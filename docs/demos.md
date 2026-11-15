# 示例演示：截图与录屏

这两个演示都在 **Windows 11 虚拟机**（`192.168.221.130`）里真实执行。宿主机只负责构建、投放与回收结果，没有在宿主机上启动被测应用或截取桌面。

## 演示内容

演示套件 `samples/DemoTests/DemoSuite.cs` 驱动 `samples/SampleApp` 完成四个步骤：

| 步骤 | 操作 | 截图 |
| --- | --- | --- |
| `01-launch` | 启动示例应用，确认主窗口 | [win11-01-launch.png](assets/demos/win11-01-launch.png) |
| `02-filter` | 在关键字框输入 `zip`，点击 Apply，断言 2 项 | [win11-02-filter.png](assets/demos/win11-02-filter.png) |
| `03-recurse` | 勾选“Search subfolders”，断言 4 项 | [win11-03-recurse.png](assets/demos/win11-03-recurse.png) |
| `04-clear` | 点击 Clear，断言恢复 3 项 | [win11-04-clear.png](assets/demos/win11-04-clear.png) |

每一步都由 Runner 调用 `context.CaptureScreenshot(...)` 在客户机内截图。录屏演示还会由 Runner 在客户机内启动 ffmpeg `gdigrab`，生成 `session.mp4`。

## 录屏效果

![录屏演示](assets/demos/session.gif)

[下载 MP4](assets/demos/session.mp4)（H.264，1440×900，8.3 秒，10 fps）。

> 为了让录屏干净，Runner 启动前会隐藏客户机桌面上残留的控制台窗口；`run.cmd` 也通过 `wscript.exe` 以隐藏窗口运行。

## 运行

```powershell
# 宿主机上设置 win11 客户机本地管理员密码
$env:VM_WIN11_PASSWORD = '<密码>'

# 截图 + 录屏；需要宿主机 PATH 中有 ffmpeg
.\demos\run-demo.ps1 -Mode both
```

也可以只跑其中一种：

```powershell
.\demos\run-demo.ps1 -Mode screenshot
.\demos\run-demo.ps1 -Mode recording
```

脚本会构建 Runner、示例应用与演示套件，然后调用 `vm-ui-pipeline.ps1`。结果在：

```text
artifacts/demos/<runId>/win11/
├─ summary.json
├─ run.log
├─ results.txt
├─ screenshots/
│  ├─ <time>-01-launch.png
│  ├─ <time>-02-filter.png
│  ├─ <time>-03-recurse.png
│  └─ <time>-04-clear.png
└─ session.mp4          # 仅录屏模式
```

## 直接使用配置文件

```powershell
.\vm-ui-pipeline.ps1 -Config .\demos\screenshot.pipeline.json
.\vm-ui-pipeline.ps1 -Config .\demos\recording.pipeline.json
```

两个配置都使用：

- `guestRoot`：`C:\VmUiPipeline`
- 客户机：`win11` / `192.168.221.130`
- 启动器：WinSimpleSSH（`external/WinSimpleSSH`）
- 录屏：`C:\VmUiPipeline\ffmpeg\ffmpeg.exe`，10 fps

## 换到 Win10 或别的 VM

复制任一配置，修改：

```json
"vms": [
  {
    "name": "win10",
    "address": "192.168.221.128",
    "user": "win10",
    "passwordEnv": "VM_WIN10_PASSWORD"
  }
]
```

然后设置 `$env:VM_WIN10_PASSWORD`，运行：

```powershell
.\vm-ui-pipeline.ps1 -Config .\demos\screenshot.win10.pipeline.json
```

## 说明

- 截图来自真实客户机桌面，分辨率由 VM 显示设置决定（本次为 1440×900）。
- 录屏是证据，不是帧级性能基准；VM 内 10 fps 足够看清操作步骤。
- ffmpeg 与 WinSimpleSSH 都不随仓库分发；演示脚本只负责把本机的 ffmpeg 投放到客户机。
- 演示配置使用 `artifacts/demo` 下的构建产物；该目录被 gitignore，不提交。
