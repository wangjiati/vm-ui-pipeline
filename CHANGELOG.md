# 更新日志

## 0.1.2

- 所有说明文件改为中文：README、贡献指南、安全策略、行为准则、架构、配置、安全、排障、WinSimpleSSH 依赖说明。
- 所有代码注释改为中文，包括 C# XML 文档注释、PowerShell 注释式帮助与内联注释。
- 删除英文与中文双份 README，只保留中文 `README.md`。
- 配置 schema、模块清单与 GitHub 模板同步改为中文。

## 0.1.1

- 修复 Pester 5 作用域问题：在每个 `Describe` 内加载宿主机测试辅助函数。
- 在 `summary.json` 对宿主机可见之前停止并收尾 MP4 录制，避免宿主机复制到未写完的视频。
- Markdown 报告中的截图路径从客户机路径映射到宿主机结果目录。
- 要求显式配置客户机用户，不再默认使用宿主机账号。
- 在依赖说明与排障文档中补充工作组环境所需的本地账户令牌策略。

## 0.1.0

初始源码版本。

- 宿主机 PowerShell 模块：配置、产物展开、SHA-256 校验、SMB 投放、快照回滚、多 VM 聚合、JUnit、Markdown。
- `VmUiPipeline.Runner`：加载套件程序集、启动应用、记录结果、失败截图、可选 ffmpeg MP4 录屏。
- `VmUiPipeline.Testing`：UI Automation 测试库，含等待、控件模式、断言、跳过与截图。
- WinSimpleSSH 启动适配器：服务安装与 IP 白名单。
- 示例：自包含 WPF 应用与套件；原 Files 筛选套件。
- MSTest 单元测试与 Pester 编排层测试；CI 工作流。
