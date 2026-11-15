// Copyright (c) Files Community and VmUiPipeline contributors.
// SPDX-License-Identifier: MPL-2.0

namespace VmUiPipeline.Runner;

public sealed class RunnerOptions
{
    public string SuitePath { get; private set; } = string.Empty;
    public string SuiteType { get; private set; } = string.Empty;
    public string OutputDirectory { get; private set; } = string.Empty;
    public string? AppPath { get; private set; }
    public string? AppArguments { get; private set; }
    public string? Folder { get; private set; }
    public string? Filter { get; private set; }
    public string? AppSha256 { get; private set; }
    public string? ProcessName { get; private set; }
    public string? RunId { get; private set; }
    public string? RecordPath { get; private set; }
    public string FfmpegPath { get; private set; } = "ffmpeg.exe";
    public int RecordFps { get; private set; } = 10;
    public bool NoScreenshots { get; private set; }
    public bool IgnoreDialogs { get; private set; }
    public int TimeoutSeconds { get; private set; } = 600;
    public int StartupTimeoutSeconds { get; private set; } = 60;
    public Dictionary<string, string> Parameters { get; } = new(StringComparer.OrdinalIgnoreCase);
    public bool ShowHelp { get; private set; }

    public static RunnerOptions Parse(string[] args)
    {
        var options = new RunnerOptions();

        for (var index = 0; index < args.Length; index++)
        {
            switch (args[index])
            {
                case "--suite":
                    options.SuitePath = RequireValue(args, ref index);
                    break;
                case "--type":
                    options.SuiteType = RequireValue(args, ref index);
                    break;
                case "--out":
                    options.OutputDirectory = RequireValue(args, ref index);
                    break;
                case "--exe":
                    options.AppPath = RequireValue(args, ref index);
                    break;
                case "--app-args":
                    options.AppArguments = RequireValue(args, ref index);
                    break;
                case "--folder":
                    options.Folder = RequireValue(args, ref index);
                    break;
                case "--filter":
                    options.Filter = RequireValue(args, ref index);
                    break;
                case "--app-sha256":
                    options.AppSha256 = RequireValue(args, ref index);
                    break;
                case "--process-name":
                    options.ProcessName = RequireValue(args, ref index);
                    break;
                case "--run-id":
                    options.RunId = RequireValue(args, ref index);
                    break;
                case "--record":
                    options.RecordPath = RequireValue(args, ref index);
                    break;
                case "--ffmpeg":
                    options.FfmpegPath = RequireValue(args, ref index);
                    break;
                case "--record-fps":
                    options.RecordFps = RequirePositiveInt(args, ref index);
                    break;
                case "--no-screenshots":
                    options.NoScreenshots = true;
                    break;
                case "--ignore-dialogs":
                    options.IgnoreDialogs = true;
                    break;
                case "--timeout":
                    options.TimeoutSeconds = RequirePositiveInt(args, ref index);
                    break;
                case "--startup-timeout":
                    options.StartupTimeoutSeconds = RequirePositiveInt(args, ref index);
                    break;
                case "--param":
                    AddParameter(options, RequireValue(args, ref index));
                    break;
                case "--help":
                case "-h":
                case "/?":
                    options.ShowHelp = true;
                    break;
                default:
                    throw new ArgumentException($"Unknown option: {args[index]}");
            }
        }

        return options;
    }

    public void Validate()
    {
        if (string.IsNullOrWhiteSpace(SuitePath))
        {
            throw new ArgumentException("--suite is required (path to the test suite assembly).");
        }

        if (!File.Exists(SuitePath))
        {
            throw new FileNotFoundException($"Suite assembly not found: {SuitePath}", SuitePath);
        }

        if (string.IsNullOrWhiteSpace(SuiteType))
        {
            throw new ArgumentException("--type is required (full name of the IUiTestSuite implementation).");
        }

        if (string.IsNullOrWhiteSpace(OutputDirectory))
        {
            throw new ArgumentException("--out is required (directory for summary.json and run.log).");
        }

        if (AppPath is not null && !File.Exists(AppPath))
        {
            throw new FileNotFoundException($"Application executable not found: {AppPath}", AppPath);
        }

        if (AppSha256 is not null && (AppSha256.Length != 64 || !AppSha256.All(Uri.IsHexDigit)))
        {
            throw new ArgumentException("--app-sha256 must be a 64-character hexadecimal SHA-256 digest.");
        }

        if (TimeoutSeconds < 0)
        {
            throw new ArgumentException("--timeout must be zero or positive.");
        }

        if (RecordFps <= 0)
        {
            throw new ArgumentException("--record-fps must be positive.");
        }
    }

    public static void PrintUsage()
    {
        Console.WriteLine(
            """
            VmUiPipeline.Runner - UI Automation test host for an interactive Windows session.

            Usage:
              VmUiPipeline.Runner --suite <assembly.dll> --type <namespace.Type> --out <directory>
                                  [--exe <app.exe>] [--app-args <args>] [--folder <path>]
                                  [--filter <regex>] [--param key=value ...]
                                  [--timeout <seconds>] [--startup-timeout <seconds>]
                                  [--record <mp4>] [--ffmpeg <path>] [--record-fps <n>]
                                  [--no-screenshots] [--ignore-dialogs]
                                  [--app-sha256 <hex>] [--process-name <name>]
                                  [--run-id <id>] [--help]

            Exit codes:
              0  all tests passed
              1  one or more tests failed
              2  invalid arguments or suite could not be loaded
              3  timeout
              4  the application could not be launched
            """);
    }

    private static string RequireValue(string[] args, ref int index)
    {
        if (index + 1 >= args.Length)
        {
            throw new ArgumentException($"Option {args[index]} requires a value.");
        }

        index++;
        return args[index];
    }

    private static int RequirePositiveInt(string[] args, ref int index)
    {
        var raw = RequireValue(args, ref index);
        if (!int.TryParse(raw, out var value) || value < 0)
        {
            throw new ArgumentException($"Option {args[index - 1]} requires a non-negative integer, got '{raw}'.");
        }

        return value;
    }

    private static void AddParameter(RunnerOptions options, string raw)
    {
        var separator = raw.IndexOf('=');
        if (separator <= 0)
        {
            throw new ArgumentException($"--param expects key=value, got '{raw}'.");
        }

        options.Parameters[raw[..separator]] = raw[(separator + 1)..];
    }
}
