// Copyright (c) Files Community and VmUiPipeline contributors.
// SPDX-License-Identifier: MPL-2.0

namespace VmUiPipeline.Testing;

/// <summary>Thrown when a UI assertion fails.</summary>
public sealed class UiAssertionException : Exception
{
    public UiAssertionException(string message) : base(message)
    {
    }
}

/// <summary>Thrown by a test body to mark the test as skipped instead of failed.</summary>
public sealed class UiSkipException : Exception
{
    public UiSkipException(string reason) : base(reason)
    {
    }
}
