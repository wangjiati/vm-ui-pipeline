// Copyright (c) Files Community and VmUiPipeline contributors.
// SPDX-License-Identifier: MPL-2.0

using System.Diagnostics;
using System.IO;

namespace VmUiPipeline.Runner;

/// <summary>
/// Optional session recording. Starts ffmpeg with the gdigrab input inside the guest
/// session and stops it gracefully so the MP4 trailer is written.
/// </summary>
internal sealed class ScreenRecorder : IDisposable
{
    private readonly Process _process;
    private readonly Action<string> _log;

    private ScreenRecorder(Process process, Action<string> log)
    {
        _process = process;
        _log = log;
    }

    public static ScreenRecorder? Start(
        string ffmpegPath,
        string outputPath,
        int framesPerSecond,
        int maximumSeconds,
        Action<string> log)
    {
        try
        {
            var directory = Path.GetDirectoryName(outputPath);
            if (!string.IsNullOrEmpty(directory))
            {
                Directory.CreateDirectory(directory);
            }

            var arguments =
                $"-y -loglevel warning -f gdigrab -framerate {framesPerSecond} -i desktop " +
                $"-t {maximumSeconds} -c:v libx264 -preset ultrafast -crf 28 -pix_fmt yuv420p \"{outputPath}\"";

            var startInfo = new ProcessStartInfo(ffmpegPath)
            {
                Arguments = arguments,
                UseShellExecute = false,
                RedirectStandardInput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
            };

            var process = Process.Start(startInfo);
            if (process is null)
            {
                log("recording disabled: ffmpeg did not start.");
                return null;
            }

            process.ErrorDataReceived += (_, args) =>
            {
                if (!string.IsNullOrWhiteSpace(args.Data))
                {
                    log($"ffmpeg: {args.Data}");
                }
            };
            process.BeginErrorReadLine();
            log($"recording to {outputPath} ({framesPerSecond} fps, max {maximumSeconds}s)");
            return new ScreenRecorder(process, log);
        }
        catch (Exception exception)
        {
            log($"recording disabled: {exception.Message}");
            return null;
        }
    }

    public void Stop()
    {
        try
        {
            if (_process.HasExited)
            {
                return;
            }

            _process.StandardInput.WriteLine("q");
            _process.StandardInput.Flush();
            if (!_process.WaitForExit(15000))
            {
                _log("ffmpeg did not stop gracefully; killing it.");
                _process.Kill(entireProcessTree: true);
            }
        }
        catch (Exception exception)
        {
            _log($"recording stop failed: {exception.Message}");
            try
            {
                if (!_process.HasExited)
                {
                    _process.Kill(entireProcessTree: true);
                }
            }
            catch (Exception)
            {
                // Process already gone.
            }
        }
    }

    public void Dispose()
    {
        Stop();
        _process.Dispose();
    }
}
