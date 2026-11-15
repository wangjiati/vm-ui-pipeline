# 配置

`pipeline.json` 由 [`schema/pipeline.schema.json`](../schema/pipeline.schema.json) 校验。相对路径以配置文件所在目录为基准；客户机路径必须是绝对 Windows 路径（`C:\...`）。

## 顶层字段

| 字段 | 类型 | 默认值 | 含义 |
| --- | --- | --- | --- |
| `schemaVersion` | 整数 | 必填 | 必须为 `1`。 |
| `guestRoot` | 字符串 | `C:\VmUiPipeline` | 客户机内的投放根目录。 |
| `artifact` | 对象 | 必填 | 应用产物。 |
| `runner` | 对象 | 必填 | 客户机测试宿主。 |
| `suite` | 对象 | 必填 | 测试套件程序集与参数。 |
| `fixtures` | 数组 | `[]` | 运行前复制到客户机的目录。 |
| `launcher` | 对象 | 必填 | 交互式会话启动器（`win-simple-ssh`）。 |
| `recording` | 对象 | 关闭 | 可选 MP4 录制。 |
| `vms` | 数组 | 必填 | 每台客户机一项。 |
| `timeoutMinutes` | 整数 | `10` | 单 VM 结果等待超时。 |
| `startupTimeoutSeconds` | 整数 | `60` | 等待应用主窗口的时间。 |
| `resultsDirectory` | 字符串 | `artifacts/results` | 宿主机结果根目录。 |

## `artifact`

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `path` | 字符串 | 包含应用的目录或 `.zip`。 |
| `exe` | 字符串 | 相对于产物根目录的可执行文件路径。 |
| `arguments` | 字符串 | 启动应用时传入的可选参数。 |
| `processName` | 字符串 | 可选的进程名覆盖，用于查找主窗口与清理残留进程。 |

宿主机计算可执行文件的 SHA-256 并传给 Runner；Runner 在不匹配时拒绝启动。

## `runner`

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `path` | 字符串 | `VmUiPipeline.Runner.exe` 的路径。会投放其整个目录。 |

自包含发布：

```powershell
dotnet publish src/VmUiPipeline.Runner -c Release -r win-x64 --self-contained true `
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o artifacts/publish
```

## `suite`

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `assembly` | 字符串 | 套件程序集路径。会投放其整个目录。 |
| `type` | 字符串 | `IUiTestSuite` 实现的完整类型名。 |
| `folder` | 字符串 | 作为 `--folder` 传入。VM 运行时必须是**客户机**路径。 |
| `ignoreDialogs` | 布尔 | 忽略异常弹窗检测，默认 `false`。仅用于确实需要保留对话框的测试。 |
| `parameters` | 对象 | 额外的 `--param key=value`，通过 `context.Parameters` 读取。 |

示例：`"type": "FilesFilterTests.FilesFilterSuite"`，`"folder": "C:\\FilterTest"`。

## `fixtures`

| 字段 | 类型 | 默认值 | 含义 |
| --- | --- | --- | --- |
| `source` | 字符串 | 必填 | 宿主机上要复制的目录。 |
| `destination` | 字符串 | 必填 | 客户机目录。绝对路径，或相对于 `guestRoot`。 |
| `clean` | 布尔 | `true` | 复制前清空目标目录。 |

夹具每次运行都会重建，保证断言看到确定的内容。

## `launcher`

只支持 `win-simple-ssh`。宿主机 UI 测试会被配置校验直接拒绝。

| 字段 | 类型 | 默认值 | 含义 |
| --- | --- | --- | --- |
| `type` | 字符串 | `win-simple-ssh` | 必须为 `win-simple-ssh`。 |
| `sshcPath` | 字符串 | 必填 | 宿主机上的 `SSHC.exe`。 |
| `sshServerExe` | 字符串 | 必填 | 投放到客户机的 `SSHServer.exe`。 |
| `port` | 整数 | `22222` | 服务端口。 |
| `ipWhitelist` | 字符串数组 | 必填 | 客户机服务白名单，例如 `["192.168.221.*"]`。 |
| `vmrunPath` | 字符串 | VMware 默认路径 | 仅在 `-RevertSnapshots` 时使用。 |

详见 [win-simple-ssh.md](win-simple-ssh.md)。

## `recording`

| 字段 | 类型 | 默认值 | 含义 |
| --- | --- | --- | --- |
| `enabled` | 布尔 | `false` | 是否为套件启动 ffmpeg。 |
| `ffmpegPath` | 字符串 | `ffmpeg.exe` | **客户机内**的 ffmpeg 路径，或 PATH 中的名称。 |
| `fps` | 整数 | `10` | `gdigrab` 帧率（1–60）。 |

输出为 `<guestRoot>\results\session.mp4`，随结果一起回传。录屏是尽力而为的能力：ffmpeg 缺失只会记录警告，测试继续。

## `vms`

| 字段 | 类型 | 默认值 | 含义 |
| --- | --- | --- | --- |
| `name` | 字符串 | 必填 | 结果中使用的稳定标识。 |
| `address` | 字符串 | 必填 | 宿主机可访问的 IPv4 地址或主机名。 |
| `user` | 字符串 | 必填 | 用于 SMB/WMI 的客户机本地管理员。 |
| `passwordEnv` | 字符串 | `VM_<NAME>_PASSWORD` | 保存密码的环境变量名。 |
| `shareName` | 字符串 | `c$` | 管理共享。 |
| `vmx` | 字符串 | 空 | `-RevertSnapshots` 使用的 VMX 路径。 |
| `snapshot` | 字符串 | 空 | `-RevertSnapshots` 使用的快照名。 |

密码不写入配置文件。请在宿主机进程中设置：

```powershell
$env:VM_WIN11_PASSWORD = '<密码>'
```

## 命令行

```powershell
./vm-ui-pipeline.ps1 -Config .\pipeline.json `
  [-Vm win10,win11] `
  [-RevertSnapshots] `
  [-OutputDirectory .\artifacts\results] `
  [-KeepWorkDirectory]
```

- `-Vm` 按 `vms[].name` 选择子集；未知名称会在运行前报错。
- `-RevertSnapshots` 停止 VM、回滚到 `snapshot`、以无界面方式启动并等待 SMB。需要 `vmx` 与 `snapshot`。
- `-KeepWorkDirectory` 保留宿主机临时展开目录，便于排查。

## 退出码

| 退出码 | 含义 |
| --- | --- |
| `0` | 所有选中的 VM 通过。 |
| `1` | 至少一个测试或 VM 失败。 |
| `2` | 任何测试开始前的配置/环境错误。 |
| `3` | 至少一个 VM 超时。 |
