# Troubleshooting

## The host must never run UI tests

If a VM is unavailable, stop at build/unit-test verification. Do not "just try it on
the host" — the project is explicitly VM-only. A host run can steal focus, move the
mouse, and capture the user's desktop.

## `vmrun` cannot start

Symptom:

```text
Error: vmrun was unable to start. Please make sure that vmrun is installed correctly
and that you have enough resources available on your system.
```

Checks:

1. VMware Workstation is installed and licensed, and `vmrun.exe` matches the version.
2. The `VMware Workstation` / `VMware VIX` services are running.
3. Hardware virtualization (VT-x/AMD-V) is enabled and not exclusively used by another
   hypervisor (Hyper-V, WSL2, Windows Sandbox).
4. The VMX path is correct and the VM is not encrypted, or its password is available.
5. Run `vmrun -T ws start "<vmx>" nogui` manually to see the vendor error.

If `vmrun` still cannot start, the VM workflow cannot be verified in that environment.
Report it; do not fall back to the host.

## SMB mapping fails

| Error | Meaning | Fix |
| --- | --- | --- |
| `53` | Host unreachable / sharing disabled | Check IP, VM network, and that the guest is logged in. |
| `1219` | Conflicting SMB session with different credentials | The orchestrator deletes and retries; close other mappings to the same VM. |
| `5` | Access denied | Use a guest local administrator and enable admin shares. |
| `67` | Share missing | Use `c$` or fix `vms[].shareName`. |

For a workgroup VM, remote admin access also needs the local account token policy:

```powershell
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
  /v LocalAccountTokenFilterPolicy /t REG_DWORD /d 1 /f
```

Reboot the guest after setting it.

Test from the host:

```powershell
Test-Path \\192.168.221.130\c$
net use \\192.168.221.130\c$ /user:win11 '<password>'
```

## WinSimpleSSH port is open but the runner never starts

- The VM must be **logged on and unlocked**. `WTSQueryUserToken` needs an active
  console session. A logged-off or locked VM has no interactive desktop.
- Confirm the service is installed and running in `services.msc` (`SSHServer`).
- Check the guest `server.json` user/password against `pipeline.json`.
- Check `C:\VmUiPipeline\results\console.log` and `exitcode.txt` for a runner crash.
- Manually test:

```powershell
$env:SSHC_PASSWORD = '<password>'
external\WinSimpleSSH\src\SSHClient\bin\Release\net452\SSHC.exe exec 192.168.221.130 -u win11 --port 22222 --json "whoami"
```

## No `summary.json`

The host copies `console.log`, `exitcode.txt`, and `run.log` if they exist. Common
causes:

- The runner could not load the suite (`--type` typo, missing dependency DLL).
- The app did not expose a main window within `startupTimeoutSeconds`.
- The runner was blocked by antivirus or Windows Defender.
- The process ran in session 0 (launcher did not use the interactive session).

## Screenshots are black or missing

- The guest is locked or the session is disconnected. Keep it logged in.
- The screen resolution/DPI changed; fix the VM display to 1920×1080 at 100%.
- `Graphics.CopyFromScreen` is unavailable (for example, a non-interactive session).
- The result directory was not writable by the runner.

## Recording is missing

- `recording.enabled` is false.
- `ffmpegPath` is wrong or ffmpeg is not on the guest.
- ffmpeg could not open `gdigrab` (no interactive desktop).
- `run.log` contains `recording disabled: ...`.

## App hash mismatch

The staged executable's SHA-256 does not match what the host computed. Causes:
antivirus rewriting the file, a stale staged copy, or a wrong `artifact.exe`. The
runner exits 4 and writes `summary.json` with the error; re-stage and rerun.

## .NET runtime errors in the guest

Publish the runner self-contained. If you chose framework-dependent, install the
matching .NET Desktop Runtime in the guest.

## Pester or `dotnet test` fails on this host

Some locked-down hosts block named pipes. Use:

```powershell
dotnet build VmUiPipeline.sln -m:1 -nodeReuse:false -p:UseSharedCompilation=false
tests/VmUiPipeline.Tests/bin/Debug/net10.0-windows/VmUiPipeline.Tests.exe
Invoke-Pester -Path tests/host
```

CI does not need these flags.
