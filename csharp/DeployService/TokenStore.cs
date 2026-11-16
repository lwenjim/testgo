using Microsoft.IdentityModel.Tokens;
using System;
using System.Collections.Concurrent;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;

namespace ManageAnonTokyo {
    /// <summary>
    /// 登录令牌的签发与校验。令牌存储为并发字典，并在签发时清理过期项，避免无限增长。
    /// </summary>
    public static class TokenStore {
        private const long TokenTtlSeconds = 300;
        private static readonly ConcurrentDictionary<string, long> Tokens = new();

        public static string Issue() {
            string token = GenerateToken();
            Tokens[token] = DateTimeOffset.Now.ToUnixTimeSeconds();
            CleanupExpired();
            return token;
        }

        public static bool TryValidate(string token, out string error) {
            if (!Tokens.TryGetValue(token, out long issuedAt)) {
                error = "not exists";
                return false;
            }
            if (DateTimeOffset.Now.ToUnixTimeSeconds() - issuedAt > TokenTtlSeconds) {
                Tokens.TryRemove(token, out _);
                error = "token expired";
                return false;
            }
            error = "";
            return true;
        }

        private static void CleanupExpired() {
            long now = DateTimeOffset.Now.ToUnixTimeSeconds();
            foreach (var entry in Tokens) {
                if (now - entry.Value > TokenTtlSeconds) {
                    Tokens.TryRemove(entry.Key, out _);
                }
            }
        }

        private static string GenerateToken() {
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

            return new JwtSecurityTokenHandler().WriteToken(token);
        }
    }
}
