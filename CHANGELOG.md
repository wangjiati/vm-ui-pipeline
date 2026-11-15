# Changelog

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
