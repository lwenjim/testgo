using System;
using System.CommandLine;
using System.Threading.Tasks;

namespace ManageAnonTokyo {
    // http://localhost:8082/?execName=anontokyo_server.exe
    internal class Program {
        static async Task<int> Main(string[] args) {
            var rootCommand = new RootCommand("MyApplication");
            var serviceCommand = new Command("service", "Configure the application");
            var runServiceCommand = new Command("run", "deploy and run window service");
            var daemonServiceCommand = new Command("daemon", "install window service");
            serviceCommand.Subcommands.Add(runServiceCommand);
            serviceCommand.Subcommands.Add(daemonServiceCommand);
            rootCommand.Subcommands.Add(serviceCommand);
            runServiceCommand.SetAction(async (aa) => {
                await InstallService.StartService();
            });
            daemonServiceCommand.SetAction((bb) => {
                string data = InstallService.InstallWindowServiceMain();
                if (data.Length > 0) {
                    Console.WriteLine(data);
                }
            });
            return rootCommand.Parse(args).Invoke();
        }
    }
}
