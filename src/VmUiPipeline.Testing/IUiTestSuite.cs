// Copyright (c) Files Community and VmUiPipeline contributors.
// SPDX-License-Identifier: MPL-2.0

namespace VmUiPipeline.Testing;

/// <summary>
/// UI 测试套件。Runner 实例化实现类，并在客户机交互式桌面会话中执行一次。
/// </summary>
public interface IUiTestSuite
{
    string Name { get; }

    void Run(UiTestContext context);
}
