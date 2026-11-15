## Summary

<!-- What changed and why. Link issues with "Fixes #123". -->

## Verification

- [ ] `dotnet build VmUiPipeline.sln -c Release`
- [ ] `tests/VmUiPipeline.Tests/bin/Release/net10.0-windows/VmUiPipeline.Tests.exe`
- [ ] `tests/run-host-tests.ps1`
- [ ] VM run completed; result directory attached or summarized below
- [ ] No UI automation, screenshot, or recording was performed on the host

### VM run details

- Guest:
- Display / DPI:
- Recording:
- Result: `X passed, Y failed, Z skipped`
- Artifacts:

## Checklist

- [ ] Docs updated (`README.md`, `README.zh-CN.md`, `docs/`)
- [ ] No secrets, `server.json`, screenshots, videos, or WinSimpleSSH binaries committed
- [ ] `summary.json` remains schema-version compatible
