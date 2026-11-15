## 摘要

<!-- 改了什么、为什么改。用 "Fixes #123" 关联 issue。 -->

## 验证

- [ ] `dotnet build VmUiPipeline.sln -c Release`
- [ ] `tests/VmUiPipeline.Tests/bin/Release/net10.0-windows/VmUiPipeline.Tests.exe`
- [ ] `tests/run-host-tests.ps1`
- [ ] 已完成 VM 运行；附上结果目录或在下方说明
- [ ] 没有在宿主机上执行 UI 自动化、截图或录屏

### VM 运行信息

- 客户机：
- 显示 / DPI：
- 录屏：
- 结果：`X 通过，Y 失败，Z 跳过`
- 产物：

## 检查清单

- [ ] 已更新 `README.md` 与相关 `docs/` 文档
- [ ] 未提交密码、`server.json`、截图、视频或 WinSimpleSSH 二进制
- [ ] `summary.json` 仍保持 schema 版本兼容
