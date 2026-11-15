// Copyright (c) Files Community and VmUiPipeline contributors.
// SPDX-License-Identifier: MPL-2.0

using System.IO;
using System.Text;

namespace VmUiPipeline.Runner;

internal sealed class RunnerLog : IDisposable
{
    private readonly StreamWriter _writer;
    private readonly object _gate = new();

    public RunnerLog(string outputDirectory)
    {
        Directory.CreateDirectory(outputDirectory);
        _writer = new StreamWriter(
            Path.Combine(outputDirectory, "run.log"),
            append: false,
            encoding: new UTF8Encoding(false))
        {
            AutoFlush = true,
        };
    }

    public void Write(string message)
    {
        var line = $"{DateTime.Now:HH:mm:ss.fff} {message}";
        lock (_gate)
        {
            _writer.WriteLine(line);
            Console.WriteLine(line);
        }
    }

    public void Dispose() => _writer.Dispose();
}
