# VM UI Pipeline

在真实虚拟机里运行 Windows 桌面 UI 自动化测试，和你的工作机彻底解耦。

[![CI](https://github.com/wangjiati/vm-ui-pipeline/actions/workflows/ci.yml/badge.svg)](https://github.com/wangjiati/vm-ui-pipeline/actions/workflows/ci.yml)
[![License: MPL-2.0](https://img.shields.io/badge/license-MPL--2.0-blue.svg)](LICENSE)

宿主机只做编排，真正的工作都在虚拟机里完成；测试期间宿主机可以继续正常使用。

## 为什么用虚拟机

Windows 服务和 CI Agent 默认运行在 **session 0**，没有交互式桌面；而 UI Automation、SendKeys、截图、录屏都需要一个真正登录的桌面。虚拟机正好提供这个桌面，同时不占用宿主机：

- **全自动模拟用户操作**：点击、输入、勾选、选择、断言、截图、录屏。
- **不干扰宿主机**：被测应用、鼠标、焦点、截图、录屏全在客户机内；宿主机桌面不被占用。
- **真实矩阵**：Windows 10/11、不同 DPI 与语言、每次运行前回滚快照。
- **可追溯证据**：失败自动留截图；开启后留下 MP4 录像。

## 组成

| 部分 | 职责 |
| --- | --- |
| `host/VmUiPipeline` | PowerShell 编排：读配置、展开产物、SMB 投放、启动、回收结果、汇总 JUnit/Markdown |
| `VmUiPipeline.Runner` | 客户机测试宿主：启动应用、执行用例、写 `summary.json`、截图、可选录屏 |
| `VmUiPipeline.Testing` | C# UI Automation 测试库：等待、查找、输入、点击、断言、截图 |
| `samples/` | 自包含 WPF 示例应用与用例；原 Files 筛选用例保留为 `FilesFilterTests` |

## 快速开始

```powershell
# 1. 构建 Runner 与示例
dotnet publish src/VmUiPipeline.Runner -c Release -r win-x64 --self-contained true `
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o artifacts/publish
dotnet publish samples/SampleTests -c Release -o artifacts/suites/SampleTests
dotnet publish samples/SampleApp -c Release -r win-x64 --self-contained true -o artifacts/app/SampleApp

# 2. 准备 WinSimpleSSH（外部依赖，不内置二进制）
./scripts/Get-WinSimpleSsh.ps1

# 3. 准备一台已登录、可访问 \\<ip>\c$ 的 Windows VM
# 4. 复制 pipeline.sample.json（示例应用）或 pipeline.example.json（Files 套件）并修改地址与路径

$env:VM_WIN11_PASSWORD = '<客户机本地管理员密码>'
./vm-ui-pipeline.ps1 -Config .\pipeline.json -Vm win11 -RevertSnapshots
```

## 结果

```text
artifacts/results/<runId>/
├─ pipeline-summary.json
├─ junit.xml
├─ report.md
├─ run.json
└─ <vm>/
   ├─ summary.json
   ├─ run.log
   ├─ results.txt
   ├─ console.log
   ├─ session.mp4            # 开启录屏时
   └─ screenshots/*.png      # 失败自动截图
```

退出码：`0` 全部通过，`1` 用例或 VM 失败，`2` 配置/环境错误，`3` 超时。

## 截图与录屏

- 截图默认开启，全部在客户机交互会话内完成：失败自动截图、`context.CaptureScreenshot("name")`、超时截图。
- 录屏是可选项：配置 `recording.enabled`，Runner 在客户机启动 `ffmpeg` 的 `gdigrab`，输出 `session.mp4`，结束后随结果一起回传。
- ffmpeg 不随项目分发；VM 内建议 1920×1080、100% 缩放、保持登录且不锁屏。

## WinSimpleSSH 依赖

它**不是测试框架**，只负责一件事：把 `run.cmd` 放进客户机已登录用户的交互式桌面会话。

```powershell
SSHC start <vm-ip> -u <user> C:\VmUiPipeline\run.cmd
```

服务端以 LocalSystem 运行，内部调用 `WTSGetActiveConsoleSessionId`、`WTSQueryUserToken`、`CreateProcessAsUser`，并把 `lpDesktop` 设为 `WinSta0\Default`。文件传输、断言、结果、截图、录屏都与它无关。上游没有 LICENSE 文件，因此本项目**不内置**它的二进制，发布产物也不包含；请用 `scripts/Get-WinSimpleSsh.ps1` 从固定 commit 构建。

细节见 [docs/win-simple-ssh.md](docs/win-simple-ssh.md)。

## 安全

- 密码只从 `passwordEnv` 指定的环境变量读取，不写入配置、结果或日志。
- 使用 Host-only/NAT 隔离网络；`ipWhitelist` 限制到宿主机网段。
- SMB 使用客户机本地管理员账号；只对专用测试 VM 使用。
- Runner 启动前校验被测应用 SHA-256。
- 截图和录屏可能包含敏感信息，按敏感产物管理。

## 当前状态

v0.1.1 为源码版本：解决方案可构建，C# 单元测试与编排层 Pester 测试通过，VM 流程已实现。**没有在本机环境完成 VM 端到端验证**：`vmrun` 无法启动测试 VM，且本项目禁止在宿主机跑 UI 测试。请先在你自己的 VM 矩阵上跑通再依赖它。

## 许可证

Mozilla Public License 2.0。流水线源自 Files 项目的 `tools/ui-pipeline`，见 [NOTICE](NOTICE)。
