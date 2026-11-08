using System;
using System.Net.Sockets;
using System.Threading;
using System.Threading.Tasks;

namespace ManageAnonTokyo {
    public static class PortWatcher {
        /// <summary>
        /// 等待指定主机的端口变为监听状态，避免阻塞线程。
        /// </summary>
        public static async Task<bool> WaitForPortAsync(
            string host,
            int port,
            int timeoutSeconds = 30,
            int retryIntervalMilliseconds = 1000,
            CancellationToken cancellationToken = default) {
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            cts.CancelAfter(TimeSpan.FromSeconds(timeoutSeconds));

            while (!cts.IsCancellationRequested) {
                if (await IsPortOpenAsync(host, port, retryIntervalMilliseconds / 2, cts.Token)) {
                    return true;
                }
                try {
                    await Task.Delay(retryIntervalMilliseconds, cts.Token);
                } catch (OperationCanceledException) {
                    return false;
                }
            }
            return false;
        }

        public static async Task<bool> IsPortOpenAsync(
            string host,
            int port,
            int timeoutMilliseconds = 3000,
            CancellationToken cancellationToken = default) {
            try {
                using var client = new TcpClient();
                using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
                cts.CancelAfter(timeoutMilliseconds);
                await client.ConnectAsync(host, port, cts.Token);
                return client.Connected;
            } catch {
                return false;
            }
        }
    }
}
