using Microsoft.Win32;
using Serilog;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;

namespace ManageAnonTokyo {
    /// <summary>
    /// 网络诊断信息输出（IP、掩码、DNS、系统代理）。
    /// </summary>
    public static class NetworkInfo {
        public static void PrintNetworkInfo() {
            Log.Information("Network Information");

            PrintIpInfo();
            PrintDnsServers();
            PrintProxyInfo();

            Console.WriteLine();
        }

        private static void PrintIpInfo() {
            string hostName = Dns.GetHostName();
            IPAddress[] addresses = Dns.GetHostAddresses(hostName);
            var validAddresses = addresses.Where(ip =>
                ip.AddressFamily == AddressFamily.InterNetwork && !IPAddress.IsLoopback(ip));

            string ipAddress = "";
            string subnetMask = "";
            foreach (var address in validAddresses) {
                if (ipAddress.Length < address.ToString().Length) {
                    ipAddress = address.ToString();
                    subnetMask = GetSubnetMaskForIP(address)?.ToString() ?? "";
                }
            }

            Log.Information("IP Address:  {IP}", ipAddress);
            Log.Information("Net Mask:    {Mask}", subnetMask);
        }

        private static void PrintDnsServers() {
            foreach (var dns in GetAllDnsServers()) {
                Log.Information("DNS Server:  {DNS}", dns);
            }
        }

        private static void PrintProxyInfo() {
            var proxyInfo = SystemProxyInfo.GetFromRegistry();
            Log.Information("Proxy Enabled:  {Enabled}", proxyInfo.Enabled);
            Log.Information("Proxy Server:   {Server}", proxyInfo.Server);
        }

        private static IPAddress? GetSubnetMaskForIP(IPAddress ip) {
            foreach (NetworkInterface ni in NetworkInterface.GetAllNetworkInterfaces()) {
                if (ni.OperationalStatus != OperationalStatus.Up) {
                    continue;
                }
                foreach (UnicastIPAddressInformation ipInfo in ni.GetIPProperties().UnicastAddresses) {
                    if (ipInfo.Address.Equals(ip)) {
                        return ipInfo.IPv4Mask;
                    }
                }
            }
            return null;
        }

        private static List<IPAddress> GetAllDnsServers() {
            var dnsList = new List<IPAddress>();
            foreach (NetworkInterface ni in NetworkInterface.GetAllNetworkInterfaces()) {
                if (ni.OperationalStatus != OperationalStatus.Up ||
                    ni.NetworkInterfaceType == NetworkInterfaceType.Loopback) {
                    continue;
                }
                IPInterfaceProperties ipProps = ni.GetIPProperties();
                foreach (var dns in ipProps.DnsAddresses) {
                    if (dns.AddressFamily == AddressFamily.InterNetwork) {
                        dnsList.Add(dns);
                    }
                }
            }
            return dnsList.Distinct().ToList();
        }
    }

    public class SystemProxyInfo {
        public bool Enabled { get; set; }
        public string Server { get; set; } = "";
        public string Override { get; set; } = "";
        public bool AutoDetect { get; set; }
        public string AutoConfigUrl { get; set; } = "";

        public static SystemProxyInfo GetFromRegistry() {
            var info = new SystemProxyInfo();
            const string keyPath = @"Software\Microsoft\Windows\CurrentVersion\Internet Settings";
            using (RegistryKey? registryKey = Registry.CurrentUser.OpenSubKey(keyPath)) {
                if (registryKey != null) {
                    info.Enabled = Convert.ToInt32(registryKey.GetValue("ProxyEnable", 0)) == 1;
                    info.Server = registryKey.GetValue("ProxyServer", "")?.ToString() ?? "";
                    info.Override = registryKey.GetValue("ProxyOverride", "")?.ToString() ?? "";
                    info.AutoDetect = Convert.ToInt32(registryKey.GetValue("AutoDetect", 0)) == 1;
                    info.AutoConfigUrl = registryKey.GetValue("AutoConfigURL", "")?.ToString() ?? "";
                }
            }
            return info;
        }
    }
}
