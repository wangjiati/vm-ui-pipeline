# 架构

## 目标

1. 在虚拟机交互式桌面里全自动执行 Windows 桌面 UI 测试。
2. 释放宿主机：宿主机不启动应用、不移动鼠标、不抢焦点、不截图、不录屏。
3. 留下可追溯证据：JSON、JUnit、Markdown、PNG 截图、可选 MP4。
4. 让 VM 矩阵明确且可复现：回滚、投放、运行、回收。

## 非目标

- 自动安装客户机操作系统。
- 替代完整测试框架（NUnit/xUnit）或设备农场。
- 像素级精确的视频采集，或 GPU/合成器性能基准。
- macOS/Linux 客户机或非 Windows UI 技术栈。

## 组件

| 组件 | 运行位置 | 职责 |
| --- | --- | --- |
| `host/VmUiPipeline`（PowerShell） | 宿主机 | 配置、投放、SMB、启动、等待、聚合、JUnit、Markdown |
| `VmUiPipeline.Runner` | 客户机 | 加载套件、启动应用、执行测试、写结果、截图、录屏 |
| `VmUiPipeline.Testing` | 客户机 | UI Automation 辅助、等待、断言、结果模型 |
| 测试套件程序集 | 客户机 | 实现 `IUiTestSuite` 的应用专用测试 |
| WinSimpleSSH | 客户机 | 在交互式控制台会话中启动 `wscript.exe` 与 `run.vbs` |
| SMB 管理共享 | 客户机 | 双向文件传输 |

## 端到端时序

```text
宿主机                                 客户机
 │                                       │
 │ 1. 读取 pipeline.json                 │
 │ 2. 展开产物，计算 app.exe SHA-256     │
 │ 3. 可选 vmrun 回滚并启动 VM           │
 │ 4. 映射 \\vm\c$ ─────────────────────►│
 │ 5. robocopy 应用/Runner/套件 ────────►│ C:\VmUiPipeline\{app,runner,suite}
 │ 6. robocopy 夹具 ────────────────────►│ C:\FilterTest（或配置路径）
 │ 7. 写入 run.cmd 与 run.vbs ──────────►│ C:\VmUiPipeline\run.cmd、run.vbs
 │ 8. 按需安装 WinSimpleSSH ────────────►│ 服务监听 :22222
 │ 9. SSHC start run.vbs ───────────────►│ 交互式桌面（隐藏控制台）
 │                                       │ 10. Runner 启动应用
 │                                       │ 11. UI Automation + 断言
 │                                       │ 12. 截图 / ffmpeg
 │ 13. 轮询 \\vm\c$\...\summary.json ◄───│ 13. 写入 summary.json
 │ 14. 复制结果 ◄────────────────────────│
 │ 15. 聚合 + JUnit + report.md          │
```

## 投放布局

```text
C:\VmUiPipeline\
├─ app\                 # 产物（目录内容）
├─ runner\              # Runner 目录（EXE 与依赖）
├─ suite\               # 套件目录（DLL 与依赖）
├─ fixtures\            # 可选夹具暂存区
├─ results\             # summary.json、run.log、results.txt、截图、session.mp4
├─ ssh\                 # SSHServer.exe 与 server.json
├─ run.cmd              # 生成的启动脚本（由 run.vbs 隐藏运行）
└─ run.vbs              # 隐藏控制台启动器
```

夹具可以通过 `fixtures[].destination` 指向 `guestRoot` 之外的路径（例如 `C:\FilterTest`）。

## 为什么用 SMB 而不是 WinSimpleSSH 传文件

WinSimpleSSH 也能传文件，但 SMB 更适合整目录传输，管理共享本来就是远程管理所需，而且能把依赖面缩到最小：WinSimpleSSH 只负责启动进程。`robocopy /MIR /MT:8` 足以处理大型便携应用。

## 为什么跨边界使用 JSON

Runner 原子写入 `summary.json`（先写 `.tmp` 再移动）。宿主机轮询该文件并复制整个结果目录。JSON 与语言无关、便于人工检查，也已经是套件结果的自然契约。JUnit 由宿主机生成，CI 消费方不需要客户机端转换器。

### `summary.json` schema（v1）

```json
{
  "schemaVersion": 1,
  "runId": "20261115-205549-123",
  "machine": {
    "name": "WIN11",
    "os": "Microsoft Windows 10.0.26100",
    "architecture": "X64",
    "user": "win11",
    "sessionId": 1
  },
  "app": { "path": "C:\\VmUiPipeline\\app\\Files.exe", "sha256": "...", "version": "4.3.3.3" },
  "startedUtc": "2026-11-15T12:55:49.980Z",
  "finishedUtc": "2026-11-15T12:56:37.670Z",
  "durationMs": 47690.0,
  "passed": 4,
  "failed": 0,
  "skipped": 1,
  "tests": [
    {
      "name": "launch",
      "status": "passed",
      "durationMs": 1.1,
      "detail": "ok"
    },
    {
      "name": "filter",
      "status": "failed",
      "durationMs": 120.0,
      "detail": "expected 2 zips, got 1",
      "screenshots": ["C:\\VmUiPipeline\\results\\screenshots\\...png"]
    }
  ],
  "error": null,
  "recording": "C:\\VmUiPipeline\\results\\session.mp4"
}
```

状态为 `passed`、`failed`、`skipped`。跳过的测试不算失败。

## 测试生命周期

```csharp
public sealed class SampleSuite : IUiTestSuite
{
    public string Name => "SampleApp";

    public void Run(UiTestContext context)
    {
        // 启动断言：Runner 已经启动应用并拿到主窗口
        context.Test("launch", () => { /* context.App、context.MainWindow */ });

        context.Test("filter", () =>
        {
            var box = context.Require(
                context.WaitForId("KeywordBox", TimeSpan.FromSeconds(5)),
                "关键字输入框");
            context.SetText(box, "zip");
            context.Invoke(context.Require(context.FindById("ApplyButton"), "应用按钮"));
            context.WaitForCount(() => ReadCount(context), 2, TimeSpan.FromSeconds(5), "zip 匹配数");
        });
    }
}
```

- 测试体抛异常即失败；约定用 `UiAssertionException` 表示断言失败。
- `UiSkipException`（或 `context.Skip`）把测试标记为跳过。
- Runner 捕获单个测试的异常，记录失败截图，然后继续执行后续测试。
- Runner 级看门狗在超时时写入报告、截取桌面、停止录屏，并以退出码 3 结束。

## 截图

`VmUiPipeline.Testing.ScreenshotCapture` 使用 `System.Windows.Forms.Screen.PrimaryScreen` 与 `Graphics.CopyFromScreen`，把 PNG 保存到 `<out>/screenshots/`。Runner 位于客户机交互式会话，因此只会截取客户机桌面。Runner 启动前会调用 `WindowHider` 隐藏客户机桌面上残留的控制台窗口，避免 `SSHC start` 留下的命令提示符污染截图与录像。

限制：

- 只截主显示器。
- 客户机会话锁定或断开时，截图可能全黑或失败。保持 VM 登录且解锁。
- DPI 缩放会改变像素尺寸；需要可比较的证据时，把 VM 固定为 100%。

## 录屏

`ScreenRecorder` 以如下参数启动 `ffmpeg`：

```text
-f gdigrab -framerate <fps> -i desktop -t <timeout+30>
-c:v libx264 -preset ultrafast -crf 28 -pix_fmt yuv420p session.mp4
```

通过向 stdin 写入 `q` 优雅停止，确保 MP4 尾部元数据写入；15 秒内未退出则强制结束。录屏是尽力而为的能力：ffmpeg 缺失只会记录原因，测试继续执行。`-t` 上限用于防止 Runner 被强杀后留下孤儿编码进程。

## 异常弹窗检测

Runner 在四个时机检查客户机桌面上可见的 `#32770` 对话框：

1. 启动应用前（`00-baseline.png` 之后）；
2. 应用主窗口出现后；
3. 每个测试通过后；
4. 套件结束后（`99-final.png` 之后）。

发现弹窗时：

- 立即截图（`existing-dialog` / `dialog-<test>` / `final-dialog`）；
- 记录弹窗标题、进程名与 PID；
- 以失败结束，Runner 退出码 `5`；
- 不自动关闭弹窗，保留现场。

这可以防止 `Files - Startup Error`、实例锁冲突、许可证提示、系统错误框等模态窗口在无人值守时静默阻塞测试。确实需要保留对话框的测试可以给 Runner 加 `--ignore-dialogs`。

## 失败处理

| 失败场景 | 结果 |
| --- | --- |
| 配置无效 | PowerShell 在投放前抛错；入口脚本退出码 2 |
| SMB 不可达 | 该 VM 记为错误，其他 VM 继续 |
| WinSimpleSSH 安装失败 | 该 VM 记为错误 |
| Runner 缺失 | 复制 `console.log` / `exitcode.txt`，记为失败 |
| 测试失败 | 记录失败、截图，套件继续 |
| 套件抛异常 | Runner 级错误，退出码 1；报告包含 `error` |
| 超时 | 退出码 3；`timeout` 截图；停止录屏 |
| 应用哈希不匹配 | 退出码 4；不执行测试 |
| 检测到异常弹窗 | 退出码 5；自动截图；不执行测试或终止当前运行 |

聚合退出码：任一 VM 超时为 `3`；否则任一失败为 `1`；否则为 `0`。

## 验证模型

CI 只构建并运行单元测试，从不启动 UI。UI 验证必须使用虚拟机，因此是手动/发布门禁步骤：

```powershell
./vm-ui-pipeline.ps1 -Config .\pipeline.json -Vm win11 -RevertSnapshots
```

构建通过不等于 UI 可用。报告、截图与录像才是证据。
