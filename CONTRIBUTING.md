# Contributing

Thanks for helping. Please read the hard rule first.

## Hard rule: UI testing happens only inside a VM

- Never launch the application under test, run UI Automation, take screenshots, or
  record the screen on the host.
- The host may build, stage, start VMs, collect results, and write reports.
- If a VM is unavailable, stop at build/unit-test verification and report the gap.
  Do not substitute the host.

## Build

```powershell
dotnet build VmUiPipeline.sln -c Debug
```

If your machine blocks named pipes (a locked-down Windows host), use:

```powershell
dotnet build VmUiPipeline.sln -c Debug -m:1 -nodeReuse:false -p:UseSharedCompilation=false
```

## Tests

```powershell
dotnet build tests/VmUiPipeline.Tests/VmUiPipeline.Tests.csproj -c Debug -p:UseSharedCompilation=false
tests/VmUiPipeline.Tests/bin/Debug/net10.0-windows/VmUiPipeline.Tests.exe

Invoke-Pester -Path tests/host
```

These are non-UI tests. They must not launch an application.

## VM verification

A UI change needs a VM run. Attach the result directory (or at least
`pipeline-summary.json`, `junit.xml`, `report.md`, and the failure screenshot) to the
pull request. State the guest OS, VM display settings, and whether recording was on.

## Code guidelines

- C#: nullable enabled, file-scoped namespaces, `VmUiPipeline.Testing` for reusable
  harness code, `VmUiPipeline.Runner` for the host process.
- PowerShell: Windows PowerShell 5.1 compatible. No ternaries, no `??`, no
  `ForEach-Object -Parallel`. Use the module functions; keep private helpers private.
- Results: keep `summary.json` backward compatible within schema version 1. Add
  optional fields rather than renaming.
- Do not add a host-side UI launcher. The only launcher is the VM interactive session.
- Do not commit guest passwords, `server.json`, result artifacts, screenshots, videos,
  or WinSimpleSSH binaries.

## Pull requests

- Keep the change focused and include the verification you ran.
- Update `README.md`, `README.zh-CN.md`, and the relevant `docs/` page when behavior or
  configuration changes.
- For a new test suite, add it under `samples/` and document the required guest fixture.

## License

By contributing you agree that your contribution is licensed under MPL-2.0.
