# Copyright (c) Files Community and VmUiPipeline contributors.
# SPDX-License-Identifier: MPL-2.0

<#
.SYNOPSIS
构建包含源码、Runner 与示例的发布 ZIP。
#>
param(
    [string]$Version = '0.1.3',
    [string]$OutputDirectory = 'artifacts\release'
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$output = [System.IO.Path]::GetFullPath((Join-Path $root $OutputDirectory))
$stage = Join-Path $output "vm-ui-pipeline-$Version"
$zip = Join-Path $output "vm-ui-pipeline-$Version.zip"

if (Test-Path -LiteralPath $stage) {
    Remove-Item -LiteralPath $stage -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $stage | Out-Null

Write-Host 'Publishing runner'
& dotnet publish (Join-Path $root 'src\VmUiPipeline.Runner\VmUiPipeline.Runner.csproj') `
    -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true -o (Join-Path $stage 'runner')
if ($LASTEXITCODE -ne 0) { throw "Runner publish failed with exit code $LASTEXITCODE." }

Write-Host 'Publishing sample app'
& dotnet publish (Join-Path $root 'samples\SampleApp\SampleApp.csproj') `
    -c Release -r win-x64 --self-contained true -o (Join-Path $stage 'samples\SampleApp')
if ($LASTEXITCODE -ne 0) { throw "Sample app publish failed with exit code $LASTEXITCODE." }

Write-Host 'Publishing sample suites'
foreach ($suite in @('SampleTests', 'DemoTests', 'FilesFilterTests')) {
    & dotnet publish (Join-Path $root "samples\$suite\$suite.csproj") `
        -c Release -o (Join-Path $stage "samples\$suite")
    if ($LASTEXITCODE -ne 0) { throw "$suite publish failed with exit code $LASTEXITCODE." }
}

Write-Host 'Copying host and docs'
Copy-Item -LiteralPath (Join-Path $root 'host') -Destination $stage -Recurse -Force
Copy-Item -LiteralPath (Join-Path $root 'schema') -Destination $stage -Recurse -Force
Copy-Item -LiteralPath (Join-Path $root 'docs') -Destination $stage -Recurse -Force
Copy-Item -LiteralPath (Join-Path $root 'demos') -Destination $stage -Recurse -Force
foreach ($file in @(
    'vm-ui-pipeline.ps1',
    'pipeline.example.json',
    'pipeline.sample.json',
    'README.md',
    'CHANGELOG.md',
    'CONTRIBUTING.md',
    'SECURITY.md',
    'CODE_OF_CONDUCT.md',
    'AGENTS.md',
    'LICENSE',
    'NOTICE')) {
    Copy-Item -LiteralPath (Join-Path $root $file) -Destination $stage -Force
}

$commit = 'unknown'
try {
    $commit = (& git -C $root rev-parse HEAD 2>$null).Trim()
}
catch {
    $commit = 'unknown'
}

$info = @(
    "VM UI Pipeline $Version",
    "Commit: $commit",
    "Built: $((Get-Date).ToUniversalTime().ToString('o'))",
    'WinSimpleSSH and ffmpeg are not included.'
)
[System.IO.File]::WriteAllText(
    (Join-Path $stage 'RELEASE-INFO.txt'),
    (($info -join "`r`n") + "`r`n"),
    (New-Object System.Text.UTF8Encoding($false)))

if (Test-Path -LiteralPath $zip) {
    Remove-Item -LiteralPath $zip -Force
}

Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -CompressionLevel Optimal
Write-Host ''
Write-Host "Release: $zip" -ForegroundColor Green
