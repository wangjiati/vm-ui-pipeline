# Copyright (c) Files Community and VmUiPipeline contributors.
# SPDX-License-Identifier: MPL-2.0
#requires -Version 5.1

<#
.SYNOPSIS
在虚拟机里运行截图与录屏演示。

.DESCRIPTION
构建 Runner、示例应用与演示套件，然后调用 VM UI Pipeline。
所有截图、录屏和 UI 操作都在客户机内完成，宿主机只负责构建与投放。

.EXAMPLE
$env:VM_WIN11_PASSWORD = '<客户机密码>'
.\demos\run-demo.ps1 -Mode both
#>
param(
    [ValidateSet('screenshot', 'recording', 'both')]
    [string]$Mode = 'both',

    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$demoRoot = Join-Path $root 'artifacts\demo'
$demosRoot = Join-Path $root 'artifacts\demos'

if ([string]::IsNullOrWhiteSpace($env:VM_WIN11_PASSWORD)) {
    throw '请先设置 VM_WIN11_PASSWORD（win11 客户机本地管理员密码）。'
}

$sshc = Join-Path $root 'external\WinSimpleSSH\src\SSHClient\bin\Release\net452\SSHC.exe'
if (-not (Test-Path -LiteralPath $sshc)) {
    throw '缺少 WinSimpleSSH。请先运行 .\scripts\Get-WinSimpleSsh.ps1。'
}

function Invoke-DotnetPublish {
    param([string[]]$Arguments)

    & dotnet @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet 命令失败，退出码 $LASTEXITCODE。"
    }
}

if (-not $SkipBuild) {
    Write-Host '构建 Runner…'
    Invoke-DotnetPublish @(
        'publish', (Join-Path $root 'src\VmUiPipeline.Runner\VmUiPipeline.Runner.csproj'),
        '-c', 'Release', '-r', 'win-x64', '--self-contained', 'true',
        '-p:PublishSingleFile=true', '-p:IncludeNativeLibrariesForSelfExtract=true',
        '-p:NuGetAudit=false', '-o', (Join-Path $demoRoot 'publish'),
        '-v:quiet', '-clp:ErrorsOnly'
    )

    Write-Host '构建示例应用…'
    Invoke-DotnetPublish @(
        'publish', (Join-Path $root 'samples\SampleApp\SampleApp.csproj'),
        '-c', 'Release', '-r', 'win-x64', '--self-contained', 'true',
        '-p:NuGetAudit=false', '-o', (Join-Path $demoRoot 'app'),
        '-v:quiet', '-clp:ErrorsOnly'
    )

    Write-Host '构建演示套件…'
    Invoke-DotnetPublish @(
        'publish', (Join-Path $root 'samples\DemoTests\DemoTests.csproj'),
        '-c', 'Release', '-p:NuGetAudit=false', '-o', (Join-Path $demoRoot 'suite'),
        '-v:quiet', '-clp:ErrorsOnly'
    )
}

if ($Mode -eq 'recording' -or $Mode -eq 'both') {
    $ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($null -eq $ffmpeg) {
        throw '录屏演示需要 ffmpeg。请安装 ffmpeg，或只运行 -Mode screenshot。'
    }

    $ffmpegDirectory = Join-Path $demoRoot 'ffmpeg'
    New-Item -ItemType Directory -Force -Path $ffmpegDirectory | Out-Null
    Copy-Item -LiteralPath $ffmpeg.Source -Destination (Join-Path $ffmpegDirectory 'ffmpeg.exe') -Force
    Write-Host "ffmpeg：$($ffmpeg.Source)"
}

Import-Module (Join-Path $root 'host\VmUiPipeline\VmUiPipeline.psd1') -Force

$modes = @()
if ($Mode -eq 'screenshot' -or $Mode -eq 'both') {
    $modes += @{ Name = '截图'; Config = Join-Path $PSScriptRoot 'screenshot.pipeline.json' }
}

if ($Mode -eq 'recording' -or $Mode -eq 'both') {
    $modes += @{ Name = '录屏'; Config = Join-Path $PSScriptRoot 'recording.pipeline.json' }
}

$failed = $false
foreach ($item in $modes) {
    Write-Host ''
    Write-Host ("=== {0}演示 ===" -f $item.Name) -ForegroundColor Cyan
    $summary = Invoke-VmUiPipeline -ConfigPath $item.Config
    foreach ($run in @($summary.Vms)) {
        Write-Host ("{0}：通过 {1}，失败 {2}，跳过 {3}" -f $run.Vm, $run.Passed, $run.Failed, $run.Skipped)
        Write-Host ("结果目录：{0}" -f $run.ResultsPath)
        $screenshots = Join-Path $run.ResultsPath 'screenshots'
        if (Test-Path -LiteralPath $screenshots) {
            Get-ChildItem -LiteralPath $screenshots -Filter *.png | ForEach-Object {
                Write-Host ("截图：{0}" -f $_.FullName)
            }
        }

        $video = Join-Path $run.ResultsPath 'session.mp4'
        if (Test-Path -LiteralPath $video) {
            Write-Host ("录像：{0}" -f $video)
        }
    }

    if ($summary.ExitCode -ne 0) {
        $failed = $true
    }
}

if ($failed) {
    Write-Host '演示未全部通过。' -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host '演示完成。' -ForegroundColor Green
Write-Host ("所有结果位于：{0}" -f $demosRoot)
exit 0
