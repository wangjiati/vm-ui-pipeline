// Copyright (c) Files Community and VmUiPipeline contributors.
// SPDX-License-Identifier: MPL-2.0

using System.IO;
using System.Windows.Automation;
using System.Windows.Forms;
using VmUiPipeline.Testing;

namespace FilesFilterTests;

/// <summary>
/// 原 Files 筛选验收套件，移植到可复用测试库。它需要打包后的 Files 应用
/// （<c>Files.exe</c>）以及包含两个根级 zip、两个文本文件、两个嵌套 zip 的夹具目录。
/// </summary>
public sealed class FilesFilterSuite : IUiTestSuite
{
    public string Name => "FilesFilter";

    public void Run(UiTestContext context)
    {
        var window = context.Require(context.MainWindow, "Files main window");
        WaitForFilterBar(context, 25);
        EnsureFolder(context, 25);

        context.Test("launch", () =>
        {
            context.Assert(!string.IsNullOrWhiteSpace(window.Current.Name), $"title '{window.Current.Name}'");
        });

        context.Test("filter-bar", () =>
        {
            var keyword = context.FindById("KeywordBox") ?? context.FindById("FilterTextBox");
            context.Assert(keyword is not null, "keyword box");
            var basic = context.FindByNameAny(["常规", "Basic"], ControlType.ListItem);
            var advanced = context.FindByNameAny(["高级", "Advanced"], ControlType.ListItem);
            context.Assert(basic is not null && advanced is not null, "mode selector items");
        });

        context.Test("labels-zh", () =>
        {
            var basic = context.FindByNameAny(["常规", "Basic"], ControlType.ListItem);
            var advanced = context.FindByNameAny(["高级", "Advanced"], ControlType.ListItem);
            var recurse = context.FindByNameAny(["搜索子文件夹", "Search subfolders"], ControlType.CheckBox);
            var clear = context.FindByNameAny(["清除所有筛选", "Clear all filters"], ControlType.Button) ??
                        context.FindByNameAny(["清除所有筛选", "Clear all filters"], null);
            var observed = string.Join(
                " | ",
                new[] { basic?.Current.Name, advanced?.Current.Name, recurse?.Current.Name, clear?.Current.Name }
                    .Select(name => name ?? "<null>"));
            context.Assert(
                basic?.Current.Name == "常规" &&
                advanced?.Current.Name == "高级" &&
                recurse?.Current.Name == "搜索子文件夹",
                $"observed: {observed}");
        });

        context.Test("basic-wildcard", () =>
        {
            SelectMode(context, "常规", "Basic");
            var keyword = context.WaitForId("KeywordBox", TimeSpan.FromSeconds(6), "keyword box");
            context.Assert(keyword is not null, "keyword box");
            context.Assert(context.SetText(keyword!, "*.zip"), "set keyword");
            var count = WaitCount(context, 6);
            context.Assert(count == 2, $"expected 2 zips, got {count?.ToString() ?? "<null>"}");
        });

        context.Test("advanced-editor", () =>
        {
            SelectMode(context, "高级", "Advanced");
            var editor = context.WaitForId("FilterTextBox", TimeSpan.FromSeconds(6), "name condition editor");
            context.Assert(editor is not null, "name condition editor");
            var combo = context.WaitFor(
                () => context.FindByControlType(ControlType.ComboBox),
                TimeSpan.FromSeconds(4),
                "operator/scope combo");
            context.Assert(combo is not null, "operator/scope combo");
        });

        context.Test("recursion-location", () =>
        {
            SelectMode(context, "常规", "Basic");
            var keyword = context.WaitForId("KeywordBox", TimeSpan.FromSeconds(6), "keyword box");
            context.Assert(keyword is not null, "keyword box");
            context.Assert(context.SetText(keyword!, "*.zip"), "set keyword");
            WaitCount(context, 6);
            var checkbox = context.FindByNameAny(["搜索子文件夹", "Search subfolders"], ControlType.CheckBox);
            context.Assert(checkbox is not null, "recursion checkbox");
            context.Assert(context.Toggle(checkbox!), "toggle recursion");
            Thread.Sleep(2500);
            var location = context.FindByNameAny(["位置", "Location"], null);
            context.Assert(location is not null, "location column");
            var count = GetCount(context);
            context.Assert(count == 4, $"expected 4 zips with 2 levels, got {count?.ToString() ?? "<null>"}");
        });

        context.Test("clear-all", () =>
        {
            var clear = context.FindByNameAny(["清除所有筛选", "Clear all filters"], ControlType.Button) ??
                        context.FindByNameAny(["清除所有筛选", "Clear all filters"], null);
            context.Assert(clear is not null, "clear button");
            context.Assert(context.Invoke(clear!), "invoke clear");
            Thread.Sleep(1500);
            var count = GetCount(context);
            var total = context.Folder is null ? 0 : Directory.EnumerateFileSystemEntries(context.Folder).Count();
            context.Assert(count is null || count == total, $"after clear count={count?.ToString() ?? "<null>"}, entries={total}");
        });

        context.Test("column-header-append", () =>
        {
            var headerFilters = context.FindAll()
                .Where(element => element.Current.ControlType == ControlType.Button)
                .Where(element =>
                    (element.Current.Name ?? string.Empty).Contains("筛选") ||
                    (element.Current.Name ?? string.Empty).Contains("Filter") ||
                    (element.Current.AutomationId ?? string.Empty).Contains("Filter"))
                .ToList();
            context.Log($"header filter buttons: {headerFilters.Count}");
            foreach (var candidate in headerFilters)
            {
                var rect = candidate.Current.BoundingRectangle;
                context.Log(
                    $"  header button name=[{candidate.Current.Name}] id=[{candidate.Current.AutomationId}] x={rect.X} y={rect.Y}");
            }

            context.Assert(headerFilters.Count >= 2, $"header filter buttons found: {headerFilters.Count}");
            var headerButton = headerFilters.OrderBy(element => element.Current.BoundingRectangle.Y).Last();
            context.Assert(context.Invoke(headerButton), "invoke header filter");
            Thread.Sleep(1500);
            var advanced = context.FindByNameAny(["高级", "Advanced"], ControlType.ListItem);
            var editor = context.WaitForId("FilterTextBox", TimeSpan.FromSeconds(5), "advanced name editor");
            context.Assert(advanced is not null && editor is not null, "advanced name editor after header click");
        });
    }

    private static void SelectMode(UiTestContext context, params string[] names)
    {
        var item = context.FindByNameAny(names, ControlType.ListItem);
        context.Assert(item is not null, $"mode item {string.Join("/", names)}");
        context.Assert(context.Select(item!), "selection pattern");
        Thread.Sleep(600);
    }

    private static void WaitForFilterBar(UiTestContext context, int seconds)
    {
        if (WaitBarReady(context, seconds))
        {
            return;
        }

        context.Log("filter bar hidden; trying Ctrl+Shift+F");
        SendKeys.SendWait("^+f");
        Thread.Sleep(2500);
        if (WaitBarReady(context, 6))
        {
            return;
        }

        context.Log("still hidden; invoking toolbar filter toggle");
        var toggle = context.FindByNameAny(["筛选", "Filter"], ControlType.Button);
        if (toggle is not null)
        {
            context.Invoke(toggle);
            Thread.Sleep(2500);
        }

        WaitBarReady(context, 8);
    }

    private static bool WaitBarReady(UiTestContext context, int seconds)
    {
        var end = DateTime.UtcNow.AddSeconds(seconds);
        while (DateTime.UtcNow < end)
        {
            if (context.FindById("KeywordBox") is not null || context.FindById("FilterTextBox") is not null)
            {
                context.Log("filter bar ready");
                return true;
            }

            Thread.Sleep(300);
        }

        return false;
    }

    private static void EnsureFolder(UiTestContext context, int seconds)
    {
        var marker = Path.GetFileName(context.Folder ?? string.Empty);
        var end = DateTime.UtcNow.AddSeconds(seconds);
        while (DateTime.UtcNow < end)
        {
            if (context.FindByName(marker) is not null)
            {
                context.Log($"folder view ready: {marker}");
                return;
            }

            Thread.Sleep(300);
        }

        var address = context.FindById("PART_TextBox");
        if (address is null)
        {
            context.Log("address bar not found; cannot navigate");
            return;
        }

        context.Log($"navigating to {context.Folder}");
        address.SetFocus();
        context.SetText(address, context.Folder ?? string.Empty);
        Thread.Sleep(300);
        SendKeys.SendWait("{ENTER}");
        Thread.Sleep(3000);
    }

    private static int? WaitCount(UiTestContext context, int seconds)
    {
        var end = DateTime.UtcNow.AddSeconds(seconds);
        int? last = null;
        while (DateTime.UtcNow < end)
        {
            last = GetCount(context);
            if (last is not null)
            {
                return last;
            }

            Thread.Sleep(200);
        }

        return last;
    }

    private static int? GetCount(UiTestContext context)
    {
        foreach (var element in context.FindAll())
        {
            if (element.Current.ControlType != ControlType.Text)
            {
                continue;
            }

            var match = System.Text.RegularExpressions.Regex.Match(
                element.Current.Name ?? string.Empty,
                @"^(\d+)\s*(个匹配项|matching items)$");
            if (match.Success)
            {
                return int.Parse(match.Groups[1].Value);
            }
        }

        return null;
    }
}
