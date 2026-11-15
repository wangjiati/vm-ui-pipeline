# 贡献指南

感谢参与。请先阅读硬约束。

## 硬约束：UI 测试只在虚拟机内执行

- 禁止在宿主机上启动被测应用、执行 UI 自动化、截图或录屏。
- 宿主机只负责构建、投放、启动虚拟机、收集结果和写报告。
- 如果没有可用虚拟机，就停在构建/单元测试验证并说明缺口，不要用宿主机替代。

## 构建

```powershell
dotnet build VmUiPipeline.sln -c Debug
```

如果宿主机阻断命名管道（受限的 Windows 环境），改用：

```powershell
dotnet build VmUiPipeline.sln -c Debug -m:1 -nodeReuse:false -p:UseSharedCompilation=false
```

## 测试

```powershell
dotnet build tests/VmUiPipeline.Tests/VmUiPipeline.Tests.csproj -c Debug -p:UseSharedCompilation=false
tests/VmUiPipeline.Tests/bin/Debug/net10.0-windows/VmUiPipeline.Tests.exe

Invoke-Pester -Path tests/host
```

这些测试不涉及 UI，不得启动任何应用。

## 虚拟机验证

涉及 UI 的改动必须有虚拟机运行结果。请在合并请求中附上结果目录，至少包含 `pipeline-summary.json`、`junit.xml`、`report.md` 与失败截图。说明客户机系统、VM 显示设置以及是否开启录屏。

## 代码规范

- C#：启用可空引用类型，使用文件级命名空间；可复用测试代码放 `VmUiPipeline.Testing`，宿主进程代码放 `VmUiPipeline.Runner`。
- PowerShell：兼容 Windows PowerShell 5.1。不要使用三元表达式、`??`、`ForEach-Object -Parallel`。优先使用模块函数，保持私有函数不导出。
- 结果：在 schema 版本 1 内保持 `summary.json` 向后兼容；新增可选字段，不要重命名既有字段。
- 不要新增宿主机 UI 启动器。唯一启动方式是虚拟机交互式会话。
- 不要提交客户机密码、`server.json`、结果产物、截图、视频或 WinSimpleSSH 二进制。

## 合并请求

- 保持改动聚焦，并写明实际执行过的验证。
- 行为或配置变化时同步更新 `README.md` 与相关 `docs/` 文档。
- 新增测试套件时放在 `samples/` 下，并说明需要的客户机夹具。

## 许可证

提交贡献即表示同意以 MPL-2.0 授权。
