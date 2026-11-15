// Copyright (c) Files Community and VmUiPipeline contributors.
// SPDX-License-Identifier: MPL-2.0

using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Text.RegularExpressions;
using System.Windows.Forms;

namespace VmUiPipeline.Testing;

/// <summary>
/// 截取客户机桌面。Runner 位于虚拟机交互式会话中，因此不会接触宿主机桌面。
/// </summary>
public static class ScreenshotCapture
{
    public static string Capture(string outputDirectory, string name)
    {
        Directory.CreateDirectory(outputDirectory);

        var safeName = Regex.Replace(name, "[^A-Za-z0-9._-]", "_");
        var path = Path.Combine(outputDirectory, $"{DateTime.Now:HHmmss-fff}-{safeName}.png");

        var screen = Screen.PrimaryScreen;
        var bounds = screen?.Bounds ?? new Rectangle(0, 0, 1920, 1080);

        using var bitmap = new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format32bppArgb);
        using var graphics = Graphics.FromImage(bitmap);
        graphics.CopyFromScreen(bounds.Left, bounds.Top, 0, 0, bounds.Size, CopyPixelOperation.SourceCopy);
        bitmap.Save(path, ImageFormat.Png);
        return path;
    }
}
