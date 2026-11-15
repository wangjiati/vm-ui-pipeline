// Copyright (c) Files Community and VmUiPipeline contributors.
// SPDX-License-Identifier: MPL-2.0

using System.Collections.ObjectModel;
using System.Windows;

namespace SampleApp;

public partial class MainWindow : Window
{
    private static readonly string[] RootItems = ["alpha.zip", "beta.zip", "notes.md"];
    private static readonly string[] NestedItems = ["sub\\gamma.zip", "sub\\deep\\delta.zip"];

    private readonly ObservableCollection<string> _visible = [];

    public MainWindow()
    {
        InitializeComponent();
        ResultsList.ItemsSource = _visible;
        Apply();
    }

    private void ApplyButton_Click(object sender, RoutedEventArgs e) => Apply();

    private void ClearButton_Click(object sender, RoutedEventArgs e)
    {
        KeywordBox.Text = string.Empty;
        RecurseCheck.IsChecked = false;
        Apply();
    }

    private void Apply()
    {
        var keyword = KeywordBox.Text.Trim();
        var source = RecurseCheck.IsChecked == true
            ? RootItems.Concat(NestedItems)
            : RootItems;

        var matches = source
            .Where(item => keyword.Length == 0 || item.Contains(keyword, StringComparison.OrdinalIgnoreCase))
            .ToList();

        _visible.Clear();
        foreach (var match in matches)
        {
            _visible.Add(match);
        }

        CountText.Text = $"{_visible.Count} matching items";
    }
}
