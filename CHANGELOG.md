# Changelog

## 0.1.1

- Fix Pester 5 scoping by loading host-test helpers inside each `Describe`.
- Stop and finalize the MP4 recorder before `summary.json` becomes visible, so the
  host never copies an open video file.
- Map guest screenshot paths to the host result directory in the Markdown report.
- Require an explicit guest user instead of defaulting to the host account.
- Add the workgroup local-account token policy to the dependency and troubleshooting
  docs.

## 0.1.0

Initial source release.

- Host PowerShell module: configuration, artifact expansion, SHA-256 verification,
  SMB staging, snapshot revert, multi-VM aggregation, JUnit, Markdown.
- `VmUiPipeline.Runner`: loads a suite assembly, launches the app, records results,
  captures failure screenshots, optionally records MP4 with ffmpeg.
- `VmUiPipeline.Testing`: UI Automation harness with waits, control patterns,
  assertions, skip support, and screenshot capture.
- WinSimpleSSH launcher adapter with service bootstrap and IP allowlist.
- Samples: self-contained WPF app and suite; original Files filter suite.
- Unit tests (MSTest) and host tests (Pester); CI workflow.
