// Copyright (c) Files Community and VmUiPipeline contributors.
// SPDX-License-Identifier: MPL-2.0

using System.Diagnostics;
using System.Text.RegularExpressions;
using System.Windows.Automation;

namespace VmUiPipeline.Testing;

/// <summary>
/// 面向测试的已启动应用与 UI Automation 门面。每次 <see cref="Test"/> 调用记录一条结果，
/// 并通过传入的日志委托输出进度。
/// </summary>
public sealed class UiTestContext
{
    private readonly List<TestOutcome> _results = [];
    private readonly object _gate = new();
    private readonly Action<string> _log;
    private readonly string? _filter;
    private readonly string? _screenshotDirectory;
    private readonly bool _screenshotsEnabled;
    private readonly bool _detectDialogs;

    public UiTestContext(
        UiApplication? app,
        string? folder,
        IReadOnlyDictionary<string, string>? parameters,
        string? filter,
        Action<string> log,
        string? screenshotDirectory = null,
        bool screenshotsEnabled = true,
        bool detectDialogs = false)
    {
        App = app;
        Folder = folder;
        Parameters = parameters ?? new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        _filter = string.IsNullOrWhiteSpace(filter) ? null : filter;
        _log = log;
        _screenshotDirectory = screenshotDirectory;
        _screenshotsEnabled = screenshotsEnabled;
        _detectDialogs = detectDialogs;
    }

    public UiApplication? App { get; }

    public string? Folder { get; }

    public IReadOnlyDictionary<string, string> Parameters { get; }

    public AutomationElement? MainWindow => App?.MainWindow;

    public IReadOnlyList<TestOutcome> Results
    {
        get
        {
            lock (_gate)
            {
                return _results.ToArray();
            }
        }
    }

    public void Test(string name, Action body)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        ArgumentNullException.ThrowIfNull(body);

        if (!MatchesFilter(name))
        {
            return;
        }

        var stopwatch = Stopwatch.StartNew();
        try
        {
            body();
            stopwatch.Stop();

            var dialogs = FindDialogs();
            if (dialogs.Count > 0)
            {
                var screenshots = TryCaptureScreenshot($"dialog-{name}");
                var detail = DescribeDialogs(dialogs);
                Record(new TestOutcome(name, TestStatus.Failed, Round(stopwatch), detail, screenshots));
                _log($"FAIL {name}: {detail}");
                return;
            }

            Record(new TestOutcome(name, TestStatus.Passed, Round(stopwatch), "ok"));
            _log($"PASS {name} ({Round(stopwatch):0} ms)");
        }
        catch (UiSkipException exception)
        {
            stopwatch.Stop();
            Record(new TestOutcome(name, TestStatus.Skipped, Round(stopwatch), exception.Message));
            _log($"SKIP {name}: {exception.Message}");
        }
        catch (Exception exception)
        {
            stopwatch.Stop();
            var dialogs = FindDialogs();
            var detail = Describe(exception);
            if (dialogs.Count > 0)
            {
                detail += "；" + DescribeDialogs(dialogs);
            }

            var screenshots = TryCaptureScreenshot($"failure-{name}");
            var screenshotNote = screenshots is null ? string.Empty : $" (screenshot: {string.Join(", ", screenshots)})";
            Record(new TestOutcome(name, TestStatus.Failed, Round(stopwatch), detail, screenshots));
            _log($"FAIL {name}: {detail}{screenshotNote}");
        }
    }

    public void Skip(string name, string reason)
    {
        if (!MatchesFilter(name))
        {
            return;
        }

        Record(new TestOutcome(name, TestStatus.Skipped, 0, reason));
        _log($"SKIP {name}: {reason}");
    }

    public void Assert(bool condition, string message)
    {
        if (!condition)
        {
            throw new UiAssertionException(message);
        }
    }

    public T Require<T>(T? value, string description) where T : class
    {
        return value ?? throw new UiAssertionException($"Expected {description}, but it was not found.");
    }

    public void Log(string message) => _log(message);

    /// <summary>返回客户机桌面上当前可见的异常对话框。</summary>
    public IReadOnlyList<UnexpectedDialog> FindDialogs() =>
        _detectDialogs ? DialogMonitor.FindVisibleDialogs() : [];

    /// <summary>截取客户机桌面并返回 PNG 路径；禁用时返回 null。</summary>
    public string? CaptureScreenshot(string name)
    {
        if (!_screenshotsEnabled || string.IsNullOrWhiteSpace(_screenshotDirectory))
        {
            return null;
        }

        try
        {
            var path = ScreenshotCapture.Capture(_screenshotDirectory, name);
            _log($"screenshot {path}");
            return path;
        }
        catch (Exception exception)
        {
            _log($"screenshot failed: {exception.Message}");
            return null;
        }
    }

    public T WaitFor<T>(Func<T?> probe, TimeSpan timeout, string? description = null) where T : class
    {
        ArgumentNullException.ThrowIfNull(probe);
        var deadline = DateTime.UtcNow + timeout;
        do
        {
            T? value;
            try
            {
                value = probe();
            }
            catch (ElementNotAvailableException)
            {
                value = null;
            }

            if (value is not null)
            {
                return value;
            }

            Thread.Sleep(200);
        }
        while (DateTime.UtcNow < deadline);

        throw new UiAssertionException(
            $"Timed out after {timeout.TotalSeconds:0.#}s waiting for {description ?? typeof(T).Name}.");
    }

    public int WaitForCount(Func<int?> probe, int expected, TimeSpan timeout, string? description = null)
    {
        ArgumentNullException.ThrowIfNull(probe);
        var deadline = DateTime.UtcNow + timeout;
        int? last = null;
        do
        {
            last = probe();
            if (last == expected)
            {
                return last.Value;
            }

            Thread.Sleep(200);
        }
        while (DateTime.UtcNow < deadline);

        throw new UiAssertionException(
            $"Timed out after {timeout.TotalSeconds:0.#}s waiting for {description ?? "count"}={expected}; last value was {last?.ToString() ?? "<null>"}.");
    }

    public AutomationElement? FindById(string automationId)
    {
        var root = MainWindow;
        if (root is null)
        {
            return null;
        }

        try
        {
            return root.FindFirst(
                TreeScope.Descendants,
                new PropertyCondition(AutomationElement.AutomationIdProperty, automationId));
        }
        catch (ElementNotAvailableException)
        {
            return null;
        }
    }

    public AutomationElement? FindByName(string name, ControlType? controlType = null)
    {
        var root = MainWindow;
        if (root is null)
        {
            return null;
        }

        try
        {
            var matches = root.FindAll(
                TreeScope.Descendants,
                new PropertyCondition(AutomationElement.NameProperty, name));
            foreach (AutomationElement element in matches)
            {
                if (controlType is null || element.Current.ControlType == controlType)
                {
                    return element;
                }
            }
        }
        catch (ElementNotAvailableException)
        {
            return null;
        }

        return null;
    }

    public AutomationElement? FindByNameAny(IEnumerable<string> names, ControlType? controlType = null)
    {
        ArgumentNullException.ThrowIfNull(names);
        foreach (var name in names)
        {
            var element = FindByName(name, controlType);
            if (element is not null)
            {
                return element;
            }
        }

        return null;
    }

    public AutomationElement? FindByControlType(ControlType controlType)
    {
        var root = MainWindow;
        if (root is null)
        {
            return null;
        }

        try
        {
            return root.FindFirst(
                TreeScope.Descendants,
                new PropertyCondition(AutomationElement.ControlTypeProperty, controlType));
        }
        catch (ElementNotAvailableException)
        {
            return null;
        }
    }

    public IReadOnlyList<AutomationElement> FindAll()
    {
        var root = MainWindow;
        if (root is null)
        {
            return [];
        }

        try
        {
            var found = root.FindAll(TreeScope.Descendants, Condition.TrueCondition);
            var elements = new List<AutomationElement>(found.Count);
            foreach (AutomationElement element in found)
            {
                elements.Add(element);
            }

            return elements;
        }
        catch (ElementNotAvailableException)
        {
            return [];
        }
    }

    public AutomationElement? WaitForId(string automationId, TimeSpan timeout, string? description = null)
    {
        return WaitFor(() => FindById(automationId), timeout, description ?? $"AutomationId '{automationId}'");
    }

    public AutomationElement? WaitForNameAny(
        IEnumerable<string> names,
        ControlType? controlType,
        TimeSpan timeout,
        string? description = null)
    {
        var candidates = names.ToArray();
        return WaitFor(
            () => FindByNameAny(candidates, controlType),
            timeout,
            description ?? $"one of '{string.Join("', '", candidates)}'");
    }

    public bool SetText(AutomationElement element, string text)
    {
        ArgumentNullException.ThrowIfNull(element);
        try
        {
            if (element.TryGetCurrentPattern(ValuePattern.Pattern, out var pattern))
            {
                ((ValuePattern)pattern).SetValue(text);
                return true;
            }
        }
        catch (ElementNotAvailableException)
        {
            return false;
        }

        return false;
    }

    public bool Invoke(AutomationElement element)
    {
        ArgumentNullException.ThrowIfNull(element);
        try
        {
            if (element.TryGetCurrentPattern(InvokePattern.Pattern, out var pattern))
            {
                ((InvokePattern)pattern).Invoke();
                return true;
            }

            if (element.TryGetCurrentPattern(SelectionItemPattern.Pattern, out var selection))
            {
                ((SelectionItemPattern)selection).Select();
                return true;
            }
        }
        catch (ElementNotAvailableException)
        {
            return false;
        }

        return false;
    }

    public bool Toggle(AutomationElement element)
    {
        ArgumentNullException.ThrowIfNull(element);
        try
        {
            if (element.TryGetCurrentPattern(TogglePattern.Pattern, out var pattern))
            {
                ((TogglePattern)pattern).Toggle();
                return true;
            }
        }
        catch (ElementNotAvailableException)
        {
            return false;
        }

        return false;
    }

    public bool Select(AutomationElement element)
    {
        ArgumentNullException.ThrowIfNull(element);
        try
        {
            if (element.TryGetCurrentPattern(SelectionItemPattern.Pattern, out var pattern))
            {
                ((SelectionItemPattern)pattern).Select();
                return true;
            }
        }
        catch (ElementNotAvailableException)
        {
            return false;
        }

        return false;
    }

    private bool MatchesFilter(string name) =>
        _filter is null || Regex.IsMatch(name, _filter, RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

    private IReadOnlyList<string>? TryCaptureScreenshot(string name)
    {
        var path = CaptureScreenshot(name);
        return path is null ? null : new[] { path };
    }

    private void Record(TestOutcome outcome)
    {
        lock (_gate)
        {
            _results.Add(outcome);
        }
    }

    private static double Round(Stopwatch stopwatch) => Math.Round(stopwatch.Elapsed.TotalMilliseconds, 1);

    private static string Describe(Exception exception)
    {
        var detail = exception.Message;
        return string.IsNullOrWhiteSpace(detail) ? exception.GetType().Name : detail;
    }

    private static string DescribeDialogs(IReadOnlyList<UnexpectedDialog> dialogs)
    {
        var parts = dialogs.Select(dialog =>
            $"{dialog.Title} [{dialog.ProcessName ?? "unknown"}:{dialog.ProcessId}]");
        return "检测到异常弹窗：" + string.Join(" | ", parts);
    }
}
