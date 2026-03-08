using System.Threading.Tasks;

namespace ManageAnonTokyo {
    // http://localhost:8082/?execName=anontokyo_server.exe
    internal class Program {
        static async Task Main(string[] args) {
            await InstallService.StartService();
        }
    }
}
