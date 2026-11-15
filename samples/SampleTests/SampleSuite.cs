// Copyright (c) Files Community and VmUiPipeline contributors.
// SPDX-License-Identifier: MPL-2.0

using System.IO;
using System.Windows.Automation;
using VmUiPipeline.Testing;

namespace SampleTests;

/// <summary>
/// End-to-end smoke suite for <c>samples/SampleApp</c>. It exercises launch, UIA lookup,
/// text input, commands, toggles, count assertions, and the skip path.
/// </summary>
public sealed class SampleSuite : IUiTestSuite
{
    public string Name => "SampleApp";

    public void Run(UiTestContext context)
    {
        context.Test("launch", () =>
        {
            var window = context.Require(context.MainWindow, "main window");
            context.Assert(!string.IsNullOrWhiteSpace(window.Current.Name), "main window has a title");
        });

        context.Test("filter", () =>
        {
            Apply(context, "zip");
            context.WaitForCount(() => ReadCount(context), 2, TimeSpan.FromSeconds(5), "zip matches");
            context.Assert(CountListItems(context) == 2, $"list shows 2 rows, saw {CountListItems(context)}");
        });

        context.Test("recurse", () =>
        {
            var checkbox = context.Require(context.FindById("RecurseCheck"), "recurse checkbox");
            context.Assert(context.Toggle(checkbox), "toggle recurse");
            context.WaitForCount(() => ReadCount(context), 4, TimeSpan.FromSeconds(5), "recursive zip matches");
        });

        context.Test("clear", () =>
        {
            var clear = context.Require(context.FindById("ClearButton"), "clear button");
            context.Assert(context.Invoke(clear), "invoke clear");
            context.WaitForCount(() => ReadCount(context), 3, TimeSpan.FromSeconds(5), "unfiltered count");
        });

        context.Test("screenshot", () =>
        {
            var path = context.CaptureScreenshot("sample");
            context.Assert(path is not null && File.Exists(path), "screenshot file");
        });
    }

    private static void Apply(UiTestContext context, string keyword)
    {
        var box = context.Require(context.FindById("KeywordBox"), "keyword box");
        context.Assert(context.SetText(box, keyword), "set keyword");
        var apply = context.Require(context.FindById("ApplyButton"), "apply button");
        context.Assert(context.Invoke(apply), "invoke apply");
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

    private static int CountListItems(UiTestContext context)
    {
        var list = context.FindById("ResultsList");
        if (list is null)
        {
            return 0;
        }

        return list
            .FindAll(
                TreeScope.Children,
                new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.ListItem))
            .Count;
    }
}
