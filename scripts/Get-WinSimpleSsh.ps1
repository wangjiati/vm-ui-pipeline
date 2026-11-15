# Copyright (c) Files Community and VmUiPipeline contributors.
# SPDX-License-Identifier: MPL-2.0

<#
.SYNOPSIS
Clones and builds the pinned WinSimpleSSH dependency.
#>
param(
    [string]$Destination = (Join-Path $PSScriptRoot '..\external\WinSimpleSSH'),
    [string]$Commit = '8f40f29c76f81e2c50fcd3fa49a26ab7ba0f8cfe'
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'git is required.'
}

$destination = [System.IO.Path]::GetFullPath($Destination)
if (Test-Path -LiteralPath $destination) {
    Write-Host "Updating $destination"
    & git -C $destination fetch --all --tags
    if ($LASTEXITCODE -ne 0) { throw 'git fetch failed.' }
}
else {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    & git clone https://github.com/wangjiati/WinSimpleSSH.git $destination
    if ($LASTEXITCODE -ne 0) { throw 'git clone failed.' }
}

& git -C $destination checkout $Commit
if ($LASTEXITCODE -ne 0) { throw "git checkout $Commit failed." }

$msbuildExe = $null
$msbuildCommand = Get-Command msbuild -ErrorAction SilentlyContinue
if ($null -ne $msbuildCommand) {
    $msbuildExe = $msbuildCommand.Source
}
else {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $vswhere) {
        $msbuildExe = & $vswhere -latest -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\MSBuild.exe' |
            Select-Object -First 1
    }
}

if ([string]::IsNullOrWhiteSpace($msbuildExe)) {
    throw @'
MSBuild was not found. Install Visual Studio with the .NET desktop build tools, or
build WinSimpleSSH.sln in Visual Studio and set launcher.sshcPath and
launcher.sshServerExe manually.
'@
}

$solution = Join-Path $destination 'WinSimpleSSH.sln'
Write-Host "Building $solution"
& $msbuildExe $solution /restore /p:Configuration=Release /v:minimal
if ($LASTEXITCODE -ne 0) { throw "MSBuild failed with exit code $LASTEXITCODE." }

$client = Join-Path $destination 'src\SSHClient\bin\Release\net452\SSHC.exe'
$server = Join-Path $destination 'src\SSHServer\bin\Release\net452\SSHServer.exe'
foreach ($path in @($client, $server)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Expected build output was not found: $path"
    }
}

Write-Host ''
Write-Host 'WinSimpleSSH build output:' -ForegroundColor Green
Write-Host "  SSHC.exe     : $client"
Write-Host "  SSHServer.exe: $server"
