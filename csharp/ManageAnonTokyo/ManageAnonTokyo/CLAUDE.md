# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A Windows service management tool that handles deployment and management of AnonTokyo server services. Built as a .NET Framework 4.7.2 console application with single-file publish configuration.

## Building the Project

**Prerequisites:** .NET Framework 4.7.2 SDK or Visual Studio 2022+

```bash
# Build Debug configuration
dotnet build -c Debug

# Build Release configuration
dotnet build -c Release

# Publish standalone executable
dotnet publish -c Release
```

The project uses MSBuild directly on Windows via `.csproj` format. Solution file: `ManageAnonTokyo.sln`

## Running Commands

The application uses System.CommandLine for CLI:

```bash
# Show help
ManageAnonTokyo --help

# Service subcommands
ManageAnonTokyo service daemon      # Install as Windows service
ManageAnonTokyo service run         # Deploy and start service

# Network diagnostics
ManageAnonTokyo service info        # Print network info (IP, DNS, proxy status)
```

Core endpoint listening at `http://*:8082/deploy/` for remote deployment operations.

## Architecture Overview

### Key Files

- **Program.cs** - Minimal entry point delegating to InstallService
- **InstallService.cs** - Main logic containing all service management functionality
- **ManageAnonTokyo.csproj** - Project configuration with NuGet dependencies

### Core Functionality (InstallService Class)

1. **Service Installation**: Uses NSSM (Non-Sucking Service Manager) to register Windows services
   - `RegisterWindowService()` - Installs executable as service
   - `UnRegisterWindowService()` - Removes service registration
   - `IsAdministrator()` - Checks admin privileges before elevation

2. **Deployment Operations**: HTTP-based remote deployment
   - `StartService()` - Listens on port 8082/deploy/ for requests
   - `ProcessRequest()` - Handles GET requests with `execName` query param
   - `Install()` - Downloads and extracts `.exe` or `.zip` packages
   - `RestartService()` - Graceful stop/start around deployments

3. **Network Utilities**:
   - `PrintNetInfo()` - Displays IP, subnet mask, DNS servers
   - `SystemProxyInfo.GetFromRegistry()` - Reads Windows registry proxy settings
   - `IsTcpPortOpenAsync()` - Port connectivity check

### Dependencies

Key NuGet packages:
- `System.CommandLine` - CLI parsing
- `Newtonsoft.Json` - JSON serialization
- `Costura.Fody` - Assembly merging (single-file publishing)
- `Microsoft.Extensions.*` - Configuration and dependency injection libraries

### File Paths (Hardcoded)

- Binary directory: `D:\bin\bin` (`GetBinPath()`)
- Web root for docs: `C:\inetpub\wwwroot`
- Deployment endpoint: `http://*.8082/deploy/`

### Service Name Mapping

Dictionary `fileMapService` maps executables to service names:
- `Anontokyo.exe` → `AnonTokyoServer`
- `AnonTokyoSiriusServer.exe/.zip` → `AnonTokyoSiriusServer`
- `AnontokyoDocs.zip` → documentation extraction to wwwroot

## Important Notes

- Requires Administrator privileges for service installation/removal
- Expects NSSM executable (`nssm.exe`) to be available in PATH
- Target runtime: Windows x64 only (`RuntimeIdentifier: win-x64`)
- Self-contained single-file publish enabled
