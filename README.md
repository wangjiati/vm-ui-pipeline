# VM UI Pipeline

在真实虚拟机里运行 Windows 桌面 UI 自动化测试，与你的工作机彻底解耦。

[![CI](https://github.com/wangjiati/vm-ui-pipeline/actions/workflows/ci.yml/badge.svg)](https://github.com/wangjiati/vm-ui-pipeline/actions/workflows/ci.yml)
[![License: MPL-2.0](https://img.shields.io/badge/license-MPL--2.0-blue.svg)](LICENSE)
[![.NET 10](https://img.shields.io/badge/.NET-10-512bd4.svg)](https://dotnet.microsoft.com/)
[![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-5391fe.svg)](https://learn.microsoft.com/powershell/)

宿主机只做编排，真正的工作都在虚拟机里完成；测试期间宿主机可以继续正常使用。

```text
┌──────────────────── 宿主机（不执行 UI 自动化）────────────────────┐
│ PowerShell 编排器                                                 │
│   • 展开产物并校验 SHA-256                                        │
│   • 通过 SMB 投放应用、Runner、套件与夹具 ───────────────────┐    │
│   • 通过 WinSimpleSSH 启动 run.cmd ──────────────────────┐    │    │
│   • 回收 JSON、JUnit、截图、MP4 ◄───────────────────────┼────┼────┘
└─────────────────────────────────────────────────────────┼────┼─────┘
                                                          │    │
┌──────────────────── 虚拟机（交互式桌面）────────────────▼────▼─────┐
│  C:\VmUiPipeline\run.cmd                                          │
│    └─ VmUiPipeline.Runner                                         │
│         ├─ 启动被测应用                                           │
│         ├─ 通过 UI Automation 驱动应用                            │
│         ├─ 写入 summary.json / run.log                            │
│         ├─ 失败时保存 PNG 截图                                    │
│         └─ 可选：用 ffmpeg 录制 session.mp4                       │
└────────────────────────────────────────────────────────────────────┘
```

## 为什么用虚拟机

Windows 服务与 CI Agent 默认运行在 **session 0**，没有交互式桌面；而 UI Automation、SendKeys、截图、录屏都需要一个真正登录的桌面。虚拟机正好提供这个桌面，同时不占用宿主机：

- **全自动模拟用户操作**：点击、输入、勾选、选择、断言、截图、录屏。
- **不干扰宿主机**：被测应用、鼠标、焦点、截图、录屏全部在客户机内；宿主机桌面不被占用。
- **真实矩阵**：Windows 10/11、不同 DPI 与语言，每次运行前可回滚快照。
- **可追溯证据**：失败自动留截图；开启后留下 MP4 录像。

## 功能

- 通过 SMB 投放便携应用（目录或 `.zip`）与夹具，并在客户机内校验应用哈希。
- 运行前回滚 VMware 快照，然后以无界面方式启动虚拟机。
- 通过 WinSimpleSSH 在客户机已登录的控制台会话中启动 Runner。
- 可复用的 C# UI Automation 测试库（`VmUiPipeline.Testing`）：等待、断言、控件模式、失败截图。
- 可选的 MP4 录屏：客户机内 ffmpeg `gdigrab`，不碰宿主机。
- 机器可读结果、供 CI 使用的 JUnit XML、Markdown 报告。
- 多 VM 聚合，逐 VM 统计通过/失败，退出码明确。
- 原 Files 筛选验收套件保留为示例。

## 环境要求

**宿主机**

- Windows 10/11，PowerShell 5.1 或 PowerShell 7。
- 构建 Runner 与套件需要 .NET 10 SDK；使用自包含 Runner 时，测试阶段不需要 SDK。
- 使用 `-RevertSnapshots` 时需要 VMware Workstation 与测试虚拟机。
- 需要从源码构建的 [WinSimpleSSH](https://github.com/wangjiati/WinSimpleSSH)，见 [docs/win-simple-ssh.md](docs/win-simple-ssh.md)。

**客户机**

- Windows 10/11，已登录的本地管理员账户。
- 可访问 SMB 管理共享（`\\<ip>\c$`），TCP 445 开放。
- 首次使用时由编排器安装 WinSimpleSSH 服务。
- 仅当以框架依赖方式发布 Runner 时，才需要 .NET 10 桌面运行时；文档中的发布命令是自包含的，正常无需额外安装。
- 可选：客户机上的 `ffmpeg.exe`，用于录屏。

## 快速开始

### 1. 构建 Runner 与示例套件

```powershell
dotnet publish src/VmUiPipeline.Runner -c Release -r win-x64 --self-contained true `
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o artifacts/publish

dotnet publish samples/SampleTests -c Release -o artifacts/suites/SampleTests
dotnet publish samples/SampleApp -c Release -r win-x64 --self-contained true -o artifacts/app/SampleApp
```

### 2. 获取 WinSimpleSSH

```powershell
./scripts/Get-WinSimpleSsh.ps1
```

脚本会克隆固定提交并用 MSBuild 构建 `SSHC.exe` 与 `SSHServer.exe`。本项目不分发这两个二进制。

### 3. 准备虚拟机

- 安装 Windows 10/11，以本地管理员登录，并保持桌面解锁。锁定或注销的虚拟机没有可用的交互式会话。
- 确认宿主机可以访问 `\\<vm-ip>\c$`。
- 在客户机防火墙中放行 TCP 445（SMB）与 WinSimpleSSH 端口（默认 22222）。编排器会在首次运行时安装服务。
- 如果依赖截图或录屏，把显示固定为确定的分辨率（例如 1920×1080、100% 缩放）。

### 4. 编写 `pipeline.json`

示例应用使用 [pipeline.sample.json](pipeline.sample.json)，Files 筛选套件使用 [pipeline.example.json](pipeline.example.json)。按实际情况修改路径、VM 地址与密码环境变量名。

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

### 5. 运行

```powershell
$env:VM_WIN11_PASSWORD = '<客户机本地管理员密码>'
powershell -NoProfile -ExecutionPolicy Bypass -File .\vm-ui-pipeline.ps1 `
  -Config .\pipeline.json -Vm win11
```

加上 `-RevertSnapshots` 可在运行前把每台 VM 回滚到快照。用 `-OutputDirectory` 指定结果目录。

## 结果

```text
artifacts/results/<runId>/
├─ pipeline-summary.json     # 聚合结果、逐 VM 计数、退出码
├─ junit.xml                 # 供 CI 测试报告消费
├─ report.md                 # 人类可读摘要
├─ run.json                  # 本次运行配置
└─ <vm>/
   ├─ summary.json           # 客户机 Runner 输出
   ├─ run.log                # 带时间戳的客户机日志
   ├─ results.txt            # PASSED|name|detail 行
   ├─ console.log            # Runner 标准输出/错误
   ├─ session.mp4            # 开启录屏时
   └─ screenshots/*.png      # 失败自动截图
```

退出码：`0` 全部通过，`1` 用例或 VM 失败，`2` 配置/环境错误，`3` 超时。

## 截图与录屏

截图默认开启，并且全部在客户机内完成：

- 测试失败时自动截图；
- 用例中调用 `context.CaptureScreenshot("name")`；
- 超时时截图。

录屏是可选能力：

```json
"recording": {
  "enabled": true,
  "ffmpegPath": "C:\\tools\\ffmpeg\\bin\\ffmpeg.exe",
  "fps": 10
}
```

Runner 会在客户机启动 `ffmpeg` 的 `gdigrab` 桌面输入，录制到 `C:\VmUiPipeline\results\session.mp4`，套件结束后优雅停止，MP4 随结果一起回传。ffmpeg 不随项目分发。虚拟机里 10–15 fps 通常足够；录屏是证据，不是帧级性能基准。

## WinSimpleSSH 依赖

WinSimpleSSH **不是测试框架**，只负责在虚拟机的已登录桌面会话里启动一个进程：

```powershell
SSHC start <vm-ip> -u <user> C:\VmUiPipeline\run.cmd
```

它的 Windows 服务（`SSHServer.exe`，LocalSystem）调用 `WTSGetActiveConsoleSessionId`、`WTSQueryUserToken`、`CreateProcessAsUser`，并把 `lpDesktop` 设为 `WinSta0\Default`。这是引入它的唯一原因。其余职责完全独立：

| 关注点 | 负责方 |
| --- | --- |
| 应用/ Runner / 套件 / 夹具传输 | SMB |
| 在交互式会话中启动 | WinSimpleSSH |
| 启动应用、驱动 UI、断言 | `VmUiPipeline.Runner` + `VmUiPipeline.Testing` |
| 写结果、截图、录屏 | `VmUiPipeline.Runner` |
| 聚合、JUnit、Markdown、退出码 | 宿主机 PowerShell 模块 |

上游没有 LICENSE 文件，因此本项目**不内置**它，发布产物也不包含它。请用 `scripts/Get-WinSimpleSsh.ps1` 从固定提交构建，或把 `sshcPath` / `sshServerExe` 指向你自己的构建。完整契约、安装步骤与失败模式见 [docs/win-simple-ssh.md](docs/win-simple-ssh.md)。

## 安全

- 密码只从 `passwordEnv` 指定的环境变量读取，不写入 `pipeline.json`、结果文件或日志。
- 使用隔离的 Host-only 或 NAT 虚拟机网络。WinSimpleSSH 在虚拟机内监听并校验配置用户，`ipWhitelist` 应限制到宿主机网段。
- SMB 使用客户机本地管理员。只对专用测试虚拟机使用，不要用于生产机。
- Runner 在启动前校验已投放应用的 SHA-256。
- 截图和录屏可能包含敏感信息，应按敏感产物管理。

## 项目结构

```text
src/VmUiPipeline.Testing/   UI Automation 测试库与结果模型
src/VmUiPipeline.Runner/    客户机测试宿主（单文件 EXE）
host/VmUiPipeline/          PowerShell 编排模块
samples/SampleApp/          用于冒烟测试的自包含 WPF 应用
samples/SampleTests/        示例套件（启动、筛选、递归、清除、截图）
samples/FilesFilterTests/   原 Files 筛选验收套件
tests/VmUiPipeline.Tests/   C# 单元测试
tests/host/                 编排层 Pester 测试
docs/                       架构、配置、依赖、安全与排障
```

## 当前状态

v0.1.2 为源码版本：解决方案可构建，C# 单元测试与编排层 Pester 测试通过，VM 流程已实现。**没有在本机环境完成 VM 端到端验证**：该环境的 `vmrun` 无法启动测试虚拟机，且本项目禁止在宿主机执行 UI 测试。请先在你自己的 VM 矩阵上跑通再依赖它；失败与验证模型见 [docs/architecture.md](docs/architecture.md)。

## 许可证

Mozilla Public License 2.0。流水线源自 Files 项目的 `tools/ui-pipeline`，见 [NOTICE](NOTICE)。
