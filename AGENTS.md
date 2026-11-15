# 项目说明

## 硬约束：UI 测试只在虚拟机内执行

- 禁止在宿主机上启动被测应用、执行 UI 自动化、截图或录屏。
- 宿主机只负责构建、投放、启动虚拟机、读取结果和写报告，不得驱动 UI。
- 所有截图和录屏都由 `VmUiPipeline.Runner` 在客户机交互式桌面会话内产生。
- 如果没有可用虚拟机，就停在构建/单元测试验证，并如实说明 UI 验证缺口，不要用宿主机替代。

## 构建与测试

```powershell
dotnet build VmUiPipeline.sln -c Debug -m:1 -nodeReuse:false -p:UseSharedCompilation=false
dotnet build tests/VmUiPipeline.Tests/VmUiPipeline.Tests.csproj -c Debug -p:UseSharedCompilation=false
tests/VmUiPipeline.Tests/bin/Debug/net10.0-windows/VmUiPipeline.Tests.exe
Invoke-Pester -Path tests/host
```

`-m:1 -nodeReuse:false -p:UseSharedCompilation=false` 用于绕开阻断命名管道的宿主机；CI 不需要这些参数。

## 依赖边界

WinSimpleSSH 是外部依赖，只负责在客户机交互式控制台会话里启动 `run.cmd`。不要把它打进发布产物；上游没有 LICENSE 文件。发布产物与仓库都不包含它的二进制。
