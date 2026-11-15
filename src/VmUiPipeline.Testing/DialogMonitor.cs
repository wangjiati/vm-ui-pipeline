// Copyright (c) Files Community and VmUiPipeline contributors.
// SPDX-License-Identifier: MPL-2.0

using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace VmUiPipeline.Testing;

/// <summary>客户机桌面上一个可见的异常对话框。</summary>
public sealed record UnexpectedDialog(string Title, string ClassName, int ProcessId, string? ProcessName);

/// <summary>
/// 检测客户机桌面上可见的 Windows 对话框（窗口类 #32770）。
/// 用于在无人值守运行时发现启动错误、许可证提示、实例锁冲突等弹窗。
/// </summary>
public static class DialogMonitor
{
    public static IReadOnlyList<UnexpectedDialog> FindVisibleDialogs()
    {
        var dialogs = new List<UnexpectedDialog>();
        EnumWindows((handle, _) =>
        {
            try
            {
                if (!IsWindowVisible(handle))
                {
                    return true;
                }

                var className = new StringBuilder(256);
                if (GetClassName(handle, className, className.Capacity) <= 0 ||
                    !className.ToString().Equals("#32770", StringComparison.Ordinal))
                {
                    return true;
                }

                var title = new StringBuilder(512);
                GetWindowText(handle, title, title.Capacity);
                if (title.Length == 0)
                {
                    return true;
                }

                GetWindowThreadProcessId(handle, out var processId);
                string? processName = null;
                try
                {
                    processName = Process.GetProcessById((int)processId).ProcessName;
                }
                catch (Exception)
                {
                    // 进程可能已经退出。
                }

                dialogs.Add(new UnexpectedDialog(
                    title.ToString(),
                    className.ToString(),
                    (int)processId,
                    processName));
            }
            catch (Exception)
            {
                // 单个窗口消失不应影响整体检测。
            }

            return true;
        }, IntPtr.Zero);

        return dialogs;
    }

    private delegate bool EnumWindowsProc(IntPtr handle, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(IntPtr handle, StringBuilder className, int maxCount);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr handle, StringBuilder text, int maxCount);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr handle);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr handle, out uint processId);
}
