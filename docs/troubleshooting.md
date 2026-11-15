# 排障

## 宿主机绝不能跑 UI 测试

如果没有可用虚拟机，就停在构建/单元测试验证。不要“先在宿主机上试一下”——本项目明确只允许 VM。宿主机运行会抢焦点、移动鼠标并截取用户桌面。

## `vmrun` 无法启动

现象：

```text
Error: vmrun was unable to start. Please make sure that vmrun is installed correctly
and that you have enough resources available on your system.
```

检查：

1. VMware Workstation 已安装并授权，`vmrun.exe` 版本匹配。
2. `VMware Workstation` / `VMware VIX` 服务正在运行。
3. 硬件虚拟化（VT-x/AMD-V）已启用，且没有被其他 hypervisor（Hyper-V、WSL2、Windows Sandbox）独占。
4. VMX 路径正确；若 VM 加密，需要可用密码。
5. 手动执行 `vmrun -T ws start "<vmx>" nogui` 查看厂商错误。

如果 `vmrun` 仍无法启动，该环境就无法验证 VM 流程。请如实报告，不要退回宿主机。

## SMB 映射失败

| 错误 | 含义 | 处理 |
| --- | --- | --- |
| `53` | 主机不可达 / 未启用共享 | 检查 IP、VM 网络，以及客户机是否已登录。 |
| `1219` | 与不同凭据的 SMB 会话冲突 | 编排器会删除并重试；关闭到同一 VM 的其他映射。 |
| `5` | 拒绝访问 | 使用客户机本地管理员并启用管理共享。 |
| `67` | 共享不存在 | 使用 `c$`，或修正 `vms[].shareName`。 |

工作组 VM 还需要允许远程管理：

```powershell
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
  /v LocalAccountTokenFilterPolicy /t REG_DWORD /d 1 /f
```

设置后重启客户机。

从宿主机测试：

```powershell
Test-Path \\192.168.221.130\c$
net use \\192.168.221.130\c$ /user:win11 '<密码>'
```

## WinSimpleSSH 端口开放但 Runner 不启动

- VM 必须**已登录且解锁**。`WTSQueryUserToken` 需要活动控制台会话；注销或锁定的 VM 没有交互式桌面。
- 在 `services.msc` 中确认服务已安装并运行（`SSHServer`）。
- 检查客户机 `server.json` 的用户/密码是否与 `pipeline.json` 一致。
- 查看 `C:\VmUiPipeline\results\console.log` 与 `exitcode.txt` 是否记录了 Runner 崩溃。
- 手动测试：

```powershell
$env:SSHC_PASSWORD = '<密码>'
external\WinSimpleSSH\src\SSHClient\bin\Release\net452\SSHC.exe exec 192.168.221.130 -u win11 --port 22222 --json "whoami"
```

## 没有 `summary.json`

如果存在，宿主机仍会复制 `console.log`、`exitcode.txt` 与 `run.log`。常见原因：

- Runner 无法加载套件（`--type` 拼写错误、缺依赖 DLL）。
- 应用在 `startupTimeoutSeconds` 内没有暴露主窗口。
- Runner 被杀毒软件或 Windows Defender 拦截。
- 进程实际运行在 session 0（启动器没有使用交互式会话）。

## 截图全黑或缺失

- 客户机已锁定，或会话已断开。保持登录。
- 分辨率/DPI 变化；把 VM 显示固定为 1920×1080、100%。
- `Graphics.CopyFromScreen` 不可用（例如非交互式会话）。
- 结果目录对 Runner 不可写。

## 录屏缺失

- `recording.enabled` 为 false。
- `ffmpegPath` 错误，或客户机没有 ffmpeg。
- ffmpeg 无法打开 `gdigrab`（没有交互式桌面）。
- `run.log` 中包含 `recording disabled: ...`。

## 应用哈希不匹配

已投放可执行文件的 SHA-256 与宿主机计算值不一致。原因可能是杀毒软件改写文件、残留的旧投放副本，或 `artifact.exe` 配置错误。Runner 会以退出码 4 结束，并在 `summary.json` 中写入错误；重新投放后重试。

## 客户机 .NET 运行时错误

请把 Runner 发布为自包含。如果选择框架依赖方式，在客户机安装匹配的 .NET 桌面运行时。

## 本机 Pester 或 `dotnet test` 失败

部分受限宿主机阻断命名管道。改用：

```powershell
dotnet build VmUiPipeline.sln -m:1 -nodeReuse:false -p:UseSharedCompilation=false
tests/VmUiPipeline.Tests/bin/Debug/net10.0-windows/VmUiPipeline.Tests.exe
Invoke-Pester -Path tests/host
```

CI 不需要这些参数。
