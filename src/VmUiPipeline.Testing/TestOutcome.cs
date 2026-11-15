// Copyright (c) Files Community and VmUiPipeline contributors.
// SPDX-License-Identifier: MPL-2.0

using System.Text.Json.Serialization;

namespace VmUiPipeline.Testing;

public enum TestStatus
{
    Passed,
    Failed,
    Skipped,
}

public sealed record TestOutcome(
    string Name,
    TestStatus Status,
    double DurationMs,
    string? Detail,
    IReadOnlyList<string>? Screenshots = null)
{
    [JsonIgnore]
    public bool Passed => Status == TestStatus.Passed;
}
