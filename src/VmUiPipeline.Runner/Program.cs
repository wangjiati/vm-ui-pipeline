// Copyright (c) Files Community and VmUiPipeline contributors.
// SPDX-License-Identifier: MPL-2.0

using System.Diagnostics;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using VmUiPipeline.Testing;

namespace VmUiPipeline.Runner;

internal static class Program
{
    private static int _completed;
    private static RunnerLog? _log;

    private static int Main(string[] args)
    {
        RunnerOptions options;
        try
        {
            options = RunnerOptions.Parse(args);
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine(exception.Message);
            Console.Error.WriteLine();
            RunnerOptions.PrintUsage();
            return 2;
        }

        if (options.ShowHelp)
        {
            RunnerOptions.PrintUsage();
            return 0;
        }

        try
        {
            return Run(options);
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine(exception);
            return 2;
        }
    }

    private static int Run(RunnerOptions options)
    {
        options.Validate();
        Directory.CreateDirectory(options.OutputDirectory);

        using var log = new RunnerLog(options.OutputDirectory);
        _log = log;

        var startedUtc = DateTimeOffset.UtcNow;
        var runId = string.IsNullOrWhiteSpace(options.RunId)
            ? $"{Environment.MachineName}-{startedUtc:yyyyMMdd-HHmmss}"
            : options.RunId;

        var machine = new MachineInfo
        {
            Name = Environment.MachineName,
            Os = RuntimeInformation.OSDescription,
            Architecture = RuntimeInformation.OSArchitecture.ToString(),
            User = Environment.UserName,
            SessionId = Process.GetCurrentProcess().SessionId,
        };

        log.Write($"runId={runId}");
        log.Write($"machine={machine.Name} os={machine.Os} session={machine.SessionId} user={machine.User}");
        log.Write($"suite={options.SuitePath} type={options.SuiteType}");

        var appInfo = new AppInfo
        {
            Path = options.AppPath,
            Version = GetFileVersion(options.AppPath),
        };

        if (options.AppPath is not null)
        {
            var appHash = ComputeSha256(options.AppPath);
            appInfo = new AppInfo
            {
                Path = options.AppPath,
                Version = appInfo.Version,
                Sha256 = appHash,
            };

            log.Write($"app={options.AppPath} sha256={appHash}");
            if (options.AppSha256 is not null &&
                !string.Equals(appHash, options.AppSha256, StringComparison.OrdinalIgnoreCase))
            {
                var message =
                    $"App hash mismatch: expected {options.AppSha256}, actual {appHash}.";
                log.Write($"ERROR {message}");
                WriteReport(options.OutputDirectory, runId, machine, appInfo, startedUtc, [], message, options.RecordPath);
                return 4;
            }
        }

        IUiTestSuite suite;
        try
        {
            suite = LoadSuite(options.SuitePath, options.SuiteType);
        }
        catch (Exception exception)
        {
            var message = $"Failed to load suite: {exception}";
            log.Write($"ERROR {message}");
            WriteReport(options.OutputDirectory, runId, machine, appInfo, startedUtc, [], message, options.RecordPath);
            return 2;
        }

        log.Write($"suiteName={suite.Name}");

        ScreenRecorder? recorder = null;
        if (!string.IsNullOrWhiteSpace(options.RecordPath))
        {
            var maximumSeconds = options.TimeoutSeconds > 0 ? options.TimeoutSeconds + 30 : 600;
            recorder = ScreenRecorder.Start(
                options.FfmpegPath,
                options.RecordPath,
                options.RecordFps,
                maximumSeconds,
                log.Write);
        }

        UiApplication? app = null;
        string? error = null;

        try
        {
            if (options.AppPath is not null)
            {
                log.Write($"launching app {options.AppPath}");
                app = UiApplication.Launch(
                    options.AppPath,
                    options.AppArguments,
                    TimeSpan.FromSeconds(options.StartupTimeoutSeconds),
                    options.ProcessName);
            }

            using var watchdog = options.TimeoutSeconds > 0
                ? new Timer(
                    _ => OnTimeout(
                        options.OutputDirectory,
                        runId,
                        machine,
                        appInfo,
                        startedUtc,
                        options.TimeoutSeconds,
                        options.RecordPath,
                        options.NoScreenshots,
                        recorder),
                    null,
                    TimeSpan.FromSeconds(options.TimeoutSeconds),
                    Timeout.InfiniteTimeSpan)
                : null;

            var context = new UiTestContext(
                app,
                options.Folder,
                options.Parameters,
                options.Filter,
                log.Write,
                Path.Combine(options.OutputDirectory, "screenshots"),
                !options.NoScreenshots);

            try
            {
                suite.Run(context);
            }
            catch (Exception exception)
            {
                error = exception.ToString();
                log.Write($"SUITE ERROR {exception}");
            }
            finally
            {
                app?.Dispose();
                app = null;
            }

            // 在 summary.json 对宿主机可见之前收尾 MP4。
            recorder?.Stop();

            if (Interlocked.Exchange(ref _completed, 1) != 0)
            {
                return 3;
            }

            var report = TestReport.Create(
                runId,
                machine,
                appInfo,
                startedUtc,
                context.Results,
                error,
                options.RecordPath);
            WriteReport(options.OutputDirectory, report);
            log.Write($"done passed={report.Passed} failed={report.Failed} skipped={report.Skipped}");
            return report.Failed > 0 || error is not null ? 1 : 0;
        }
        catch (Exception exception)
        {
            error = exception.ToString();
            log.Write($"ERROR {exception}");
            recorder?.Stop();
            if (Interlocked.Exchange(ref _completed, 1) == 0)
            {
                WriteReport(options.OutputDirectory, runId, machine, appInfo, startedUtc, [], error, options.RecordPath);
            }

            return 4;
        }
        finally
        {
            app?.Dispose();
            recorder?.Dispose();
        }
    }

    private static void OnTimeout(
        string outputDirectory,
        string runId,
        MachineInfo machine,
        AppInfo appInfo,
        DateTimeOffset startedUtc,
        int timeoutSeconds,
        string? recording,
        bool noScreenshots,
        ScreenRecorder? recorder)
    {
        if (Interlocked.Exchange(ref _completed, 1) != 0)
        {
            return;
        }

        var message = $"Runner timed out after {timeoutSeconds}s.";
        _log?.Write($"TIMEOUT {message}");

        if (!noScreenshots)
        {
            try
            {
                var path = ScreenshotCapture.Capture(Path.Combine(outputDirectory, "screenshots"), "timeout");
                _log?.Write($"screenshot {path}");
            }
            catch (Exception exception)
            {
                _log?.Write($"screenshot failed: {exception.Message}");
            }
        }

        try
        {
            recorder?.Stop();
        }
        catch (Exception exception)
        {
            _log?.Write($"recording stop failed: {exception.Message}");
        }

        try
        {
            WriteReport(outputDirectory, runId, machine, appInfo, startedUtc, [], message, recording);
        }
        catch (Exception exception)
        {
            _log?.Write($"ERROR writing timeout report: {exception.Message}");
        }

        Environment.Exit(3);
    }

    private static void WriteReport(
        string outputDirectory,
        string runId,
        MachineInfo machine,
        AppInfo appInfo,
        DateTimeOffset startedUtc,
        IReadOnlyList<TestOutcome> tests,
        string? error,
        string? recording)
    {
        WriteReport(
            outputDirectory,
            TestReport.Create(runId, machine, appInfo, startedUtc, tests, error, recording));
    }

    private static void WriteReport(string outputDirectory, TestReport report)
    {
        ReportWriter.Write(report, outputDirectory);
        ReportWriter.WriteTextResults(report, outputDirectory);
    }

    private static IUiTestSuite LoadSuite(string assemblyPath, string typeName)
    {
        var fullPath = Path.GetFullPath(assemblyPath);
        var assembly = Assembly.LoadFrom(fullPath);
        var type = assembly.GetType(typeName, throwOnError: false, ignoreCase: false);
        if (type is null)
        {
            var available = assembly
                .GetTypes()
                .Where(t => typeof(IUiTestSuite).IsAssignableFrom(t) && !t.IsAbstract)
                .Select(t => t.FullName)
                .Where(name => name is not null);
            throw new InvalidOperationException(
                $"Type '{typeName}' was not found in {Path.GetFileName(fullPath)}. Available suites: {string.Join(", ", available)}");
        }

        if (Activator.CreateInstance(type) is not IUiTestSuite suite)
        {
            throw new InvalidOperationException(
                $"Type '{typeName}' does not implement {nameof(IUiTestSuite)} or has no public parameterless constructor.");
        }

        return suite;
    }

    private static string ComputeSha256(string path)
    {
        using var stream = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(stream));
    }

    private static string? GetFileVersion(string? path)
    {
        if (path is null)
        {
            return null;
        }

        try
        {
            return FileVersionInfo.GetVersionInfo(path).FileVersion;
        }
        catch (Exception)
        {
            return null;
        }
    }
}
