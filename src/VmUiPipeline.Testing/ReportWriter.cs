// Copyright (c) Files Community and VmUiPipeline contributors.
// SPDX-License-Identifier: MPL-2.0

using System.IO;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace VmUiPipeline.Testing;

public static class ReportWriter
{
    public static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    public static string Write(TestReport report, string outputDirectory)
    {
        Directory.CreateDirectory(outputDirectory);
        var path = Path.Combine(outputDirectory, "summary.json");
        var temporaryPath = path + ".tmp";
        File.WriteAllText(temporaryPath, JsonSerializer.Serialize(report, JsonOptions), new UTF8Encoding(false));
        File.Move(temporaryPath, path, overwrite: true);
        return path;
    }

    public static string WriteTextResults(TestReport report, string outputDirectory)
    {
        Directory.CreateDirectory(outputDirectory);
        var path = Path.Combine(outputDirectory, "results.txt");
        var lines = report.Tests.Select(t =>
            $"{t.Status.ToString().ToUpperInvariant()}|{t.Name}|{t.Detail ?? string.Empty}");
        File.WriteAllLines(path, lines, new UTF8Encoding(false));
        return path;
    }
}
