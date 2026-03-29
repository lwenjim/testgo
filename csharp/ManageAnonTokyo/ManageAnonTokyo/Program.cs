using Microsoft.IdentityModel.Tokens;
using Newtonsoft.Json;
using System;
using System.Collections.Generic;
using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Security.Claims;
using System.Text;
using System.Threading;

namespace ManageAnonTokyo {
    internal class Program {
        static Dictionary<string, Int64> tokens = new Dictionary<string, Int64>();
        static int Main(string[] args) {
            HttpListener listener = new HttpListener();
            listener.Prefixes.Add("http://localhost:8080/");
            listener.Start();
            while (true) {
                HttpListenerContext context = listener.GetContext();
                ThreadPool.QueueUserWorkItem((o) => ProcessRequest(context));
            }
            //return InstallService.Run(args);
            return 0;
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
            Response(response, 500, "empty");
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
            // 1. 定义安全密钥（实际应从配置中读取）
            var secretKey = "your-256-bit-secret-key-here-which-is-long-enough";
            var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(secretKey));
            var credentials = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

            // 2. 设置声明（用户信息）
            var claims = new[]
            {
            new Claim(JwtRegisteredClaimNames.Sub, "user123"),
            new Claim(JwtRegisteredClaimNames.Email, "user@example.com"),
            new Claim(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString()),
            new Claim("role", "admin") // 自定义声明
        };

            // 3. 配置令牌参数
            var token = new JwtSecurityToken(
                issuer: "your-app-name",          // 签发者
                audience: "your-api",             // 接收者
                claims: claims,
                expires: DateTime.UtcNow.AddHours(1), // 过期时间
                signingCredentials: credentials
            );

            // 4. 生成字符串格式的 Token
            var tokenString = new JwtSecurityTokenHandler().WriteToken(token);
            return tokenString;
        }
    }
}
