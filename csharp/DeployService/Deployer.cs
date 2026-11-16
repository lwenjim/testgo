using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Net.Http;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using Serilog;

namespace ManageAnonTokyo {
    /// <summary>
    /// 包下载、版本管理与部署编排。同一服务上的部署通过服务名串行化，避免并发解压/替换互相破坏。
    /// </summary>
    public static class Deployer {
        private static readonly Dictionary<string, string> FileMapService = new() {
            {"AnontokyoServer.exe", "AnonTokyoServer"},
            {"AnonTokyoConfig.zip",  "AnonTokyoServer"},
            {"AnonTokyoSiriusServer.exe", "AnonTokyoSiriusServer"},
            {"AnonTokyoSiriusServerCbor.zip", "AnonTokyoSiriusServer"},
            {"TestGo.exe", "AnonTokyoTestGo"},
            {"AnontokyoDocs.zip", ""},
            {"AnontokyoBuildCbor.exe", "" },
            {"AnontokyoSiriusBuildCbor.exe", "" },
            {"Mysql.zip", "AnonTokyoMysql" },
            {"Redis.zip", "AnonTokyoRedis" },
        };

        private static readonly ConcurrentDictionary<string, SemaphoreSlim> PackageLocks = new();
        private static readonly HttpClient Http = CreateHttpClient();

        public static bool IsKnownPackage(string fileName) {
            return FileMapService.ContainsKey(fileName);
        }

        public static async Task<string> Install(string urlName, string version, string domainDownload) {
            try {
                if (!FileMapService.TryGetValue(urlName, out string? serviceName)) {
                    return ApiResult.Fail($"Invalid package: {urlName}");
                }

                var gate = PackageLocks.GetOrAdd(
                    string.IsNullOrEmpty(serviceName) ? urlName : serviceName,
                    _ => new SemaphoreSlim(1, 1));

                await gate.WaitAsync();
                try {
                    var info = GetPathInfo(urlName);
                    string url = $"{domainDownload}/{urlName}";

                    return await RestartService(urlName, async () => {
                        switch (Path.GetExtension(urlName).ToLowerInvariant()) {
                            case ".exe":
                                return await HandleExeInstall(url, info, version);
                            case ".zip":
                                return await HandleZipInstall(url, urlName, info, version);
                            default:
                                return ApiResult.Fail("Unsupported file type");
                        }
                    });
                } finally {
                    gate.Release();
                }
            } catch (Exception ex) {
                Log.Error(ex, "Deploy failed for {Package}", urlName);
                return ApiResult.Fail($"操作失败: {ex.Message}");
            }
        }

        private static async Task<string> HandleExeInstall(string url, PathInfo info, string version) {
            string? error = await EnsurePackageAvailableAsync(url, info, version);
            return error == null ? ApiResult.Ok() : ApiResult.Fail(error);
        }

        private static async Task<string> HandleZipInstall(string url, string urlName, PathInfo info, string version) {
            string? error = await EnsurePackageAvailableAsync(url, info, version);
            if (error != null) {
                return ApiResult.Fail(error);
            }

            switch (urlName) {
                case "AnonTokyoSiriusServerCbor.zip": {
                    string cborPath = Path.Combine(AppConfig.BinPath, AppConfig.CborDirectoryName);
                    Log.Information("Extracting CBOR to {CborPath}", cborPath);
                    FileUtil.DeleteDirectoryIfExists(cborPath);
                    ZipFile.ExtractToDirectory(info.binPath, AppConfig.BinPath);
                    return ApiResult.Ok();
                }
                case "AnonTokyoConfig.zip": {
                    Log.Information("Extracting config to {BinPath}", AppConfig.BinPath);
                    FileUtil.DeleteDirectoryIfExists(Path.Combine(AppConfig.BinPath, AppConfig.AtConfigDirectoryName));
                    ZipFile.ExtractToDirectory(info.binPath, AppConfig.BinPath);
                    return ApiResult.Ok();
                }
                case "AnontokyoDocs.zip": {
                    FileUtil.DeleteDirectoryIfExists(Path.Combine(AppConfig.BinPath, "docs"));
                    ZipFile.ExtractToDirectory(info.binPath, AppConfig.BinPath);
                    return ApiResult.Ok();
                }
                case "Mysql.zip":
                    return await InstallMysqlAsync(info);
                case "Redis.zip":
                    return InstallRedis(info);
                default:
                    return ApiResult.Fail("Unsupported package");
            }
        }

        private static async Task<string> InstallMysqlAsync(PathInfo info) {
            const string mysqlServerName = "AnonTokyoMysql";
            string mysqlDir = Path.Combine(AppConfig.BinPath, "mysql");

            if (!Directory.Exists(mysqlDir)) {
                ZipFile.ExtractToDirectory(info.binPath, AppConfig.BinPath);
            }

            if (ServiceManager.Exists(mysqlServerName)) {
                ServiceManager.StartIfStopped(mysqlServerName);
                return ApiResult.Ok();
            }

            Log.Information("Initializing MySQL data directory at {MysqlDir}", mysqlDir);
            string dataDir = Path.Combine(mysqlDir, "data");
            var init = await ProcessRunner.RunAsync(Path.Combine(mysqlDir, "bin", "mysqld"), "--initialize --console");
            if (!Directory.Exists(dataDir) && init.ExitCode != 0) {
                return ApiResult.Fail("failed to initialize");
            }

            Log.Debug("MySQL initialization output: {Output}", init.Output);
            Match match = Regex.Match(init.Output, @"A temporary password is generated for root@localhost:(.+)");
            if (!match.Success) {
                Log.Error("Failed to extract temporary password from mysqld output");
                return ApiResult.Fail(init.Output);
            }
            string tempPassword = match.Groups[1].Value.Trim();

            Log.Information("Registering MySQL service with NSSM");
            ServiceManager.Register(
                mysqlServerName,
                Path.Combine(mysqlDir, "bin", "mysqld.exe"),
                $"--defaults-file=\"{Path.Combine(mysqlDir, "bin", "my.ini")}\"");

            Log.Information("Starting MySQL service and waiting for it to be running");
            ServiceManager.StartAndWait(mysqlServerName);

            if (!await PortWatcher.WaitForPortAsync("localhost", 3306, timeoutSeconds: 60)) {
                Log.Error("MySQL did not start within the expected time");
                return ApiResult.Fail("MySQL did not start within the expected time.");
            }

            Log.Information("Resetting MySQL root password");
            await ProcessRunner.RunAsync(
                Path.Combine(mysqlDir, "bin", "mysql"),
                $"-u root --connect-expired-password -p\"{tempPassword}\" -e \"ALTER USER 'root'@'localhost' IDENTIFIED BY '';\"");

            Log.Information("Granting remote access to MySQL root user");
            await ProcessRunner.RunAsync(
                Path.Combine(mysqlDir, "bin", "mysql"),
                "-u root -e \"create USER 'root'@'%' IDENTIFIED BY '';\"");
            await ProcessRunner.RunAsync(
                Path.Combine(mysqlDir, "bin", "mysql"),
                "-u root -e \"GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION; FLUSH PRIVILEGES;\"");

            return ApiResult.Ok();
        }

        private static string InstallRedis(PathInfo info) {
            const string redisServerName = "AnonTokyoRedis";
            string redisDir = Path.Combine(AppConfig.BinPath, "redis");

            ServiceManager.StopIfRunning(redisServerName);

            if (!Directory.Exists(redisDir)) {
                Log.Information("Extracting Redis to {RedisDir}", redisDir);
                ZipFile.ExtractToDirectory(info.binPath, AppConfig.BinPath);
            }

            if (ServiceManager.Exists(redisServerName)) {
                Log.Information("Redis service already exists, starting if stopped");
                ServiceManager.StartIfStopped(redisServerName);
                return ApiResult.Ok();
            }

            Log.Information("Registering Redis service with NSSM");
            ServiceManager.Register(
                redisServerName,
                Path.Combine(redisDir, "redis-server.exe"),
                $"\"{Path.Combine(redisDir, "redis.windows.conf")}\"");

            ServiceManager.StartAndWait(redisServerName);
            return ApiResult.Ok();
        }

        /// <summary>
        /// 确保目标文件已就位：优先使用 history 中的同版本文件，否则下载新版本并把旧文件归档。
        /// 返回 null 表示成功，否则返回错误信息。
        /// </summary>
        private static async Task<string?> EnsurePackageAvailableAsync(string url, PathInfo info, string version) {
            if (!IsKnownPackage(Path.GetFileName(info.binPath))) {
                return "Invalid package";
            }
            if (string.IsNullOrWhiteSpace(version)) {
                return "empty version";
            }

            string binDirPath = Path.GetDirectoryName(info.binPath)!;
            string filename = Path.GetFileName(info.binPath);
            string extension = Path.GetExtension(info.binPath);

            if (version == "-1") {
                version = FindLatestLocalVersion(binDirPath, filename, extension) ?? "";
                if (version.Length == 0) {
                    return "no local version found";
                }
            }
            if (!IsSafeVersion(version)) {
                return $"invalid version: {version}";
            }

            string historyDir = Path.Combine(binDirPath, "history");
            Directory.CreateDirectory(historyDir);
            string versionFilename = Path.Combine(historyDir, $"{filename}-{version}{extension}");

            if (File.Exists(versionFilename)) {
                File.Copy(versionFilename, info.binPath, overwrite: true);
                return null;
            }

            string tempFile = info.binPath + ".download";
            if (!await DownloadFileAsync(url, tempFile)) {
                FileUtil.DeleteIfExists(tempFile);
                return "download failed";
            }

            try {
                if (File.Exists(info.binPath)) {
                    File.Move(info.binPath, versionFilename, overwrite: true);
                }
                File.Move(tempFile, info.binPath, overwrite: true);
            } catch {
                FileUtil.DeleteIfExists(tempFile);
                throw;
            }
            return null;
        }

        private static bool IsSafeVersion(string version) {
            return Regex.IsMatch(version, @"^[0-9A-Za-z._-]+$");
        }

        private static string? FindLatestLocalVersion(string binDirPath, string filename, string extension) {
            long max = 0;
            foreach (string file in Directory.GetFiles(binDirPath, $"{filename}*{extension}", SearchOption.TopDirectoryOnly)) {
                string[] parts = Path.GetFileName(file).Split('-', '.');
                if (parts.Length < 3 || !long.TryParse(parts[2], out long value)) {
                    continue;
                }
                if (value > max) {
                    max = value;
                }
            }
            return max > 0 ? max.ToString() : null;
        }

        public static async Task<string> RestartService(string urlName, Func<Task<string>> handler) {
            if (!FileMapService.TryGetValue(urlName, out string? serviceName) || string.IsNullOrEmpty(serviceName)) {
                Log.Debug("No associated service for {UrlName}, skipping service restart", urlName);
                return await handler();
            }

            Log.Information("Restarting service {ServiceName} for {UrlName}", serviceName, urlName);
            try {
                ServiceManager.StopIfRunning(serviceName);

                string result = await handler();

                if (Path.GetExtension(urlName).Equals(".exe", StringComparison.OrdinalIgnoreCase)
                    && !ServiceManager.Exists(serviceName)) {
                    Log.Information("Registering service {ServiceName}", serviceName);
                    ServiceManager.Register(
                        serviceName,
                        Path.Combine(AppConfig.BinPath, Path.GetFileName(urlName)));
                }
                return result;
            } finally {
                ServiceManager.StartIfStopped(serviceName);
            }
        }

        public static PathInfo GetPathInfo(string urlName) {
            return new PathInfo { binPath = Path.Combine(AppConfig.BinPath, urlName) };
        }

        public static async Task<bool> DownloadFileAsync(string url, string filePath) {
            Log.Information("Starting download from {Url} to {FilePath}", url, filePath);
            try {
                using var response = await Http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead);
                response.EnsureSuccessStatusCode();
                await using var responseStream = await response.Content.ReadAsStreamAsync();
                await using var fileStream = File.Create(filePath);
                await responseStream.CopyToAsync(fileStream);
                return true;
            } catch (Exception ex) {
                Log.Error(ex, "Download failed from {Url}", url);
                return false;
            }
        }

        private static HttpClient CreateHttpClient() {
            var client = new HttpClient {
                Timeout = TimeSpan.FromMilliseconds(AppConfig.DownloadTimeoutMilliseconds)
            };
            client.DefaultRequestHeaders.UserAgent.ParseAdd("Mozilla/5.0");
            return client;
        }
    }

    public class PathInfo {
        public required string binPath;
    }
}
