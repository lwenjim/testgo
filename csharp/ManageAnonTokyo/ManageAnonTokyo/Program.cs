using System;
using System.IO;
using System.Text.RegularExpressions;

namespace ManageAnonTokyo {
    internal class Program {
        static void Main(string[] args) {
//            string data = $@"
//Error: 2026-04-15T09:59:41.916159Z 0 [System] [MY-013169] [Server] D:\bin\bin\mysql\bin\mysqld (mysqld 8.0.45) initializing of server in progress as process 3984
//2026-04-15T09:59:41.953544Z 1 [System] [MY-013576] [InnoDB] InnoDB initialization has started.
//2026-04-15T09:59:48.565100Z 1 [System] [MY-013577] [InnoDB] InnoDB initialization has ended.
//2026-04-15T09:59:53.192699Z 6 [Note] [MY-010454] [Server] A temporary password is generated for root@localhost: rd3mM(hr*wYK
//";          
//            data = File.ReadAllText(@"data.log");
//            Match match = Regex.Match(data, @"A temporary password is generated for root@localhost:(.+)");
//            if (match.Success) {
//                string tempPassword = match.Groups[1].Value;
//                Console.WriteLine($"Temporary password found: {tempPassword}");
//            } else {
//                Console.WriteLine("No temporary password found.");
//            }
//            Console.ReadLine();
            InstallService.Run(args);
        }
    }
}
