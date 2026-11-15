# WinSimpleSSH dependency contract

WinSimpleSSH is an external project: <https://github.com/wangjiati/WinSimpleSSH>.
This repository pins the commit `8f40f29c76f81e2c50fcd3fa49a26ab7ba0f8cfe` in
`scripts/Get-WinSimpleSsh.ps1` but does not vendor its source or binaries.

## What it is used for

Exactly one operation:

```powershell
SSHC start <vm-ip> -u <user> --port 22222 C:\VmUiPipeline\run.cmd
```

The command asks the WinSimpleSSH service on the VM to start `run.cmd` in the
**logged-on user's interactive console session**. The runner then launches the
application, drives UI Automation, writes results, takes screenshots, and optionally
records video.

A normal remote execution channel (SSH, WinRM, PsExec without `-i`, a CI agent, a
scheduled task without an interactive logon) lands in session 0. Session 0 has no
desktop, so UI Automation finds no window. That is the entire reason this dependency
exists.

## How the launch works upstream

`SSHServer.exe` runs as a Windows service (LocalSystem). In
`src/SSHServer/Service/ProcessLauncher.cs` it:

1. calls `WTSGetActiveConsoleSessionId()` to find the active console session;
2. calls `WTSQueryUserToken(sessionId, out userToken)` to get that user's token;
3. calls `CreateProcessAsUser(...)` with `si.lpDesktop = "WinSta0\\Default"`.

The result is a process on the interactive desktop, not in session 0.

`SSHC.exe start` is fire-and-forget; it does not wait for the process. The host waits
for `summary.json` over SMB instead.

## What the pipeline uses

| Call | Purpose |
| --- | --- |
| `SSHC start` | Start `C:\VmUiPipeline\run.cmd` in the interactive session. |
| `SSHC exec` | Stop stale `Files.exe` / `VmUiPipeline.Runner.exe` before a run. |
| `SSHServer.exe --install` | Install the service once, via WMI `Win32_Process.Create`. |

The password is passed to `SSHC` through the `SSHC_PASSWORD` process environment
variable, never as a command-line argument. The service's `server.json` must contain
the same user and password so the client can authenticate.

## Bootstrap performed by the orchestrator

On the first run for a VM (when the port is closed), `Initialize-VmSshService`:

1. copies `SSHServer.exe` to `\\<vm>\c$\VmUiPipeline\ssh\SSHServer.exe`;
2. writes `\\<vm>\c$\VmUiPipeline\ssh\server.json` with the port, IP allowlist, and
   the configured user/password;
3. runs `cmd.exe /c "C:\VmUiPipeline\ssh\SSHServer.exe" --install` remotely through
   WMI `Win32_Process.Create` using the guest local administrator credentials;
4. waits up to 90 seconds for the port to open.

If the port is already open, the orchestrator assumes the service is installed and
does not rewrite `server.json`. Restart the service manually after changing the
password or allowlist.

## What it is not responsible for

- Moving files. The host uses SMB (`\\<vm>\c$`).
- Deciding pass/fail. `VmUiPipeline.Runner` owns test execution and results.
- Scheduling, retries, aggregation, JUnit, Markdown.
- Screenshots or recording. The runner captures them inside the guest.
- Test logic. No test code references WinSimpleSSH.

If you replace it with another interactive-session launcher, only
`host/VmUiPipeline/launchers/WinSimpleSsh.ps1` needs to change. The rest of the
pipeline is launcher-agnostic in contract: stage files, run one command in the
guest's desktop session, wait for a JSON file.

## Acquisition

```powershell
./scripts/Get-WinSimpleSsh.ps1
```

The script:

1. clones the pinned commit into `external/WinSimpleSSH` (gitignored);
2. builds `WinSimpleSSH.sln` with MSBuild in Release;
3. prints the resulting `SSHC.exe` and `SSHServer.exe` paths.

The upstream project targets .NET Framework 4.5.2 and needs Visual Studio or
MSBuild. If MSBuild is not available, build the solution in Visual Studio and point
`launcher.sshcPath` / `launcher.sshServerExe` at your binaries.

## Licensing

The upstream repository has no `LICENSE` file. This project therefore does not copy,
submodule, or redistribute WinSimpleSSH, and release ZIPs do not contain it. The
clone/build script is only a convenience for users who choose to obtain it
themselves. Review the upstream repository's terms before redistributing it in your
own environment.

## Failure modes

| Symptom | Likely cause | Action |
| --- | --- | --- |
| `SSHC start` exits non-zero | Service not installed, port blocked, wrong password | Check the service, firewall, and `server.json`; reinstall. |
| Port 22222 open but authentication fails | `server.json` user/password differs from config | Update `server.json` and restart the service. |
| Runner never starts | VM logged off or locked; no active console session | Log in and unlock the VM; keep it logged in for the run. |
| `SSHC start` returns 0 but no result | Runner crashed before writing `summary.json` | Read `console.log` and `run.log` in the result directory. |
| `WTSQueryUserToken` fails | Service not LocalSystem, or no console session | Reinstall the service as LocalSystem; log in interactively. |

See [troubleshooting.md](troubleshooting.md) for the full checklist.
