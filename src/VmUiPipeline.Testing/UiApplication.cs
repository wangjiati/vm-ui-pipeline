// Copyright (c) Files Community and VmUiPipeline contributors.
// SPDX-License-Identifier: MPL-2.0

using System.IO;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Automation;

namespace VmUiPipeline.Testing;

/// <summary>
/// 已启动的桌面应用及其 UI Automation 根窗口。
/// </summary>
public sealed class UiApplication : IDisposable
{
    private const int SwRestore = 9;
    private const uint SwpShowWindow = 0x0040;
    private static readonly IntPtr HwndTop = IntPtr.Zero;

    private readonly Process _process;
    private bool _disposed;

    private UiApplication(Process process, AutomationElement mainWindow)
    {
        _process = process;
        MainWindow = mainWindow;
    }

    public Process Process => _process;

    public AutomationElement MainWindow { get; }

    public static UiApplication Launch(
        string executablePath,
        string? arguments,
        TimeSpan timeout,
        string? processName = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(executablePath);
        if (!File.Exists(executablePath))
        {
            throw new FileNotFoundException($"Application executable not found: {executablePath}", executablePath);
        }

        var startInfo = new ProcessStartInfo(executablePath)
        {
            UseShellExecute = true,
        };
        if (!string.IsNullOrWhiteSpace(arguments))
        {
            startInfo.Arguments = arguments;
        }

        var process = Process.Start(startInfo)
            ?? throw new InvalidOperationException($"Failed to start {executablePath}.");

        var window = WaitForMainWindow(process, timeout, processName);
        if (window is null)
        {
            TryKill(process);
            throw new InvalidOperationException(
                $"No main window appeared within {timeout.TotalSeconds:0.#}s for {Path.GetFileName(executablePath)}.");
        }

        var application = new UiApplication(process, window);
        application.Focus();
        return application;
    }

    /// <summary>把主窗口调整到确定的大小并置于前台。</summary>
    public void Focus(int width = 1600, int height = 1000)
    {
        var handle = new IntPtr(MainWindow.Current.NativeWindowHandle);
        if (handle == IntPtr.Zero)
        {
            return;
        }

        ShowWindow(handle, SwRestore);
        SetWindowPos(handle, HwndTop, 0, 0, width, height, SwpShowWindow);
        SetForegroundWindow(handle);
        Thread.Sleep(400);
    }

    public void Close()
    {
        try
        {
            if (MainWindow.TryGetCurrentPattern(WindowPattern.Pattern, out var pattern))
            {
                ((WindowPattern)pattern).Close();
            }
        }
        catch (ElementNotAvailableException)
        {
            return;
        }
        catch (InvalidOperationException)
        {
            return;
        }

        try
        {
            if (_process.WaitForExit(2000))
            {
                return;
            }
        }
        catch (InvalidOperationException)
        {
            return;
        }

        TryKill(_process);
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        Close();
        _process.Dispose();
    }

    private static AutomationElement? WaitForMainWindow(Process started, TimeSpan timeout, string? processName)
    {
        string expectedProcessName;
        try
        {
            expectedProcessName = string.IsNullOrWhiteSpace(processName) ? started.ProcessName : processName;
        }
        catch (InvalidOperationException)
        {
            expectedProcessName = processName ?? string.Empty;
        }

        var deadline = DateTime.UtcNow + timeout;
        var nextScan = DateTime.UtcNow;
        do
        {
            try
            {
                started.Refresh();
                if (started.MainWindowHandle != IntPtr.Zero)
                {
                    return AutomationElement.FromHandle(started.MainWindowHandle);
                }

                if (started.HasExited && string.IsNullOrEmpty(processName))
                {
                    return null;
                }
            }
            catch (InvalidOperationException)
            {
                return null;
            }

            // 启动器可能转交给另一个进程；降低扫描频率，
            // 避免进程枚举拖慢启动。
            if (DateTime.UtcNow >= nextScan)
            {
                foreach (var candidate in Process.GetProcesses())
                {
                    using (candidate)
                    {
                        try
                        {
                            if (candidate.MainWindowHandle == IntPtr.Zero)
                            {
                                continue;
                            }

                            var matches = candidate.Id == started.Id ||
                                (!string.IsNullOrEmpty(expectedProcessName) &&
                                 candidate.ProcessName.Equals(expectedProcessName, StringComparison.OrdinalIgnoreCase));
                            if (!matches)
                            {
                                continue;
                            }

                            return AutomationElement.FromHandle(candidate.MainWindowHandle);
                        }
                        catch (InvalidOperationException)
                        {
                            // 进程在枚举与检查之间退出。
                        }
                        catch (ArgumentException)
                        {
                            // 窗口句柄已消失。
                        }
                    }
                }

                nextScan = DateTime.UtcNow.AddSeconds(2);
            }

            Thread.Sleep(200);
        }
        while (DateTime.UtcNow < deadline);

        return null;
    }

    private static void TryKill(Process process)
    {
        try
        {
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
            }
        }
        catch (InvalidOperationException)
        {
            // 已经退出。
        }
        catch (System.ComponentModel.Win32Exception)
        {
            // 拒绝访问或已不存在。
        }
    }

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr handle, int command);

    [DllImport("user32.dll")]
    private static extern bool SetWindowPos(IntPtr handle, IntPtr insertAfter, int x, int y, int width, int height, uint flags);

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr handle);
}
