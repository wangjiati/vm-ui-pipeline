// Copyright (c) Files Community and VmUiPipeline contributors.
// SPDX-License-Identifier: MPL-2.0

namespace VmUiPipeline.Testing;

public sealed class MachineInfo
{
    public string Name { get; init; } = string.Empty;
    public string Os { get; init; } = string.Empty;
    public string Architecture { get; init; } = string.Empty;
    public string User { get; init; } = string.Empty;
    public int SessionId { get; init; }
}

public sealed class AppInfo
{
    public string? Path { get; init; }
    public string? Sha256 { get; init; }
    public string? Version { get; init; }
}

public sealed class TestReport
{
    public int SchemaVersion { get; init; } = 1;
    public string RunId { get; init; } = string.Empty;
    public MachineInfo Machine { get; init; } = new();
    public AppInfo App { get; init; } = new();
    public DateTimeOffset StartedUtc { get; init; }
    public DateTimeOffset FinishedUtc { get; init; }
    public double DurationMs { get; init; }
    public int Passed { get; init; }
    public int Failed { get; init; }
    public int Skipped { get; init; }
    public IReadOnlyList<TestOutcome> Tests { get; init; } = [];
    public string? Error { get; init; }
    public string? Recording { get; init; }

    public static TestReport Create(
        string runId,
        MachineInfo machine,
        AppInfo app,
        DateTimeOffset startedUtc,
        IReadOnlyList<TestOutcome> tests,
        string? error = null,
        string? recording = null)
    {
        var finishedUtc = DateTimeOffset.UtcNow;
        return new TestReport
        {
            RunId = runId,
            Machine = machine,
            App = app,
            StartedUtc = startedUtc,
            FinishedUtc = finishedUtc,
            DurationMs = Math.Round((finishedUtc - startedUtc).TotalMilliseconds, 1),
            Passed = tests.Count(t => t.Status == TestStatus.Passed),
            Failed = tests.Count(t => t.Status == TestStatus.Failed),
            Skipped = tests.Count(t => t.Status == TestStatus.Skipped),
            Tests = tests.ToList(),
            Error = error,
            Recording = recording,
        };
    }
}
