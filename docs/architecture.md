# Architecture

## Goals

1. Execute Windows desktop UI tests in an interactive VM desktop, fully automated.
2. Keep the host free: no app launch, mouse, focus, screenshot, or recording on the host.
3. Produce durable evidence: JSON, JUnit, Markdown, PNG screenshots, optional MP4.
4. Make the VM matrix explicit and reproducible: snapshot, stage, run, collect.

## Non-goals

- Provisioning or installing guest operating systems.
- Replacing a full test framework (NUnit/xUnit) or a device farm.
- Pixel-perfect video capture or GPU/compositor benchmarking.
- macOS/Linux guests or non-Windows UI stacks.

## Components

| Component | Runs on | Responsibility |
| --- | --- | --- |
| `host/VmUiPipeline` (PowerShell) | Host | Config, staging, SMB, launcher, waiting, aggregation, JUnit, Markdown |
| `VmUiPipeline.Runner` | Guest | Load suite, launch app, run tests, write results, screenshots, recording |
| `VmUiPipeline.Testing` | Guest | UI Automation helpers, waits, assertions, result model |
| Test suite assembly | Guest | App-specific tests implementing `IUiTestSuite` |
| WinSimpleSSH | Guest | Start `run.cmd` in the interactive console session |
| SMB admin share | Guest | File transport in both directions |

## End-to-end sequence

```text
Host                                   Guest
 │                                       │
 │ 1. read pipeline.json                 │
 │ 2. expand artifact, SHA-256 app.exe   │
 │ 3. optional vmrun revert + start      │
 │ 4. map \\vm\c$ ──────────────────────►│
 │ 5. robocopy app / runner / suite ────►│ C:\VmUiPipeline\{app,runner,suite}
 │ 6. robocopy fixtures ────────────────►│ C:\FilterTest (or configured)
 │ 7. write run.cmd ────────────────────►│ C:\VmUiPipeline\run.cmd
 │ 8. install WinSimpleSSH if needed ───►│ service on :22222
 │ 9. SSHC start run.cmd ───────────────►│ interactive desktop
 │                                       │ 10. runner launches app
 │                                       │ 11. UI Automation + assertions
 │                                       │ 12. screenshots / ffmpeg
 │ 13. poll \\vm\c$\...\summary.json ◄───│ 13. write summary.json
 │ 14. copy results ◄────────────────────│
 │ 15. aggregate + JUnit + report.md     │
```

## Staging layout

```text
C:\VmUiPipeline\
├─ app\                 # artifact (directory contents)
├─ runner\              # runner directory (EXE + deps)
├─ suite\               # suite directory (DLL + dependencies)
├─ fixtures\            # optional staging area
├─ results\             # summary.json, run.log, results.txt, screenshots, session.mp4
├─ ssh\                 # SSHServer.exe + server.json
└─ run.cmd              # generated launch script
```

Fixtures can target a path outside `guestRoot` (for example `C:\FilterTest`) via
`fixtures[].destination`.

## Why SMB and not WinSimpleSSH file transfer

WinSimpleSSH can transfer files, but SMB is faster for a directory tree, already
required for admin access, and keeps the dependency surface small: WinSimpleSSH only
launches processes. `robocopy /MIR /MT:8` handles large portable app payloads.

## Why JSON over the boundary

The runner writes `summary.json` atomically (`.tmp` then move). The host polls for it
and copies the whole result directory. JSON is language-neutral, easy to inspect, and
already the contract for the suite result. JUnit is generated on the host so CI
consumers do not need a guest-side converter.

### `summary.json` schema (v1)

```json
{
  "schemaVersion": 1,
  "runId": "20261115-205549",
  "machine": {
    "name": "WIN11",
    "os": "Microsoft Windows 10.0.26100",
    "architecture": "X64",
    "user": "win11",
    "sessionId": 1
  },
  "app": { "path": "C:\\VmUiPipeline\\app\\Files.exe", "sha256": "...", "version": "4.3.3.3" },
  "startedUtc": "2026-11-15T12:55:49.980Z",
  "finishedUtc": "2026-11-15T12:56:37.670Z",
  "durationMs": 47690.0,
  "passed": 4,
  "failed": 0,
  "skipped": 1,
  "tests": [
    {
      "name": "launch",
      "status": "passed",
      "durationMs": 1.1,
      "detail": "ok"
    },
    {
      "name": "filter",
      "status": "failed",
      "durationMs": 120.0,
      "detail": "expected 2 zips, got 1",
      "screenshots": ["C:\\VmUiPipeline\\results\\screenshots\\...png"]
    }
  ],
  "error": null,
  "recording": "C:\\VmUiPipeline\\results\\session.mp4"
}
```

Statuses are `passed`, `failed`, `skipped`. A skipped test is not a failure.

## Test lifecycle

```csharp
public sealed class SampleSuite : IUiTestSuite
{
    public string Name => "SampleApp";

    public void Run(UiTestContext context)
    {
        context.Test("launch", () => { /* context.App, context.MainWindow */ });
        context.Test("filter", () =>
        {
            var box = context.Require(context.WaitForId("KeywordBox", TimeSpan.FromSeconds(5)), "keyword box");
            context.SetText(box, "zip");
            context.Invoke(context.Require(context.FindById("ApplyButton"), "apply"));
            context.WaitForCount(() => ReadCount(context), 2, TimeSpan.FromSeconds(5), "zip matches");
        });
    }
}
```

- A test body throws to fail; `UiAssertionException` is the conventional assertion
  error.
- `UiSkipException` (or `context.Skip`) marks a test skipped.
- The runner catches per-test exceptions, records a failure screenshot, and continues.
- A runner-level watchdog writes a timeout report, captures the desktop, stops the
  recorder, and exits with code 3.

## Screenshots

`VmUiPipeline.Testing.ScreenshotCapture` uses
`System.Windows.Forms.Screen.PrimaryScreen` and `Graphics.CopyFromScreen`, saving PNG
files under `<out>/screenshots/`. Because the runner is in the guest's interactive
session, this captures the guest desktop only.

Limits:

- Primary monitor only.
- A locked or disconnected guest session produces black or no output. Keep the VM
  logged in and unlocked.
- DPI scaling changes pixel dimensions; fix the VM to 100% for comparable evidence.

## Recording

`ScreenRecorder` starts `ffmpeg` with:

```text
-f gdigrab -framerate <fps> -i desktop -t <timeout+30>
-c:v libx264 -preset ultrafast -crf 28 -pix_fmt yuv420p session.mp4
```

It stops with `q` on stdin so the MP4 trailer is written, then kills the process if it
does not exit within 15 seconds. Recording is best-effort: if ffmpeg is missing, the
run continues and logs the reason. The `-t` cap prevents an orphaned encoder if the
runner is killed.

## Failure handling

| Failure | Result |
| --- | --- |
| Config invalid | PowerShell throws before staging; exit 2 from the entry script |
| SMB unreachable | Per-VM error result; other VMs still run |
| WinSimpleSSH bootstrap fails | Per-VM error result |
| Runner missing | `console.log` / `exitcode.txt` copied back; failure result |
| Test fails | Failure recorded, screenshot, suite continues |
| Suite throws | Runner-level error, exit 1; report includes `error` |
| Timeout | Exit 3; `timeout` screenshot; recorder stopped |
| App hash mismatch | Exit 4; no test run |

The aggregate exit code is `3` if any VM timed out, else `1` if any failure, else `0`.

## Verification model

CI runs build and unit tests only. It never launches a UI. UI verification requires a
VM and is therefore a manual/release-gate step:

```powershell
./vm-ui-pipeline.ps1 -Config .\pipeline.json -Vm win11 -RevertSnapshots
```

A green build is not evidence that the UI works. The report, screenshots, and video
are the evidence.
