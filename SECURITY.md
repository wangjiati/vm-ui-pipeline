# Security policy

## Supported versions

| Version | Supported |
| --- | --- |
| 0.1.x | Yes |

## Reporting a vulnerability

Do not open a public issue. Use GitHub's private vulnerability reporting:
<https://github.com/wangjiati/vm-ui-pipeline/security/advisories/new>.

Include:

- the affected component (host module, runner, harness, docs);
- reproduction steps and the configuration shape (redact passwords);
- impact, especially if it allows escaping the guest, executing on the host, or
  disclosing credentials;
- any suggested fix.

You will get an acknowledgement as soon as possible. Please allow time for a fix and
a coordinated disclosure.

## Scope

In scope:

- Host-side command injection through configuration or guest-controlled files.
- Credential disclosure in logs, results, or errors.
- Guest-to-host escape or unintended host UI interaction.
- Path traversal in staging, fixtures, or result collection.
- Weak defaults that expose WinSimpleSSH beyond the test network.

Out of scope:

- Vulnerabilities in WinSimpleSSH upstream (report them to that project).
- Vulnerabilities in VMware, Windows, or ffmpeg.
- The inherent risk of running a LocalSystem remote-launch service on an untrusted
  network; use an isolated lab network.
- Denial of service against your own test VM.
