// Copyright (c) Files Community and VmUiPipeline contributors.
// SPDX-License-Identifier: MPL-2.0

using Microsoft.VisualStudio.TestTools.UnitTesting;
using VmUiPipeline.Testing;

namespace VmUiPipeline.Tests;

[TestClass]
public sealed class TestReportTests
{
    [TestMethod]
    public void Create_CountsStatusesAndComputesDuration()
    {
        var started = DateTimeOffset.UtcNow.AddSeconds(-2);

        var report = TestReport.Create(
            "run-2",
            new MachineInfo { Name = "win10", SessionId = 2 },
            new AppInfo(),
            started,
            [
                new TestOutcome("a", TestStatus.Passed, 1, "ok"),
                new TestOutcome("b", TestStatus.Failed, 2, "boom"),
                new TestOutcome("c", TestStatus.Skipped, 0, "later"),
                new TestOutcome("d", TestStatus.Passed, 3, "ok"),
            ]);

        Assert.AreEqual(2, report.Passed);
        Assert.AreEqual(1, report.Failed);
        Assert.AreEqual(1, report.Skipped);
        Assert.AreEqual(4, report.Tests.Count);
        Assert.IsTrue(report.DurationMs >= 0);
        Assert.IsTrue(report.FinishedUtc >= started);
    }
}
