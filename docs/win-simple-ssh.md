# WinSimpleSSH 依赖契约

WinSimpleSSH 是外部项目：<https://github.com/wangjiati/WinSimpleSSH>。
本项目在 `scripts/Get-WinSimpleSsh.ps1` 中固定提交 `8f40f29c76f81e2c50fcd3fa49a26ab7ba0f8cfe`，但不内置其源码或二进制。

## 它用来做什么

只做一件事：

```powershell
SSHC start <vm-ip> -u <user> --port 22222 C:\VmUiPipeline\run.cmd
```

该命令让客户机上的 WinSimpleSSH 服务在**已登录用户的交互式控制台会话**中启动 `run.cmd`。随后 Runner 启动应用、驱动 UI Automation、写结果、截图，并按需录屏。

普通远程执行通道（SSH、WinRM、不带 `-i` 的 PsExec、CI Agent、非交互式计划任务）会落在 session 0。session 0 没有桌面，UI Automation 找不到窗口。这就是引入该依赖的全部原因。

## 上游如何完成启动

`SSHServer.exe` 以 Windows 服务（LocalSystem）运行。在 `src/SSHServer/Service/ProcessLauncher.cs` 中，它：

1. 调用 `WTSGetActiveConsoleSessionId()` 找到活动控制台会话；
2. 调用 `WTSQueryUserToken(sessionId, out userToken)` 获取该用户的令牌；
3. 调用 `CreateProcessAsUser(...)`，并设置 `si.lpDesktop = "WinSta0\\Default"`。

结果是一个位于交互式桌面的进程，而不是 session 0 进程。

`SSHC.exe start` 是发起后即返回（fire-and-forget），不会等待进程结束。宿主机改为通过 SMB 等待 `summary.json`。

## 流水线使用到的接口

| 调用 | 用途 |
| --- | --- |
| `SSHC start` | 在交互式会话中启动 `C:\VmUiPipeline\run.cmd`。 |
| `SSHC exec` | 运行前结束残留的 `Files.exe` / `VmUiPipeline.Runner.exe`。 |
| `SSHServer.exe --install` | 通过 WMI `Win32_Process.Create` 安装一次服务。 |

密码通过 `SSHC_PASSWORD` 进程环境变量传给 `SSHC`，不作为命令行参数。服务的 `server.json` 必须包含相同的用户与密码，客户端才能通过认证。

## 编排器执行的安装流程

工作组虚拟机需要允许远程 SMB 管理与 WMI 进程创建：

```powershell
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
  /v LocalAccountTokenFilterPolicy /t REG_DWORD /d 1 /f
```

在客户机执行一次并重启。已加入域并使用域管理员的虚拟机不需要。

首次运行某台 VM（端口未开放）时，`Initialize-VmSshService` 会：

1. 把 `SSHServer.exe` 复制到 `\\<vm>\c$\VmUiPipeline\ssh\SSHServer.exe`；
2. 在 `\\<vm>\c$\VmUiPipeline\ssh\server.json` 写入端口、IP 白名单和配置的用户/密码；
3. 使用客户机本地管理员凭据，通过 WMI `Win32_Process.Create` 远程执行
   `cmd.exe /c "C:\VmUiPipeline\ssh\SSHServer.exe" --install`；
4. 最多等待 90 秒，直到端口开放。

如果端口已经开放，编排器认为服务已安装，不会重写 `server.json`。修改密码或白名单后，请手动重启服务。

## 它不负责什么

- 传文件。宿主机使用 SMB（`\\<vm>\c$`）。
- 判定通过/失败。`VmUiPipeline.Runner` 负责测试执行与结果。
- 调度、重试、聚合、JUnit、Markdown。
- 截图或录屏。Runner 在客户机内完成。
- 测试逻辑。任何测试代码都不引用 WinSimpleSSH。

如果要替换成其他交互式会话启动器，只需改 `host/VmUiPipeline/launchers/WinSimpleSsh.ps1`。其余部分的契约与启动器无关：投放文件、在客户机桌面会话执行一条命令、等待一个 JSON 文件。

## 获取方式

```powershell
./scripts/Get-WinSimpleSsh.ps1
```

脚本会：

1. 把固定提交克隆到 `external/WinSimpleSSH`（已加入 gitignore）；
2. 用 MSBuild 以 Release 构建 `WinSimpleSSH.sln`；
3. 打印生成的 `SSHC.exe` 与 `SSHServer.exe` 路径。

上游项目面向 .NET Framework 4.5.2，需要 Visual Studio 或 MSBuild。如果 MSBuild 不可用，请在 Visual Studio 中构建解决方案，再把 `launcher.sshcPath` / `launcher.sshServerExe` 指向你的二进制。

## 许可证

上游仓库没有 `LICENSE` 文件。因此本项目不复制、不引入 submodule、不分发 WinSimpleSSH，发布 ZIP 也不包含它。克隆/构建脚本只是为了方便用户自行获取。若要在自己的环境中再分发，请先审阅上游仓库条款。

## 失败模式

| 现象 | 可能原因 | 处理 |
| --- | --- | --- |
| `SSHC start` 非零退出 | 服务未安装、端口被拦、密码错误 | 检查服务、防火墙与 `server.json`；重新安装。 |
| 22222 端口开放但认证失败 | `server.json` 中的用户/密码与配置不一致 | 更新 `server.json` 并重启服务。 |
| Runner 一直不启动 | VM 注销或锁定；没有活动控制台会话 | 登录并解锁 VM；运行期间保持登录。 |
| `SSHC start` 返回 0 但没有结果 | Runner 在写 `summary.json` 前崩溃 | 查看结果目录中的 `console.log` 与 `run.log`。 |
| `WTSQueryUserToken` 失败 | 服务不是 LocalSystem，或没有控制台会话 | 以 LocalSystem 重新安装服务；以交互方式登录。 |

完整检查清单见 [troubleshooting.md](troubleshooting.md)。
