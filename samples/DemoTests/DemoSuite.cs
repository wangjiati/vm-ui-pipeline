// Copyright (c) Files Community and VmUiPipeline contributors.
// SPDX-License-Identifier: MPL-2.0

using System.IO;
using System.Windows.Automation;
using VmUiPipeline.Testing;

namespace DemoTests;

/// <summary>
/// 截图与录屏演示套件。每个步骤都会在客户机桌面留下一张 PNG；
/// 如果流水线启用了 recording，整个套件还会被录成 session.mp4。
/// </summary>
public sealed class DemoSuite : IUiTestSuite
{
    public string Name => "Demo";

    public void Run(UiTestContext context)
    {
        context.Test("01-launch", () =>
        {
            var window = context.Require(context.MainWindow, "主窗口");
            context.Assert(!string.IsNullOrWhiteSpace(window.Current.Name), "窗口标题不能为空");
            Capture(context, "01-launch");
            Thread.Sleep(1200);
        });

        context.Test("02-filter", () =>
        {
            var box = context.Require(context.WaitForId("KeywordBox", TimeSpan.FromSeconds(5)), "关键字输入框");
            context.Assert(context.SetText(box, "zip"), "输入关键字");
            var apply = context.Require(context.FindById("ApplyButton"), "应用按钮");
            context.Assert(context.Invoke(apply), "点击应用按钮");
            context.WaitForCount(() => ReadCount(context), 2, TimeSpan.FromSeconds(5), "zip 匹配数");
            Capture(context, "02-filter");
            Thread.Sleep(1200);
        });

        context.Test("03-recurse", () =>
        {
            var checkbox = context.Require(context.FindById("RecurseCheck"), "搜索子文件夹复选框");
            context.Assert(context.Toggle(checkbox), "勾选搜索子文件夹");
            context.WaitForCount(() => ReadCount(context), 4, TimeSpan.FromSeconds(5), "递归后的 zip 匹配数");
            Capture(context, "03-recurse");
            Thread.Sleep(1200);
        });

        context.Test("04-clear", () =>
        {
            var clear = context.Require(context.FindById("ClearButton"), "清除按钮");
            context.Assert(context.Invoke(clear), "点击清除按钮");
            context.WaitForCount(() => ReadCount(context), 3, TimeSpan.FromSeconds(5), "清除后的匹配数");
            Capture(context, "04-clear");
            Thread.Sleep(1500);
        });
    }

    private static void Capture(UiTestContext context, string name)
    {
        var path = context.CaptureScreenshot(name);
        context.Assert(path is not null && File.Exists(path), $"截图未生成：{name}");
        context.Log($"截图：{path}");
    }

    private static int? ReadCount(UiTestContext context)
    {
        var text = context.FindById("CountText")?.Current.Name;
        if (string.IsNullOrWhiteSpace(text))
        {
            return null;
        }

        var firstToken = text.Split(' ', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault();
        return int.TryParse(firstToken, out var count) ? count : null;
    }
}
