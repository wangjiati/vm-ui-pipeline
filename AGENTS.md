# Project instructions

## Hard rule: UI testing happens only inside a VM

- Never launch the application under test, run UI Automation, take screenshots, or record the screen on the host.
- The host may build, stage files, start VMs, read results, and write reports. It must not drive a UI.
- Every screenshot and recording is produced by `VmUiPipeline.Runner` inside the guest's interactive desktop session.
- If no VM is available, stop at build/unit-test verification and report the UI gap. Do not substitute the host.

## Build and test

```powershell
dotnet build VmUiPipeline.sln -c Debug -m:1 -nodeReuse:false -p:UseSharedCompilation=false
dotnet build tests/VmUiPipeline.Tests/VmUiPipeline.Tests.csproj -c Debug -p:UseSharedCompilation=false
tests/VmUiPipeline.Tests/bin/Debug/net10.0-windows/VmUiPipeline.Tests.exe
Invoke-Pester -Path tests/host
```

The `-m:1 -nodeReuse:false -p:UseSharedCompilation=false` flags work around hosts that block
named pipes; CI does not need them.

## Dependency boundary

WinSimpleSSH is an external, optional-to-vendor dependency. It is used only to start
`run.cmd` in the guest's interactive console session. Do not bundle its binaries in
release artifacts; upstream has no license file.
