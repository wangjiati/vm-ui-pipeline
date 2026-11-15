# Copyright (c) Files Community and VmUiPipeline contributors.
# SPDX-License-Identifier: MPL-2.0

<#
.SYNOPSIS
Runs Windows desktop UI automation tests inside one or more VM interactive sessions.

.DESCRIPTION
This module owns the host side of the pipeline: it reads a pipeline.json, stages the
application, runner, suite, and fixtures over SMB, launches the runner in the guest's
logged-on desktop session through a launcher backend, and collects JSON results.

The only launcher backend is win-simple-ssh: it starts the runner in the guest's
logged-on interactive console session. The host never launches the application under
test and never drives UI on the host.

.PRIVATE
#>

$ErrorActionPreference = 'Stop'

$script:ModuleRoot = $PSScriptRoot
. (Join-Path $PSScriptRoot 'launchers\WinSimpleSsh.ps1')

function Import-VmUiPipelineConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $resolved = Resolve-Path -LiteralPath $Path -ErrorAction Stop
    $configPath = $resolved.ProviderPath
    $configDirectory = Split-Path -Parent $configPath
    $raw = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $raw) {
        throw "Configuration is empty: $configPath"
    }

    $schemaVersion = if ($null -ne $raw.schemaVersion) { [int]$raw.schemaVersion } else { 0 }
    if ($schemaVersion -ne 1) {
        throw "Unsupported schemaVersion '$schemaVersion' in $configPath. Expected 1."
    }

    $guestRoot = if ($raw.guestRoot) { [string]$raw.guestRoot } else { 'C:\VmUiPipeline' }
    $guestRoot = $guestRoot.TrimEnd('\')
    if ($guestRoot -notmatch '^[A-Za-z]:\\') {
        throw "guestRoot must be an absolute Windows path, got '$guestRoot'."
    }

    if ($null -eq $raw.artifact -or [string]::IsNullOrWhiteSpace([string]$raw.artifact.path)) {
        throw "artifact.path is required."
    }

    $artifactPath = Resolve-VmConfigPath -Path ([string]$raw.artifact.path) -BaseDirectory $configDirectory -Description 'artifact.path'
    if (-not (Test-Path -LiteralPath $artifactPath)) {
        throw "artifact.path does not exist: $artifactPath"
    }

    $artifactIsZip = $artifactPath -match '\.zip$'
    if (-not $artifactIsZip -and -not (Test-Path -LiteralPath $artifactPath -PathType Container)) {
        throw "artifact.path must be a directory or a .zip file: $artifactPath"
    }

    $artifactExe = [string]$raw.artifact.exe
    if ([string]::IsNullOrWhiteSpace($artifactExe)) {
        throw "artifact.exe is required (path to the application executable inside the artifact)."
    }

    if (-not $artifactIsZip) {
        $artifactExePath = Join-Path $artifactPath $artifactExe
        if (-not (Test-Path -LiteralPath $artifactExePath -PathType Leaf)) {
            throw "artifact.exe was not found inside the artifact directory: $artifactExePath"
        }
    }

    if ($null -eq $raw.runner -or [string]::IsNullOrWhiteSpace([string]$raw.runner.path)) {
        throw "runner.path is required."
    }

    $runnerPath = Resolve-VmConfigPath -Path ([string]$raw.runner.path) -BaseDirectory $configDirectory -Description 'runner.path'
    if (-not (Test-Path -LiteralPath $runnerPath -PathType Leaf)) {
        throw "runner.path does not exist: $runnerPath"
    }

    if ($null -eq $raw.suite -or [string]::IsNullOrWhiteSpace([string]$raw.suite.assembly)) {
        throw "suite.assembly is required."
    }

    if ([string]::IsNullOrWhiteSpace([string]$raw.suite.type)) {
        throw "suite.type is required (full name of the IUiTestSuite implementation)."
    }

    $suiteAssembly = Resolve-VmConfigPath -Path ([string]$raw.suite.assembly) -BaseDirectory $configDirectory -Description 'suite.assembly'
    if (-not (Test-Path -LiteralPath $suiteAssembly -PathType Leaf)) {
        throw "suite.assembly does not exist: $suiteAssembly"
    }

    $suiteFolder = $null
    if ($raw.suite.folder) {
        $suiteFolder = [string]$raw.suite.folder
        if ($suiteFolder -notmatch '^[A-Za-z]:\\' -and $suiteFolder -notmatch '^\\\\') {
            $suiteFolder = Resolve-VmConfigPath -Path $suiteFolder -BaseDirectory $configDirectory -Description 'suite.folder'
        }
    }

    $suiteParameters = @{}
    if ($raw.suite.parameters) {
        foreach ($property in $raw.suite.parameters.PSObject.Properties) {
            $suiteParameters[$property.Name] = [string]$property.Value
        }
    }

    $fixtures = @()
    foreach ($fixture in @($raw.fixtures)) {
        if ($null -eq $fixture) {
            continue
        }

        if ([string]::IsNullOrWhiteSpace([string]$fixture.source)) {
            throw "fixtures[].source is required."
        }

        if ([string]::IsNullOrWhiteSpace([string]$fixture.destination)) {
            throw "fixtures[].destination is required."
        }

        $fixtureSource = Resolve-VmConfigPath -Path ([string]$fixture.source) -BaseDirectory $configDirectory -Description 'fixtures[].source'
        if (-not (Test-Path -LiteralPath $fixtureSource)) {
            throw "Fixture source does not exist: $fixtureSource"
        }

        $clean = $true
        if ($null -ne $fixture.clean) {
            $clean = [bool]$fixture.clean
        }

        $fixtures += [pscustomobject]@{
            Source      = $fixtureSource
            Destination = [string]$fixture.destination
            Clean       = $clean
        }
    }

    $launcherType = if ($raw.launcher -and $raw.launcher.type) { [string]$raw.launcher.type } else { 'win-simple-ssh' }
    if ($launcherType -ne 'win-simple-ssh') {
        throw "launcher.type must be 'win-simple-ssh'. Host-side UI testing is not supported."
    }

    $vmrunDefault = 'C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe'
    $launcher = [pscustomobject]@{
        Type         = $launcherType
        SshcPath     = $null
        SshServerExe = $null
        Port         = 22222
        IpWhitelist  = @()
        VmrunPath    = $vmrunDefault
    }

    if ($launcherType -eq 'win-simple-ssh') {
        if ($null -eq $raw.launcher -or [string]::IsNullOrWhiteSpace([string]$raw.launcher.sshcPath)) {
            throw "launcher.sshcPath is required for the win-simple-ssh launcher."
        }

        if ([string]::IsNullOrWhiteSpace([string]$raw.launcher.sshServerExe)) {
            throw "launcher.sshServerExe is required for the win-simple-ssh launcher."
        }

        $launcher.SshcPath = Resolve-VmConfigPath -Path ([string]$raw.launcher.sshcPath) -BaseDirectory $configDirectory -Description 'launcher.sshcPath'
        $launcher.SshServerExe = Resolve-VmConfigPath -Path ([string]$raw.launcher.sshServerExe) -BaseDirectory $configDirectory -Description 'launcher.sshServerExe'
        if (-not (Test-Path -LiteralPath $launcher.SshcPath -PathType Leaf)) {
            throw "launcher.sshcPath does not exist: $($launcher.SshcPath)"
        }

        if (-not (Test-Path -LiteralPath $launcher.SshServerExe -PathType Leaf)) {
            throw "launcher.sshServerExe does not exist: $($launcher.SshServerExe)"
        }

        if ($raw.launcher.port) {
            $launcher.Port = [int]$raw.launcher.port
        }

        $launcher.IpWhitelist = @($raw.launcher.ipWhitelist | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        if ($launcher.IpWhitelist.Count -eq 0) {
            throw "launcher.ipWhitelist must contain at least one entry (for example '192.168.221.*')."
        }

        if ($raw.launcher.vmrunPath) {
            $launcher.VmrunPath = Resolve-VmConfigPath -Path ([string]$raw.launcher.vmrunPath) -BaseDirectory $configDirectory -Description 'launcher.vmrunPath'
        }
    }

    $vms = @()
    foreach ($vm in @($raw.vms)) {
        if ($null -eq $vm) {
            continue
        }

        if ([string]::IsNullOrWhiteSpace([string]$vm.name)) {
            throw "vms[].name is required."
        }

        $name = [string]$vm.name
        $address = [string]$vm.address
        if ([string]::IsNullOrWhiteSpace($address)) {
            throw "vms[].address is required for '$name'."
        }

        $user = [string]$vm.user
        if ([string]::IsNullOrWhiteSpace($user)) {
            $user = $env:USERNAME
        }

        $passwordEnv = [string]$vm.passwordEnv
        if ([string]::IsNullOrWhiteSpace($passwordEnv)) {
            $passwordEnv = 'VM_' + ($name.ToUpperInvariant() -replace '[^A-Z0-9]', '_') + '_PASSWORD'
        }

        $shareName = [string]$vm.shareName
        if ([string]::IsNullOrWhiteSpace($shareName)) {
            $shareName = 'c$'
        }

        $vms += [pscustomobject]@{
            Name        = $name
            Address     = $address
            User        = $user
            PasswordEnv = $passwordEnv
            ShareName   = $shareName
            Vmx         = [string]$vm.vmx
            Snapshot    = [string]$vm.snapshot
        }
    }

    if ($vms.Count -eq 0) {
        throw "At least one VM must be configured."
    }

    $timeoutMinutes = if ($raw.timeoutMinutes) { [int]$raw.timeoutMinutes } else { 10 }
    if ($timeoutMinutes -le 0) {
        throw "timeoutMinutes must be positive."
    }

    $startupTimeoutSeconds = if ($raw.startupTimeoutSeconds) { [int]$raw.startupTimeoutSeconds } else { 60 }
    if ($startupTimeoutSeconds -le 0) {
        throw "startupTimeoutSeconds must be positive."
    }

    $recordingEnabled = $false
    $recordingFfmpeg = 'ffmpeg.exe'
    $recordingFps = 10
    if ($raw.recording) {
        if ($null -ne $raw.recording.enabled) {
            $recordingEnabled = [bool]$raw.recording.enabled
        }

        if ($raw.recording.ffmpegPath) {
            $recordingFfmpeg = [string]$raw.recording.ffmpegPath
        }

        if ($raw.recording.fps) {
            $recordingFps = [int]$raw.recording.fps
        }
    }

    if ($recordingFps -le 0) {
        throw "recording.fps must be positive."
    }

    $resultsDirectory = if ($raw.resultsDirectory) {
        Resolve-VmConfigPath -Path ([string]$raw.resultsDirectory) -BaseDirectory $configDirectory -Description 'resultsDirectory'
    }
    else {
        Join-Path $configDirectory 'artifacts\results'
    }

    return [pscustomobject]@{
        SchemaVersion         = $schemaVersion
        ConfigPath            = $configPath
        ConfigDirectory       = $configDirectory
        GuestRoot             = $guestRoot
        TimeoutMinutes        = $timeoutMinutes
        StartupTimeoutSeconds = $startupTimeoutSeconds
        ResultRoot            = $resultsDirectory
        Artifact              = [pscustomobject]@{
            Path   = $artifactPath
            Exe    = $artifactExe
            IsZip  = $artifactIsZip
            Arguments = [string]$raw.artifact.arguments
            ProcessName = [string]$raw.artifact.processName
        }
        Runner                = [pscustomobject]@{ Path = $runnerPath }
        Suite                 = [pscustomobject]@{
            Assembly   = $suiteAssembly
            Type       = [string]$raw.suite.type
            Folder     = $suiteFolder
            Parameters = $suiteParameters
        }
        Fixtures              = $fixtures
        Launcher              = $launcher
        Recording             = [pscustomobject]@{
            Enabled    = $recordingEnabled
            FfmpegPath = $recordingFfmpeg
            Fps        = $recordingFps
        }
        Vms                   = $vms
    }
}

function Invoke-VmUiPipeline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,

        [string[]]$Vm,

        [switch]$RevertSnapshots,

        [string]$OutputDirectory,

        [switch]$KeepWorkDirectory
    )

    $config = Import-VmUiPipelineConfig -Path $ConfigPath

    $selected = @($config.Vms)
    if ($Vm) {
        $selected = @($config.Vms | Where-Object { $Vm -contains $_.Name })
        $missing = @($Vm | Where-Object { $name = $_; -not ($config.Vms | Where-Object { $_.Name -eq $name }) })
        if ($missing.Count -gt 0) {
            throw "Unknown VM name(s): $($missing -join ', ')."
        }
    }

    if ($selected.Count -eq 0) {
        throw "No VM selected."
    }

    $runId = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $runRoot = if ($OutputDirectory) {
        Join-Path $OutputDirectory $runId
    }
    else {
        Join-Path $config.ResultRoot $runId
    }

    New-Item -ItemType Directory -Force -Path $runRoot | Out-Null
    $startedUtc = (Get-Date).ToUniversalTime()

    Write-Host "==> run $runId"
    Write-Host "    config  : $($config.ConfigPath)"
    Write-Host "    results : $runRoot"

    Write-Utf8File -Path (Join-Path $runRoot 'run.json') -Content (ConvertTo-Json -InputObject ([pscustomobject]@{
        schemaVersion = 1
        runId         = $runId
        startedUtc    = $startedUtc.ToString('o')
        configPath    = $config.ConfigPath
        guestRoot     = $config.GuestRoot
        artifact      = $config.Artifact.Path
        runner        = $config.Runner.Path
        suite         = $config.Suite.Assembly
        suiteType     = $config.Suite.Type
        launcher      = $config.Launcher.Type
        vms           = @($selected | ForEach-Object { $_.Name })
    }) -Depth 6)

    $workDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("vm-ui-pipeline-" + $runId)
    if (Test-Path -LiteralPath $workDirectory) {
        Remove-Item -LiteralPath $workDirectory -Recurse -Force
    }

    New-Item -ItemType Directory -Force -Path $workDirectory | Out-Null

    try {
        $artifactDirectory = Expand-VmArtifact -Artifact $config.Artifact -WorkDirectory $workDirectory
        $appPath = Join-Path $artifactDirectory $config.Artifact.Exe
        if (-not (Test-Path -LiteralPath $appPath -PathType Leaf)) {
            throw "Application executable was not found after expanding the artifact: $appPath"
        }

        $appSha256 = (Get-FileHash -LiteralPath $appPath -Algorithm SHA256).Hash
        Write-Host "    app     : $appPath"
        Write-Host "    sha256  : $appSha256"

        $runs = @()
        foreach ($vmItem in $selected) {
            Write-Host ""
            Write-Host "==> $($vmItem.Name) ($($vmItem.Address))" -ForegroundColor Cyan
            try {
                $run = Invoke-RemoteVmRun -Config $config -Vm $vmItem -ArtifactDirectory $artifactDirectory `
                    -AppPath $appPath -AppSha256 $appSha256 -RunRoot $runRoot -RunId $runId `
                    -RevertSnapshot:$RevertSnapshots
            }
            catch {
                $run = New-VmFailureRun -Vm $vmItem -Error $_.Exception.Message -Status 'error' -ResultsPath (Join-Path $runRoot $vmItem.Name)
            }

            $runs += $run
            Write-VmRunSummary -Run $run
        }

        $finishedUtc = (Get-Date).ToUniversalTime()
        $summary = New-VmUiPipelineSummary -Runs $runs -RunId $runId -StartedUtc $startedUtc -FinishedUtc $finishedUtc
        Write-Utf8File -Path (Join-Path $runRoot 'pipeline-summary.json') -Content (ConvertTo-Json -InputObject $summary -Depth 12)
        ConvertTo-VmUiPipelineJUnit -Runs $runs -Path (Join-Path $runRoot 'junit.xml')
        Write-VmUiPipelineMarkdownReport -Summary $summary -Path (Join-Path $runRoot 'report.md')
        Write-VmUiPipelineConsoleReport -Summary $summary

        Write-Host ""
        Write-Host "Results: $runRoot"
        return $summary
    }
    finally {
        if (-not $KeepWorkDirectory) {
            Remove-Item -LiteralPath $workDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-RemoteVmRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Config,
        [Parameter(Mandatory = $true)][object]$Vm,
        [Parameter(Mandatory = $true)][string]$ArtifactDirectory,
        [Parameter(Mandatory = $true)][string]$AppPath,
        [Parameter(Mandatory = $true)][string]$AppSha256,
        [Parameter(Mandatory = $true)][string]$RunRoot,
        [Parameter(Mandatory = $true)][string]$RunId,
        [switch]$RevertSnapshot
    )

    $password = Get-VmPassword -Vm $Vm

    if ($RevertSnapshot) {
        Restore-VmSnapshot -Config $Config -Vm $Vm
    }

    $mapping = Connect-VmShare -Vm $Vm -Password $password
    try {
        $guestRoot = $Config.GuestRoot
        $uncRoot = ConvertTo-VmUncPath -GuestPath $guestRoot -Vm $Vm
        foreach ($child in @('app', 'runner', 'suite', 'fixtures', 'results')) {
            New-Item -ItemType Directory -Force -Path (Join-Path $uncRoot $child) | Out-Null
        }

        $uncApp = Join-Path $uncRoot 'app'
        $uncRunner = Join-Path $uncRoot 'runner'
        $uncSuite = Join-Path $uncRoot 'suite'
        $uncResults = Join-Path $uncRoot 'results'

        Write-Host "    staging application"
        Clear-VmDirectory -Path $uncApp
        Invoke-Robocopy -Source $ArtifactDirectory -Destination $uncApp

        Write-Host "    staging runner"
        Clear-VmDirectory -Path $uncRunner
        Invoke-Robocopy -Source (Split-Path -Parent $Config.Runner.Path) -Destination $uncRunner

        Write-Host "    staging suite"
        Clear-VmDirectory -Path $uncSuite
        Invoke-Robocopy -Source (Split-Path -Parent $Config.Suite.Assembly) -Destination $uncSuite

        foreach ($fixture in $Config.Fixtures) {
            $fixtureGuest = $fixture.Destination
            if ($fixtureGuest -notmatch '^[A-Za-z]:\\' -and $fixtureGuest -notmatch '^\\\\') {
                $fixtureGuest = Join-Path $guestRoot $fixtureGuest
            }

            $fixtureUnc = ConvertTo-VmUncPath -GuestPath $fixtureGuest -Vm $Vm
            Write-Host "    staging fixture -> $fixtureGuest"
            if ($fixture.Clean) {
                Clear-VmDirectory -Path $fixtureUnc
            }

            New-Item -ItemType Directory -Force -Path $fixtureUnc | Out-Null
            Invoke-Robocopy -Source $fixture.Source -Destination $fixtureUnc
        }

        Clear-VmDirectory -Path $uncResults

        $appGuestPath = Join-Path (Join-Path $guestRoot 'app') $Config.Artifact.Exe
        $runnerGuestPath = Join-Path (Join-Path $guestRoot 'runner') (Split-Path -Leaf $Config.Runner.Path)
        $suiteGuestPath = Join-Path (Join-Path $guestRoot 'suite') (Split-Path -Leaf $Config.Suite.Assembly)

        if (-not (Test-Path -LiteralPath (ConvertTo-VmUncPath -GuestPath $appGuestPath -Vm $Vm) -PathType Leaf)) {
            throw "Application was not staged to the guest: $appGuestPath"
        }

        if (-not (Test-Path -LiteralPath (ConvertTo-VmUncPath -GuestPath $runnerGuestPath -Vm $Vm) -PathType Leaf)) {
            throw "Runner was not staged to the guest: $runnerGuestPath"
        }

        if (-not (Test-Path -LiteralPath (ConvertTo-VmUncPath -GuestPath $suiteGuestPath -Vm $Vm) -PathType Leaf)) {
            throw "Suite was not staged to the guest: $suiteGuestPath"
        }

        $runnerArguments = @(
            '--suite', $suiteGuestPath,
            '--type', $Config.Suite.Type,
            '--out', (Join-Path $guestRoot 'results'),
            '--exe', $appGuestPath,
            '--app-sha256', $AppSha256,
            '--timeout', [string]($Config.TimeoutMinutes * 60),
            '--startup-timeout', [string]$Config.StartupTimeoutSeconds,
            '--run-id', $RunId
        )

        if ($Config.Artifact.Arguments) {
            $runnerArguments += @('--app-args', $Config.Artifact.Arguments)
        }

        if ($Config.Artifact.ProcessName) {
            $runnerArguments += @('--process-name', $Config.Artifact.ProcessName)
        }

        if ($Config.Suite.Folder) {
            $runnerArguments += @('--folder', $Config.Suite.Folder)
        }

        if ($Config.Recording.Enabled) {
            $runnerArguments += @(
                '--record', (Join-Path $guestRoot 'results\session.mp4'),
                '--ffmpeg', $Config.Recording.FfmpegPath,
                '--record-fps', [string]$Config.Recording.Fps
            )
        }

        foreach ($key in $Config.Suite.Parameters.Keys) {
            $runnerArguments += @('--param', ("{0}={1}" -f $key, $Config.Suite.Parameters[$key]))
        }

        $scriptContent = New-VmRunCommand -RunnerPath $runnerGuestPath -Arguments $runnerArguments `
            -ResultsDirectory (Join-Path $guestRoot 'results') -GuestRoot $guestRoot
        Write-Utf8File -Path (Join-Path $uncRoot 'run.cmd') -Content $scriptContent

        Write-Host "    starting WinSimpleSSH service if needed"
        Initialize-VmSshService -Vm $Vm -Launcher $Config.Launcher -Password $password `
            -UncGuestRoot $uncRoot -GuestRoot $guestRoot

        $appProcessName = if ($Config.Artifact.ProcessName) {
            $Config.Artifact.ProcessName
        }
        else {
            [System.IO.Path]::GetFileNameWithoutExtension($Config.Artifact.Exe)
        }

        Write-Host "    stopping stale guest processes"
        Stop-VmSshProcesses -Vm $Vm -Launcher $Config.Launcher -Password $password -ProcessNames @($appProcessName, 'VmUiPipeline.Runner')

        Write-Host "    launching runner in the interactive desktop session"
        Start-VmSshProcess -Vm $Vm -Launcher $Config.Launcher -Password $password `
            -Program (Join-Path $guestRoot 'run.cmd')

        $wait = Wait-VmSummary -SummaryPath (Join-Path $uncResults 'summary.json') `
            -ExitCodePath (Join-Path $uncResults 'exitcode.txt') `
            -TimeoutMinutes $Config.TimeoutMinutes

        $localDirectory = Join-Path $RunRoot $Vm.Name
        New-Item -ItemType Directory -Force -Path $localDirectory | Out-Null
        if (Test-Path -LiteralPath $uncResults) {
            Copy-Item -Path (Join-Path $uncResults '*') -Destination $localDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }

        if (-not $wait.Completed) {
            $detail = $wait.Detail
            if ($wait.TimedOut) {
                return New-VmFailureRun -Vm $Vm -Error $detail -Status 'timeout' -ResultsPath $localDirectory
            }

            return New-VmFailureRun -Vm $Vm -Error $detail -Status 'error' -ResultsPath $localDirectory
        }

        $summary = Read-VmSummary -Path (Join-Path $localDirectory 'summary.json')
        return New-VmRunResult -Vm $Vm -Summary $summary -ResultsPath $localDirectory -Status 'completed'
    }
    finally {
        Disconnect-VmShare -Mapping $mapping
    }
}

function New-VmUiPipelineSummary {
    [CmdletBinding()]
    param(
        [object[]]$Runs,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][datetime]$StartedUtc,
        [Parameter(Mandatory = $true)][datetime]$FinishedUtc
    )

    $runList = @($Runs)
    $passed = 0
    $failed = 0
    $skipped = 0
    $total = 0
    foreach ($run in $runList) {
        $passed += [int]$run.Passed
        $failed += [int]$run.Failed
        $skipped += [int]$run.Skipped
        $total += [int]$run.Total
    }

    $exitCode = 0
    if ($runList.Count -eq 0) {
        $exitCode = 2
    }
    elseif (@($runList | Where-Object { $_.Status -eq 'timeout' }).Count -gt 0) {
        $exitCode = 3
    }
    elseif ($failed -gt 0 -or @($runList | Where-Object { $_.Status -eq 'error' }).Count -gt 0) {
        $exitCode = 1
    }

    return [pscustomobject]@{
        SchemaVersion = 1
        RunId         = $RunId
        StartedUtc    = $StartedUtc.ToString('o')
        FinishedUtc   = $FinishedUtc.ToString('o')
        DurationMs    = [math]::Round(($FinishedUtc - $StartedUtc).TotalMilliseconds, 1)
        Passed        = $passed
        Failed        = $failed
        Skipped       = $skipped
        Total         = $total
        ExitCode      = $exitCode
        Vms           = $runList
    }
}

function ConvertTo-VmUiPipelineJUnit {
    [CmdletBinding()]
    param(
        [object[]]$Runs,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $runList = @($Runs)
    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)
    $settings.OmitXmlDeclaration = $false

    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }

    $writer = [System.Xml.XmlWriter]::Create($Path, $settings)
    try {
        $writer.WriteStartDocument()
        $writer.WriteStartElement('testsuites')
        $writer.WriteAttributeString('name', 'vm-ui-pipeline')

        foreach ($run in $runList) {
            $tests = @($run.Tests)
            $failures = @($tests | Where-Object { $_.status -eq 'failed' }).Count
            $skipped = @($tests | Where-Object { $_.status -eq 'skipped' }).Count
            $writer.WriteStartElement('testsuite')
            $writer.WriteAttributeString('name', [string]$run.Vm)
            $writer.WriteAttributeString('hostname', [string]$run.Address)
            $writer.WriteAttributeString('tests', [string]$tests.Count)
            $writer.WriteAttributeString('failures', [string]$failures)
            $writer.WriteAttributeString('skipped', [string]$skipped)
            $writer.WriteAttributeString('time', (Format-JUnitSeconds $run.DurationMs))

            foreach ($test in $tests) {
                $writer.WriteStartElement('testcase')
                $writer.WriteAttributeString('classname', ('VmUiPipeline.' + [string]$run.Vm))
                $writer.WriteAttributeString('name', [string]$test.name)
                $writer.WriteAttributeString('time', (Format-JUnitSeconds $test.durationMs))

                if ($test.status -eq 'failed') {
                    $writer.WriteStartElement('failure')
                    $writer.WriteAttributeString('message', [string]$test.detail)
                    $writer.WriteString([string]$test.detail)
                    $writer.WriteEndElement()
                }
                elseif ($test.status -eq 'skipped') {
                    $writer.WriteStartElement('skipped')
                    $writer.WriteAttributeString('message', [string]$test.detail)
                    $writer.WriteEndElement()
                }

                $writer.WriteEndElement()
            }

            $writer.WriteEndElement()
        }

        $writer.WriteEndElement()
        $writer.WriteEndDocument()
    }
    finally {
        $writer.Dispose()
    }
}

function Write-VmUiPipelineMarkdownReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Summary,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.AppendLine('# VM UI Pipeline Report')
    [void]$builder.AppendLine()
    [void]$builder.AppendLine(('- Run: `{0}`' -f $Summary.RunId))
    [void]$builder.AppendLine(('- Started: {0}' -f $Summary.StartedUtc))
    [void]$builder.AppendLine(('- Duration: {0:N1}s' -f ($Summary.DurationMs / 1000.0)))
    [void]$builder.AppendLine()
    [void]$builder.AppendLine('| VM | Passed | Failed | Skipped | Duration | Status |')
    [void]$builder.AppendLine('| --- | ---: | ---: | ---: | ---: | --- |')

    foreach ($run in @($Summary.Vms)) {
        [void]$builder.AppendLine(('| {0} | {1} | {2} | {3} | {4:N1}s | {5} |' -f `
            $run.Vm, $run.Passed, $run.Failed, $run.Skipped, ($run.DurationMs / 1000.0), $run.Status))
    }

    $failedTests = @()
    foreach ($run in @($Summary.Vms)) {
        foreach ($test in @($run.Tests)) {
            if ($test.status -eq 'failed') {
                $failedTests += [pscustomobject]@{
                    Vm          = $run.Vm
                    Name        = $test.name
                    Detail      = $test.detail
                    Screenshots = @($test.screenshots)
                }
            }
        }
    }

    [void]$builder.AppendLine()
    if ($failedTests.Count -eq 0) {
        [void]$builder.AppendLine('All executed tests passed.')
    }
    else {
        [void]$builder.AppendLine('## Failures')
        [void]$builder.AppendLine()
        foreach ($failure in $failedTests) {
            [void]$builder.AppendLine(('### {0} / {1}' -f $failure.Vm, $failure.Name))
            [void]$builder.AppendLine()
            [void]$builder.AppendLine('```text')
            [void]$builder.AppendLine([string]$failure.Detail)
            [void]$builder.AppendLine('```')
            foreach ($screenshot in @($failure.Screenshots)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$screenshot)) {
                    [void]$builder.AppendLine(('- Screenshot: `{0}`' -f $screenshot))
                }
            }

            [void]$builder.AppendLine()
        }
    }

    Write-Utf8File -Path $Path -Content $builder.ToString()
}

function Write-VmUiPipelineConsoleReport {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Summary)

    Write-Host ""
    Write-Host ('{0,-12} {1,8} {2,8} {3,8} {4,10} {5}' -f 'VM', 'Passed', 'Failed', 'Skipped', 'Duration', 'Status')
    Write-Host ('{0,-12} {1,8} {2,8} {3,8} {4,10} {5}' -f '--', '------', '------', '-------', '--------', '------')
    foreach ($run in @($Summary.Vms)) {
        Write-Host ('{0,-12} {1,8} {2,8} {3,8} {4,9:N1}s {5}' -f `
            $run.Vm, $run.Passed, $run.Failed, $run.Skipped, ($run.DurationMs / 1000.0), $run.Status)
    }

    Write-Host ""
    Write-Host ('Total: {0} passed, {1} failed, {2} skipped' -f $Summary.Passed, $Summary.Failed, $Summary.Skipped)
}

function Write-VmRunSummary {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Run)

    foreach ($test in @($Run.Tests)) {
        $mark = switch ([string]$test.status) {
            'passed' { 'PASS' }
            'skipped' { 'SKIP' }
            default { 'FAIL' }
        }
        Write-Host ('    {0} {1} :: {2}' -f $mark, $test.name, $test.detail)
    }

    if ($Run.Failed -gt 0 -or $Run.Status -eq 'error' -or $Run.Status -eq 'timeout') {
        Write-Host ('    result: {0}' -f $Run.Status) -ForegroundColor Red
    }
    else {
        Write-Host ('    result: {0}' -f $Run.Status) -ForegroundColor Green
    }
}

function New-VmRunResult {
    param(
        [Parameter(Mandatory = $true)][object]$Vm,
        [Parameter(Mandatory = $true)][object]$Summary,
        [Parameter(Mandatory = $true)][string]$ResultsPath,
        [Parameter(Mandatory = $true)][string]$Status
    )

    $tests = @()
    foreach ($test in @($Summary.tests)) {
        $tests += [pscustomobject]@{
            name       = [string]$test.name
            status     = [string]$test.status
            durationMs = [double]$test.durationMs
            detail     = [string]$test.detail
        }
    }

    return [pscustomobject]@{
        Vm          = $Vm.Name
        Address     = $Vm.Address
        Status      = $Status
        Passed      = [int]$Summary.passed
        Failed      = [int]$Summary.failed
        Skipped     = [int]$Summary.skipped
        Total       = ([int]$Summary.passed + [int]$Summary.failed + [int]$Summary.skipped)
        DurationMs  = [double]$Summary.durationMs
        Tests       = $tests
        Error       = [string]$Summary.error
        ResultsPath = $ResultsPath
    }
}

function New-VmFailureRun {
    param(
        [Parameter(Mandatory = $true)][object]$Vm,
        [Parameter(Mandatory = $true)][string]$Error,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$ResultsPath
    )

    return [pscustomobject]@{
        Vm          = $Vm.Name
        Address     = $Vm.Address
        Status      = $Status
        Passed      = 0
        Failed      = 1
        Skipped     = 0
        Total       = 1
        DurationMs  = 0
        Tests       = @([pscustomobject]@{
            name       = 'pipeline'
            status     = 'failed'
            durationMs = 0
            detail     = $Error
        })
        Error       = $Error
        ResultsPath = $ResultsPath
    }
}

function Expand-VmArtifact {
    param(
        [Parameter(Mandatory = $true)][object]$Artifact,
        [Parameter(Mandatory = $true)][string]$WorkDirectory
    )

    if (-not $Artifact.IsZip) {
        return $Artifact.Path
    }

    $destination = Join-Path $WorkDirectory 'artifact'
    if (Test-Path -LiteralPath $destination) {
        Remove-Item -LiteralPath $destination -Recurse -Force
    }

    Expand-Archive -LiteralPath $Artifact.Path -DestinationPath $destination -Force
    return $destination
}

function Read-VmSummary {
    param([Parameter(Mandatory = $true)][string]$Path)

    $summary = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $summary) {
        throw "Result file is empty: $Path"
    }

    if ($null -eq $summary.tests) {
        throw "Result file has no tests array: $Path"
    }

    return $summary
}

function Wait-VmSummary {
    param(
        [Parameter(Mandatory = $true)][string]$SummaryPath,
        [Parameter(Mandatory = $true)][string]$ExitCodePath,
        [Parameter(Mandatory = $true)][int]$TimeoutMinutes
    )

    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $SummaryPath -PathType Leaf) {
            return [pscustomobject]@{ Completed = $true; TimedOut = $false; Detail = 'completed' }
        }

        if (Test-Path -LiteralPath $ExitCodePath -PathType Leaf) {
            Start-Sleep -Seconds 3
            if (Test-Path -LiteralPath $SummaryPath -PathType Leaf) {
                return [pscustomobject]@{ Completed = $true; TimedOut = $false; Detail = 'completed' }
            }

            $exitCode = (Get-Content -LiteralPath $ExitCodePath -Raw -Encoding UTF8).Trim()
            return [pscustomobject]@{
                Completed = $false
                TimedOut  = $false
                Detail    = "Runner exited with $exitCode without writing summary.json."
            }
        }

        Start-Sleep -Seconds 3
    }

    return [pscustomobject]@{
        Completed = $false
        TimedOut  = $true
        Detail    = "Timed out after $TimeoutMinutes minute(s) waiting for the guest result."
    }
}

function Restore-VmSnapshot {
    param(
        [Parameter(Mandatory = $true)][object]$Config,
        [Parameter(Mandatory = $true)][object]$Vm
    )

    if ([string]::IsNullOrWhiteSpace($Vm.Vmx) -or [string]::IsNullOrWhiteSpace($Vm.Snapshot)) {
        throw "VM '$($Vm.Name)' needs vmx and snapshot to use -RevertSnapshots."
    }

    if (-not (Test-Path -LiteralPath $Config.Launcher.VmrunPath -PathType Leaf)) {
        throw "vmrun was not found: $($Config.Launcher.VmrunPath)"
    }

    Write-Host "    reverting snapshot '$($Vm.Snapshot)'"
    & $Config.Launcher.VmrunPath -T ws stop $Vm.Vmx soft 2>$null | Out-Null
    & $Config.Launcher.VmrunPath -T ws revertToSnapshot $Vm.Vmx $Vm.Snapshot | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "vmrun revertToSnapshot failed with exit code $LASTEXITCODE."
    }

    & $Config.Launcher.VmrunPath -T ws start $Vm.Vmx nogui | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "vmrun start failed with exit code $LASTEXITCODE."
    }

    Write-Host "    waiting for SMB"
    if (-not (Wait-VmTcpPort -ComputerName $Vm.Address -Port 445 -TimeoutSeconds 300)) {
        throw "SMB did not become reachable on $($Vm.Address):445."
    }
}

function Get-VmPassword {
    param([Parameter(Mandatory = $true)][object]$Vm)

    $password = [Environment]::GetEnvironmentVariable($Vm.PasswordEnv, 'Process')
    if ([string]::IsNullOrEmpty($password)) {
        throw "Set the $($Vm.PasswordEnv) environment variable to the local administrator password for '$($Vm.Name)'."
    }

    return $password
}

function Connect-VmShare {
    param(
        [Parameter(Mandatory = $true)][object]$Vm,
        [Parameter(Mandatory = $true)][string]$Password
    )

    $share = '\\{0}\{1}' -f $Vm.Address, $Vm.ShareName
    if (Test-Path -LiteralPath $share) {
        return [pscustomobject]@{ Path = $share; Created = $false }
    }

    $output = & net use $share $Password ('/user:' + $Vm.User) 2>&1
    if ($LASTEXITCODE -ne 0 -and ($output -join ' ') -match '1219') {
        & net use $share /delete /y 2>&1 | Out-Null
        $output = & net use $share $Password ('/user:' + $Vm.User) 2>&1
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Could not map $share as $($Vm.User): $($output -join ' ')"
    }

    return [pscustomobject]@{ Path = $share; Created = $true }
}

function Disconnect-VmShare {
    param([Parameter(Mandatory = $true)][object]$Mapping)

    if (-not $Mapping.Created) {
        return
    }

    & net use $Mapping.Path /delete /y 2>&1 | Out-Null
}

function ConvertTo-VmUncPath {
    param(
        [Parameter(Mandatory = $true)][string]$GuestPath,
        [Parameter(Mandatory = $true)][object]$Vm
    )

    if ($GuestPath -match '^\\\\') {
        return $GuestPath
    }

    if ($GuestPath -match '^([A-Za-z]):\\(.*)$') {
        $drive = $Matches[1].ToLowerInvariant()
        $rest = $Matches[2]
        $share = if ($drive -eq 'c' -and $Vm.ShareName -ne 'c$') { $Vm.ShareName } else { $drive + '$' }
        return '\\{0}\{1}\{2}' -f $Vm.Address, $share, $rest
    }

    throw "Guest path must be absolute: $GuestPath"
}

function Invoke-Robocopy {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $arguments = @(
        $Source,
        $Destination,
        '/MIR',
        '/MT:8',
        '/NFL',
        '/NDL',
        '/NJH',
        '/NJS',
        '/NP',
        '/R:1',
        '/W:1'
    )

    & robocopy @arguments | Out-Null
    if ($LASTEXITCODE -ge 8) {
        throw "robocopy failed with exit code $LASTEXITCODE ($Source -> $Destination)."
    }
}

function Clear-VmDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (Test-Path -LiteralPath $Path) {
        Get-ChildItem -LiteralPath $Path -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function New-VmRunCommand {
    param(
        [Parameter(Mandatory = $true)][string]$RunnerPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$ResultsDirectory,
        [Parameter(Mandatory = $true)][string]$GuestRoot
    )

    $commandParts = @($RunnerPath) + $Arguments
    $quoted = @()
    foreach ($part in $commandParts) {
        $quoted += '"' + ([string]$part).Replace('"', '""') + '"'
    }

    $consoleLog = Join-Path $ResultsDirectory 'console.log'
    $exitCodeFile = Join-Path $ResultsDirectory 'exitcode.txt'
    $lines = @(
        '@echo off',
        ('cd /d "' + $GuestRoot + '"'),
        (($quoted -join ' ') + ' > "' + $consoleLog + '" 2>&1'),
        ('echo %ERRORLEVEL% > "' + $exitCodeFile + '"')
    )

    return (($lines -join "`r`n") + "`r`n")
}

function Write-Utf8File {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }

    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function Resolve-VmConfigPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$BaseDirectory,
        [Parameter(Mandatory = $true)][string]$Description
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "$Description is required."
    }

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $BaseDirectory $Path))
}

function Format-JUnitSeconds {
    param([object]$Milliseconds)

    if ($null -eq $Milliseconds) {
        return '0'
    }

    return ([math]::Round(([double]$Milliseconds) / 1000.0, 3)).ToString('0.###', [System.Globalization.CultureInfo]::InvariantCulture)
}

Export-ModuleMember -Function @(
    'Import-VmUiPipelineConfig',
    'Invoke-VmUiPipeline',
    'New-VmUiPipelineSummary',
    'ConvertTo-VmUiPipelineJUnit',
    'Write-VmUiPipelineMarkdownReport'
)
