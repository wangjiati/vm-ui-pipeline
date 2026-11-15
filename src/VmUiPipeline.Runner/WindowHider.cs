// Copyright (c) Files Community and VmUiPipeline contributors.
// SPDX-License-Identifier: MPL-2.0

using System.Runtime.InteropServices;
using System.Text;

namespace VmUiPipeline.Runner;

/// <summary>
/// 隐藏客户机桌面上的控制台窗口。WinSimpleSSH 的 start 动词会留下一个
/// 命令提示符窗口；它不属于被测应用，却会污染截图和录像。
/// </summary>
internal static class WindowHider
{
    private const int SwHide = 0;

    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    public static int HideConsoleWindows()
    {
        var hidden = 0;
        EnumWindows((handle, _) =>
        {
            try
            {
                if (!IsWindowVisible(handle))
                {
                    return true;
                }

                var className = new StringBuilder(256);
                if (GetClassName(handle, className, className.Capacity) > 0 &&
                    className.ToString().Equals("ConsoleWindowClass", StringComparison.Ordinal))
                {
                    ShowWindow(handle, SwHide);
                    hidden++;
                }
            }
            catch (Exception)
            {
                // 单个窗口消失不应影响测试。
            }

            return true;
        }, IntPtr.Zero);

        return hidden;
    }

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(IntPtr handle, StringBuilder className, int maxCount);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr handle);

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr handle, int command);
}
