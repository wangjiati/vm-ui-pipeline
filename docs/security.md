# Security model

This is a test lab tool. Treat the host, the guest, and the network between them as a
single trusted test environment, not as production infrastructure.

## Assets

- Guest local administrator credentials.
- The application under test and its test data.
- Screenshots and recordings of the guest desktop.
- The WinSimpleSSH service, which can start processes as the logged-on user.

## Credentials

- Passwords are read from the environment variable named by `vms[].passwordEnv`.
- The orchestrator passes the password to `SSHC.exe` through the `SSHC_PASSWORD`
  process environment variable, not as an argument.
- WinSimpleSSH requires the password in the guest's `server.json`. The file is written
  over SMB and remains on the guest. Protect it with guest filesystem ACLs and delete
  it when the VM is retired.
- SMB uses `net use \\<ip>\c$` with the guest local administrator. The mapping is
  removed after the run.
- Passwords are not written to `pipeline.json`, `run.json`, `summary.json`, JUnit, or
  logs. Review logs before sharing them.

## Network

- Use a host-only or NAT VM network. Do not expose the WinSimpleSSH port to a corporate
  LAN or the internet.
- Restrict `launcher.ipWhitelist` to the host subnet.
- Restrict guest firewall rules for 445 and 22222 to the host address.
- Prefer a dedicated test VM with no domain join, no user data, and no production
  credentials.
- Revert to a known snapshot before a run to remove leftovers.

## Least privilege

- The guest account must be a local administrator because SMB admin shares, WMI
  process creation, and service installation require it. Do not use a domain admin.
- WinSimpleSSH runs as LocalSystem. Its IP allowlist and password are the only
  authentication in front of process creation as the logged-on user. This is why the
  network must be isolated.
- The host process needs permission to map SMB and run `vmrun`; it does not need to be
  elevated beyond that.

## Supply chain

- WinSimpleSSH is pinned to a commit and built locally; no upstream binary is trusted
  or redistributed.
- ffmpeg is a user-supplied guest binary. Verify its source and hash if required.
- NuGet dependencies are limited to MSTest for the unit-test project. The runner and
  harness use the Windows Desktop framework.

## Evidence and privacy

Screenshots and videos capture whatever is on the guest desktop. They can contain
test data, notifications, account names, or secrets. Store results accordingly:
restrict access, set retention, and delete them when no longer needed.

## Reporting a vulnerability

Do not open a public issue for a vulnerability. Follow [SECURITY.md](../SECURITY.md).
