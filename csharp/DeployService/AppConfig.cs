using System;

namespace ManageAnonTokyo {
    /// <summary>
    /// 运行期配置。所有路径/监听地址均可通过环境变量覆盖，避免改代码重新编译。
    /// </summary>
    public static class AppConfig {
        public static string BinPath { get; } = GetEnv("DEPLOY_BIN_PATH", "D:\\bin\\bin");
        public static string DomainExpose { get; } = GetEnv("DEPLOY_LISTEN_PREFIX", "http://*:80/");
        public static string ServiceName { get; } = GetEnv("DEPLOY_SERVICE_NAME", "AnonTokyoManage");
        public static string LogDirectory { get; } = GetEnv("DEPLOY_LOG_DIRECTORY", "D:\\bin\\logs");
        public static string SiriusDevRoot { get; } = GetEnv(
            "DEPLOY_SIRIUS_ROOT",
            "D:\\workdata\\sirius-client-dev\\bili-tools\\master-tools\\master_output");

        public static string DefaultIndex { get; } = "index.html";
        public static string CborDirectoryName { get; } = "mastercbor";
        public static string AtConfigDirectoryName { get; } = "atmastercbor";
        public static string LogFileName { get; } = "deploy-service-.log";

        public static int DownloadTimeoutMilliseconds { get; } = 60000;
        public static int ServiceStopTimeoutSeconds { get; } = 60;
        public static int ServiceStartTimeoutSeconds { get; } = 30;

        private static string GetEnv(string name, string fallback) {
            string? value = Environment.GetEnvironmentVariable(name);
            return string.IsNullOrWhiteSpace(value) ? fallback : value;
        }
    }
}
