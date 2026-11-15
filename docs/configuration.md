# Configuration

`pipeline.json` is validated by [`schema/pipeline.schema.json`](../schema/pipeline.schema.json).
Relative paths are resolved against the configuration file's directory. Guest paths
must be absolute Windows paths (`C:\...`).

## Top level

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `schemaVersion` | integer | required | Must be `1`. |
| `guestRoot` | string | `C:\VmUiPipeline` | Staging root inside the guest. |
| `artifact` | object | required | Application payload. |
| `runner` | object | required | Guest test host. |
| `suite` | object | required | Test suite assembly and arguments. |
| `fixtures` | array | `[]` | Directories copied to the guest before the run. |
| `launcher` | object | required | Interactive-session launcher (`win-simple-ssh`). |
| `recording` | object | disabled | Optional MP4 capture. |
| `vms` | array | required | One entry per guest. |
| `timeoutMinutes` | integer | `10` | Per-VM result timeout. |
| `startupTimeoutSeconds` | integer | `60` | Time allowed for the app's main window. |
| `resultsDirectory` | string | `artifacts/results` | Base directory for host-side results. |

## `artifact`

| Field | Type | Meaning |
| --- | --- | --- |
| `path` | string | Directory or `.zip` containing the app. |
| `exe` | string | Executable path relative to the artifact root. |
| `arguments` | string | Optional arguments passed to the app at launch. |
| `processName` | string | Optional process name override for window discovery and stale-process cleanup. |

The host computes the SHA-256 of the executable, passes it to the runner, and the
runner refuses to launch on mismatch.

## `runner`

| Field | Type | Meaning |
| --- | --- | --- |
| `path` | string | Path to `VmUiPipeline.Runner.exe`. Its whole directory is staged. |

Publish it self-contained:

```powershell
dotnet publish src/VmUiPipeline.Runner -c Release -r win-x64 --self-contained true `
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o artifacts/publish
```

## `suite`

| Field | Type | Meaning |
| --- | --- | --- |
| `assembly` | string | Path to the suite assembly. Its whole directory is staged. |
| `type` | string | Full name of the `IUiTestSuite` implementation. |
| `folder` | string | Passed as `--folder`. For VM runs this is a **guest** path. |
| `parameters` | object | Extra `--param key=value` pairs exposed via `context.Parameters`. |

Example: `"type": "FilesFilterTests.FilesFilterSuite"`, `"folder": "C:\\FilterTest"`.

## `fixtures`

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `source` | string | required | Host directory to copy. |
| `destination` | string | required | Guest directory. Absolute, or relative to `guestRoot`. |
| `clean` | boolean | `true` | Remove existing destination contents first. |

Fixtures are recreated per run, so assertions see deterministic content.

## `launcher`

Only `win-simple-ssh` is supported. Host-side UI testing is rejected by design.

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `type` | string | `win-simple-ssh` | Must be `win-simple-ssh`. |
| `sshcPath` | string | required | `SSHC.exe` on the host. |
| `sshServerExe` | string | required | `SSHServer.exe` staged to the guest. |
| `port` | integer | `22222` | Service port. |
| `ipWhitelist` | string[] | required | Guest service allowlist, for example `["192.168.221.*"]`. |
| `vmrunPath` | string | VMware default | Used only with `-RevertSnapshots`. |

See [win-simple-ssh.md](win-simple-ssh.md).

## `recording`

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `enabled` | boolean | `false` | Start ffmpeg for the suite. |
| `ffmpegPath` | string | `ffmpeg.exe` | ffmpeg path **inside the guest** (or a PATH name). |
| `fps` | integer | `10` | `gdigrab` frame rate (1–60). |

Output is `<guestRoot>\results\session.mp4` and is copied back with the results.
Recording is best-effort: a missing ffmpeg logs a warning and the tests still run.

## `vms`

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `name` | string | required | Stable identifier used in results. |
| `address` | string | required | IPv4 address or host name reachable from the host. |
| `user` | string | required | Guest local administrator for SMB/WMI. |
| `passwordEnv` | string | `VM_<NAME>_PASSWORD` | Environment variable holding the password. |
| `shareName` | string | `c$` | Admin share. |
| `vmx` | string | empty | VMX path for `-RevertSnapshots`. |
| `snapshot` | string | empty | Snapshot name for `-RevertSnapshots`. |

Passwords are never stored in the configuration. Set them in the host process:

```powershell
$env:VM_WIN11_PASSWORD = '<password>'
```

## CLI

```powershell
./vm-ui-pipeline.ps1 -Config .\pipeline.json `
  [-Vm win10,win11] `
  [-RevertSnapshots] `
  [-OutputDirectory .\artifacts\results] `
  [-KeepWorkDirectory]
```

- `-Vm` selects a subset by `vms[].name`; unknown names fail before running.
- `-RevertSnapshots` stops the VM, reverts to `snapshot`, starts it headless, and waits
  for SMB. Requires `vmx` and `snapshot`.
- `-KeepWorkDirectory` keeps the host temp expansion for inspection.

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | All selected VMs passed. |
| `1` | At least one test or VM failed. |
| `2` | Configuration/environment error before any test. |
| `3` | At least one VM timed out. |
