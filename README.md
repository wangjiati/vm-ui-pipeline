# VM UI Pipeline

Run Windows desktop UI automation tests inside real virtual machines — completely
decoupled from the machine you work on.

[![CI](https://github.com/wangjiati/vm-ui-pipeline/actions/workflows/ci.yml/badge.svg)](https://github.com/wangjiati/vm-ui-pipeline/actions/workflows/ci.yml)
[![License: MPL-2.0](https://img.shields.io/badge/license-MPL--2.0-blue.svg)](LICENSE)
[![.NET 10](https://img.shields.io/badge/.NET-10-512bd4.svg)](https://dotnet.microsoft.com/)
[![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-5391fe.svg)](https://learn.microsoft.com/powershell/)

The host orchestrates. The VM does the work. Your desktop stays usable.

```text
┌──────────────────────── host (no UI automation) ────────────────────────┐
│ PowerShell orchestrator                                                 │
│   • expands the artifact and verifies SHA-256                           │
│   • stages app / runner / suite / fixtures over SMB ──────────┐         │
│   • starts run.cmd through WinSimpleSSH ──────────────────┐   │         │
│   • collects JSON, JUnit XML, screenshots, MP4 ◄──────────┼───┼─────┐   │
└───────────────────────────────────────────────────────────┼───┼─────┼───┘
                                                            │   │     │
┌──────────────────────── VM (interactive desktop) ─────────▼───▼─────┼───┐
│  C:\VmUiPipeline\run.cmd                                            │   │
│    └─ VmUiPipeline.Runner                                           │   │
│         ├─ launches the application under test                      │   │
│         ├─ drives it with UI Automation                             │   │
│         ├─ writes summary.json / run.log                            │   │
│         ├─ captures PNG screenshots on failure                      │   │
│         └─ optionally records session.mp4 with ffmpeg               │   │
└─────────────────────────────────────────────────────────────────────┴───┘
```

## Why a VM

Windows services and CI agents run in **session 0**, which has no interactive desktop.
UI Automation, SendKeys, screenshots, and video capture need a real logged-on desktop.
A VM gives you that desktop without taking over the host:

- **Fully automated user simulation** — click, type, toggle, select, assert, capture.
- **No interference** — the app, the mouse, the focus, the screenshots, and the
  recording all live inside the VM. You can keep working on the host.
- **A real matrix** — Windows 10 and Windows 11 guests, different DPI and locale
  settings, snapshotted and reset for each run.
- **Evidence** — a failure leaves a screenshot and, when enabled, a video.

## Features

- Stage a portable app (directory or `.zip`) and fixtures over SMB; verify the app
  hash inside the guest before running it.
- Revert a VMware snapshot before a run, then start the VM headless.
- Launch the runner in the guest's logged-on console session via WinSimpleSSH.
- Reusable C# UI Automation harness (`VmUiPipeline.Testing`) with waits, assertions,
  control patterns, and per-failure screenshots.
- Optional MP4 recording through ffmpeg `gdigrab`, all inside the guest.
- Machine-readable results, JUnit XML for CI, and a Markdown report.
- Multi-VM aggregation with per-VM pass/fail and clear exit codes.
- The Files filter acceptance suite is preserved as a sample.

## Requirements

**Host**

- Windows 10/11, PowerShell 5.1 or PowerShell 7.
- .NET 10 SDK for building the runner and suites (not needed at test time if you use
  the self-contained runner).
- VMware Workstation with test VMs, if you use `-RevertSnapshots`.
- [WinSimpleSSH](https://github.com/wangjiati/WinSimpleSSH) built from source. See
  [docs/win-simple-ssh.md](docs/win-simple-ssh.md).

**Guest**

- Windows 10/11, a logged-on local administrator.
- SMB admin share reachable (`\\<ip>\c$`) and TCP 445 open.
- WinSimpleSSH service installed on first use (the orchestrator does this).
- .NET 10 desktop runtime only if you publish the runner framework-dependent. The
  documented publish command is self-contained, so normally nothing is needed.
- Optional: `ffmpeg.exe` on the guest for recording.

## Quick start

### 1. Build the runner and the sample suite

```powershell
dotnet publish src/VmUiPipeline.Runner -c Release -r win-x64 --self-contained true `
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o artifacts/publish

dotnet publish samples/SampleTests -c Release -o artifacts/suites/SampleTests
dotnet publish samples/SampleApp -c Release -r win-x64 --self-contained true -o artifacts/app/SampleApp
```

### 2. Get WinSimpleSSH

```powershell
./scripts/Get-WinSimpleSsh.ps1
```

The script clones the pinned upstream commit and builds `SSHC.exe` and
`SSHServer.exe` with MSBuild. The binaries are not redistributed by this project.

### 3. Prepare a VM

- Install Windows 10/11, log in as a local administrator, and keep the desktop
  unlocked. A locked or logged-off VM has no interactive session to launch into.
- Confirm `\\<vm-ip>\c$` is reachable from the host.
- Allow TCP 445 (SMB) and the WinSimpleSSH port (default 22222) through the guest
  firewall. The orchestrator installs the service on first use.
- Set the display to a deterministic size (for example 1920×1080, 100% scaling) if
  you rely on screenshots or recording.

### 4. Write `pipeline.json`

Copy [pipeline.sample.json](pipeline.sample.json) for the self-contained sample, or
[pipeline.example.json](pipeline.example.json) for the Files filter suite. Adjust the
paths, VM addresses, and credential environment variable names.

```json
{
  "schemaVersion": 1,
  "guestRoot": "C:\\VmUiPipeline",
  "artifact": { "path": "artifacts\\app\\SampleApp", "exe": "SampleApp.exe" },
  "runner": { "path": "artifacts\\publish\\VmUiPipeline.Runner.exe" },
  "suite": {
    "assembly": "artifacts\\suites\\SampleTests\\SampleTests.dll",
    "type": "SampleTests.SampleSuite"
  },
  "launcher": {
    "type": "win-simple-ssh",
    "sshcPath": "external\\WinSimpleSSH\\src\\SSHClient\\bin\\Release\\net452\\SSHC.exe",
    "sshServerExe": "external\\WinSimpleSSH\\src\\SSHServer\\bin\\Release\\net452\\SSHServer.exe",
    "port": 22222,
    "ipWhitelist": ["192.168.221.*"]
  },
  "vms": [
    {
      "name": "win11",
      "address": "192.168.221.130",
      "user": "win11",
      "passwordEnv": "VM_WIN11_PASSWORD",
      "vmx": "D:\\VMs\\Win11\\Win11.vmx",
      "snapshot": "initial"
    }
  ],
  "recording": { "enabled": true, "ffmpegPath": "C:\\tools\\ffmpeg\\bin\\ffmpeg.exe", "fps": 10 },
  "timeoutMinutes": 10
}
```

### 5. Run

```powershell
$env:VM_WIN11_PASSWORD = '<guest local admin password>'
powershell -NoProfile -ExecutionPolicy Bypass -File .\vm-ui-pipeline.ps1 `
  -Config .\pipeline.json -Vm win11
```

Add `-RevertSnapshots` to reset each VM to its snapshot first. Use `-OutputDirectory`
to choose where results land.

## Results

```text
artifacts/results/<runId>/
├─ pipeline-summary.json     # aggregate, per-VM counts, exit code
├─ junit.xml                 # for CI test-report ingestion
├─ report.md                 # human-readable summary
├─ run.json                  # what was run
└─ <vm>/
   ├─ summary.json           # guest runner output
   ├─ run.log                # timestamped guest log
   ├─ results.txt            # PASSED|name|detail lines
   ├─ console.log            # stdout/stderr of the runner
   ├─ session.mp4            # when recording is enabled
   └─ screenshots/*.png      # automatic failure captures
```

Exit codes: `0` all passed, `1` a test or VM failed, `2` configuration or environment
error, `3` timeout.

## Screenshots and recording

Screenshots are **on by default** and are taken inside the guest:

- automatically when a test fails;
- manually with `context.CaptureScreenshot("name")`;
- on timeout.

Recording is opt-in:

```json
"recording": {
  "enabled": true,
  "ffmpegPath": "C:\\tools\\ffmpeg\\bin\\ffmpeg.exe",
  "fps": 10
}
```

The runner starts `ffmpeg` with the `gdigrab` desktop input, records
`C:\VmUiPipeline\results\session.mp4`, and stops it gracefully after the suite. The
MP4 is copied back with the rest of the results. ffmpeg is not bundled. In a VM,
10–15 fps is usually enough; recording is evidence, not a frame-accurate benchmark.

## WinSimpleSSH dependency

WinSimpleSSH is **not a test framework**. It is the transport that starts one process
in the VM's logged-on desktop session:

```powershell
SSHC start <vm-ip> -u <user> C:\VmUiPipeline\run.cmd
```

Its Windows service (`SSHServer.exe`, LocalSystem) calls
`WTSGetActiveConsoleSessionId`, `WTSQueryUserToken`, and `CreateProcessAsUser` with
`lpDesktop = "WinSta0\Default"`. That is the only reason it is here. Everything else
is independent:

| Concern | Owner |
| --- | --- |
| Move app / runner / suite / fixtures | SMB |
| Launch in the interactive session | WinSimpleSSH |
| Launch the app, drive UI, assert | `VmUiPipeline.Runner` + `VmUiPipeline.Testing` |
| Write results, screenshots, video | `VmUiPipeline.Runner` |
| Aggregate, JUnit, Markdown, exit code | host PowerShell module |

The upstream project has no license file, so this repository does **not** vendor it
and release artifacts do not contain it. Build it from the pinned commit with
`scripts/Get-WinSimpleSsh.ps1`, or point `sshcPath` / `sshServerExe` at your own
build. See [docs/win-simple-ssh.md](docs/win-simple-ssh.md) for the exact contract,
bootstrap steps, and failure modes.

## Security

- Credentials come from environment variables named in `passwordEnv`. They are never
  written to `pipeline.json`, result files, or logs.
- Use an isolated host-only or NAT VM network. WinSimpleSSH listens on the VM and
  authenticates with the configured user; restrict `ipWhitelist` to the host subnet.
- The SMB mapping uses the guest local administrator. Use a dedicated test VM, not a
  production machine.
- The runner verifies the staged application's SHA-256 before launching it.
- Treat screenshots and recordings as potentially sensitive: they capture the guest
  desktop.

## Project layout

```text
src/VmUiPipeline.Testing/   UI Automation harness and result model
src/VmUiPipeline.Runner/    guest-side test host (single-file EXE)
host/VmUiPipeline/          PowerShell orchestrator module
samples/SampleApp/          self-contained WPF app for smoke tests
samples/SampleTests/        sample suite (launch, filter, recurse, clear, screenshot)
samples/FilesFilterTests/   original Files filter acceptance suite
tests/VmUiPipeline.Tests/   C# unit tests
tests/host/                 Pester tests for the orchestrator
docs/                       architecture, configuration, dependency, security
```

## Status

v0.1.1 is a source release. The solution builds, the C# unit tests and the
orchestrator Pester tests pass, and the VM workflow is implemented. The end-to-end VM
run has **not** been verified in the environment where this project was extracted:
`vmrun` could not start the test VMs there, and host-side UI testing is intentionally
forbidden. Run it against your own VM matrix before relying on it. See
[docs/architecture.md](docs/architecture.md) for the failure and verification model.

## License

Mozilla Public License 2.0. The pipeline is derived from the Files project's
`tools/ui-pipeline`; see [NOTICE](NOTICE).
