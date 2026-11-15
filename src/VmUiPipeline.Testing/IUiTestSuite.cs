// Copyright (c) Files Community and VmUiPipeline contributors.
// SPDX-License-Identifier: MPL-2.0

namespace VmUiPipeline.Testing;

/// <summary>
/// A suite of UI tests. Implementations are instantiated by the runner and run once
/// inside the guest's interactive desktop session.
/// </summary>
public interface IUiTestSuite
{
    string Name { get; }

    void Run(UiTestContext context);
}
