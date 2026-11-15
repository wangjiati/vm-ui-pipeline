// Copyright (c) Files Community and VmUiPipeline contributors.
// SPDX-License-Identifier: MPL-2.0

using System.IO;
using System.Text.Json;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using VmUiPipeline.Testing;

namespace VmUiPipeline.Tests;

[TestClass]
public sealed class ReportWriterTests
{
    private string _outputDirectory = string.Empty;

    [TestInitialize]
    public void Initialize()
    {
        _outputDirectory = Path.Combine(
            AppContext.BaseDirectory,
            "test-temp",
            Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_outputDirectory);
    }

    [TestCleanup]
    public void Cleanup()
    {
        if (Directory.Exists(_outputDirectory))
        {
            Directory.Delete(_outputDirectory, recursive: true);
        }
    }

    [TestMethod]
    public void Write_UsesCamelCaseAndStringStatuses()
    {
        var report = CreateReport();

        var path = ReportWriter.Write(report, _outputDirectory);
        var json = File.ReadAllText(path);

        StringAssert.Contains(json, "\"schemaVersion\": 1");
        StringAssert.Contains(json, "\"status\": \"passed\"");
        StringAssert.Contains(json, "\"status\": \"skipped\"");
        StringAssert.Contains(json, "\"passed\": 1");
        StringAssert.Contains(json, "\"skipped\": 1");
        Assert.IsFalse(File.Exists(path + ".tmp"), "temporary file should be moved into place");
    }

    [TestMethod]
    public void Write_RoundTripsReport()
    {
        var report = CreateReport();

        var path = ReportWriter.Write(report, _outputDirectory);
        var roundTrip = JsonSerializer.Deserialize<TestReport>(
            File.ReadAllText(path),
            ReportWriter.JsonOptions);

        Assert.IsNotNull(roundTrip);
        Assert.AreEqual(report.RunId, roundTrip.RunId);
        Assert.AreEqual(report.Passed, roundTrip.Passed);
        Assert.AreEqual(report.Tests.Count, roundTrip.Tests.Count);
        Assert.AreEqual(report.Tests[0].Status, roundTrip.Tests[0].Status);
    }

    [TestMethod]
    public void WriteTextResults_WritesOneLinePerTest()
    {
        var report = CreateReport();

        var path = ReportWriter.WriteTextResults(report, _outputDirectory);
        var lines = File.ReadAllLines(path);

        Assert.AreEqual(2, lines.Length);
        Assert.AreEqual("PASSED|launch|ok", lines[0]);
        Assert.AreEqual("SKIPPED|screenshot|out of scope", lines[1]);
    }

    private static TestReport CreateReport() =>
        TestReport.Create(
            "run-1",
            new MachineInfo
            {
                Name = "win11",
                Os = "Windows 11",
                Architecture = "X64",
                User = "tester",
                SessionId = 1,
            },
            new AppInfo
            {
                Path = @"C:\VmUiPipeline\app\SampleApp.exe",
                Sha256 = new string('A', 64),
                Version = "1.0.0.0",
            },
            DateTimeOffset.UtcNow.AddSeconds(-3),
            [
                new TestOutcome("launch", TestStatus.Passed, 12.5, "ok"),
                new TestOutcome("screenshot", TestStatus.Skipped, 0, "out of scope"),
            ]);
}
