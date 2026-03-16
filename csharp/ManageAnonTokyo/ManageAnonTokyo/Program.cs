using System;
using System.CommandLine;

namespace ManageAnonTokyo {
    internal class Program {
        static int Main(string[] args) {
            var root = new RootCommand("MyApplication");
            var service = new Command("service", "Configure the application");
            var daemon = new Command("daemon", "install window service");
            var run = new Command("run", "deploy and run window service");
            var netinfo = new Command("info", "print network infomation");

            run.SetAction(async (@params) => {
                await InstallService.StartService();
            });

            daemon.SetAction((@params) => {
                string data = InstallService.InstallDaemon();
                if (data.Length > 0) {
                    Console.WriteLine(data);
                }
            });

            netinfo.SetAction((@params) => {
                InstallService.PrintNetInfo();
            });

            root.Subcommands.Add(service);
            service.Subcommands.Add(daemon);
            service.Subcommands.Add(run);
            service.Subcommands.Add(netinfo);

            return root.Parse(args).Invoke();
        }
    }
}
