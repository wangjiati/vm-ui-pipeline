// Copyright (c) Files Community and VmUiPipeline contributors.
// SPDX-License-Identifier: MPL-2.0

namespace VmUiPipeline.Testing;

/// <summary>UI 断言失败时抛出。</summary>
public sealed class UiAssertionException : Exception
{
    public UiAssertionException(string message) : base(message)
    {
    }
}

/// <summary>由测试体抛出，用于把测试标记为跳过而不是失败。</summary>
public sealed class UiSkipException : Exception
{
    public UiSkipException(string reason) : base(reason)
    {
    }
}
