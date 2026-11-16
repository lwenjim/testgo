# Project Rules

## Auto Approve Commands

All terminal/shell commands should be auto-approved without requiring user confirmation. This includes:
- `dotnet build`, `dotnet run`, `dotnet test`
- `git add`, `git commit`, `git push`, `git status`, `git diff`
- `npm`, `node`, `python`, `pip`
- File system operations (`mkdir`, `del`, `copy`, `move`)
- Any other shell commands

When running commands, always set `requires_approval: false`.

## Build & Lint

- Build command: `dotnet build`
- Project type: C# .NET 8.0 (Windows)