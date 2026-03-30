using ManageAnonTokyo;
using Microsoft.IdentityModel.Tokens;
using Newtonsoft.Json;
using System;
using System.Collections.Generic;
using System.IdentityModel.Tokens.Jwt;
using System.IO;
using System.Net;
using System.Security.Claims;
using System.Text;
using System.Threading;


namespace AnonTokyoManage {
    internal class Jmeter {
        static Dictionary<string, Int64> tokens = new Dictionary<string, Int64>();
        public static void Run() {
            HttpListener listener = new HttpListener();
            listener.Prefixes.Add("http://localhost:8081/");
            listener.Start();
            while (true) {
                HttpListenerContext context = listener.GetContext();
                ThreadPool.QueueUserWorkItem((o) => ProcessRequest(context));
            }
        }

        private static void ProcessRequest(HttpListenerContext context) {
            var request = context.Request;
            var response = context.Response;
            switch (request.Url.AbsolutePath) {
                case "/login":
                    string[] usernames = request.QueryString.GetValues("username");
                    string[] passwords = request.QueryString.GetValues("password");
                    if (usernames.Length == 0 || passwords.Length == 0) {
                        Response(response, 500, "error params");
                        return;
                    }
                    var token = GenerateToken();
                    tokens.Add(token, DateTimeOffset.Now.ToUnixTimeSeconds());
                    response.Headers.Add("token", token);
                    Response(response, 200, token);
                    return;
                case "/info":
                    string[] t = request.QueryString.GetValues("token");
                    if (t.Length == 0 || t[0].Length == 0) {
                        Response(response, 500, "error params");
                        return;
                    }
                    if (!tokens.ContainsKey(t[0])) {
                        Response(response, 500, "not exists");
                        return;
                    }
                    if (DateTimeOffset.Now.ToUnixTimeSeconds() - tokens[t[0]] > 300) {
                        Response(response, 500, "token expired");
                        return;
                    }
                    Response(response, 200, "ok");
                    return;
            }
            string filename = $"{AppConfig.BinPath}\\{request.Url.AbsolutePath}";
            if (File.Exists(filename)) {
                response.ContentType = "application/octet-stream";
                response.OutputStream.Write(File.ReadAllBytes(filename), 0, (int)new FileInfo(filename).Length);
                response.OutputStream.Close();
                return;
            }
            response.ContentType = "text/html; charset=utf-8";
            DirectoryInfo info = new DirectoryInfo(AppConfig.BinPath);
            StringBuilder sb = new StringBuilder();
            foreach (var item in info.GetFiles()) {
                sb.AppendLine($"<a href=\"{item.Name}\">{item.Name}</a><br>");
            }
            string data = $"<html><body>{sb.ToString()}</body></html>";
            byte[] buffer = Encoding.UTF8.GetBytes(data);
            response.ContentLength64 = buffer.Length;
            response.OutputStream.Write(buffer, 0, buffer.Length);
            response.OutputStream.Close();
            return;
        }
        public class Result {
            public string Code { get; set; }
            public string Data { get; set; }
            public string Message { get; set; }
        }

        private static void Response(HttpListenerResponse response, Int32 code, string responseString) {
            var data = new Result {
                Code = $"{code}",
                Data = responseString,
                Message = "success"
            };

            byte[] buffer = Encoding.UTF8.GetBytes($"{JsonConvert.SerializeObject(data)}\n");
            response.ContentType = "text/html; charset=utf-8";
            response.ContentLength64 = buffer.Length;
            response.OutputStream.Write(buffer, 0, buffer.Length);
            response.OutputStream.Close();
        }

        public static string GenerateToken() {
            var secretKey = "your-256-bit-secret-key-here-which-is-long-enough";
            var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(secretKey));
            var credentials = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

            var claims = new[]{
            new Claim(JwtRegisteredClaimNames.Sub, "user123"),
            new Claim(JwtRegisteredClaimNames.Email, "user@example.com"),
            new Claim(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString()),
            new Claim("role", "admin")
            };

            var token = new JwtSecurityToken(
                issuer: "your-app-name",
                audience: "your-api",
                claims: claims,
                expires: DateTime.UtcNow.AddHours(1),
                signingCredentials: credentials
            );

            var tokenString = new JwtSecurityTokenHandler().WriteToken(token);
            return tokenString;
        }
    }
}
