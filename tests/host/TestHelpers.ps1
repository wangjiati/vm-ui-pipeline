# Copyright (c) Files Community and VmUiPipeline contributors.
# SPDX-License-Identifier: MPL-2.0

Import-Module (Join-Path $PSScriptRoot '..\..\host\VmUiPipeline\VmUiPipeline.psd1') -Force

function Assert-Equal {
    param($Actual, $Expected, [string]$Label)
    if ($Actual -ne $Expected) {
        throw "$Label`: expected '$Expected', got '$Actual'."
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Label)
    if (-not $Condition) {
        throw $Label
    }
}

function Assert-Throws {
    param([scriptblock]$Block, [string]$Label)
    $threw = $false
    try {
        & $Block
    }
    catch {
        $threw = $true
    }

    if (-not $threw) {
        throw "$Label`: expected an exception."
    }
}

function New-TestDirectory {
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ('vm-ui-pipeline-pester-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $path | Out-Null
    return $path
}

function Write-TestFile {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function New-TestConfig {
    param([string]$Directory)

    $appDirectory = Join-Path $Directory 'app'
    New-Item -ItemType Directory -Force -Path $appDirectory | Out-Null
    New-Item -ItemType File -Force -Path (Join-Path $appDirectory 'app.exe') | Out-Null
    New-Item -ItemType File -Force -Path (Join-Path $Directory 'runner.exe') | Out-Null
    New-Item -ItemType File -Force -Path (Join-Path $Directory 'suite.dll') | Out-Null
    New-Item -ItemType File -Force -Path (Join-Path $Directory 'sshc.exe') | Out-Null
    New-Item -ItemType File -Force -Path (Join-Path $Directory 'sshserver.exe') | Out-Null

    $config = [ordered]@{
        schemaVersion = 1
        artifact      = @{ path = 'app'; exe = 'app.exe' }
        runner        = @{ path = 'runner.exe' }
        suite         = @{ assembly = 'suite.dll'; type = 'Test.Suite' }
        launcher      = @{
            type         = 'win-simple-ssh'
            sshcPath     = 'sshc.exe'
            sshServerExe = 'sshserver.exe'
            port         = 22222
            ipWhitelist  = @('192.168.221.*')
        }
        vms           = @(@{ name = 'win11'; address = '192.168.221.130'; user = 'win11' })
        resultsDirectory = 'results'
    }

    $path = Join-Path $Directory 'pipeline.json'
    Write-TestFile -Path $path -Content ($config | ConvertTo-Json -Depth 8)
    return $path
}
