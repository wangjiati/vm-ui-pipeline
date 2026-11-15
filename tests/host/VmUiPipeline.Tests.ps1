# Copyright (c) Files Community and VmUiPipeline contributors.
# SPDX-License-Identifier: MPL-2.0

Describe 'Import-VmUiPipelineConfig' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    }

    It 'resolves relative paths and applies defaults' {
        $directory = New-TestDirectory
        try {
            $path = New-TestConfig -Directory $directory
            $config = Import-VmUiPipelineConfig -Path $path

            Assert-Equal $config.GuestRoot 'C:\VmUiPipeline' 'GuestRoot'
            Assert-Equal $config.TimeoutMinutes 10 'TimeoutMinutes'
            Assert-Equal $config.StartupTimeoutSeconds 60 'StartupTimeoutSeconds'
            Assert-Equal $config.Artifact.Path (Join-Path $directory 'app') 'Artifact.Path'
            Assert-Equal $config.Runner.Path (Join-Path $directory 'runner.exe') 'Runner.Path'
            Assert-Equal $config.Suite.Assembly (Join-Path $directory 'suite.dll') 'Suite.Assembly'
            Assert-Equal $config.ResultRoot (Join-Path $directory 'results') 'ResultRoot'
            Assert-Equal $config.Launcher.Type 'win-simple-ssh' 'Launcher.Type'
            Assert-Equal $config.Vms.Count 1 'VM count'
            Assert-Equal $config.Vms[0].Address '192.168.221.130' 'VM address'
            Assert-Equal $config.Vms[0].PasswordEnv 'VM_WIN11_PASSWORD' 'PasswordEnv default'
            Assert-Equal $config.Recording.Enabled $false 'Recording disabled by default'
            Assert-Equal $config.Recording.Fps 10 'Recording fps default'
        }
        finally {
            Remove-Item -LiteralPath $directory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects a missing artifact path' {
        $directory = New-TestDirectory
        try {
            $path = New-TestConfig -Directory $directory
            $badPath = Join-Path $directory 'missing.json'
            $object = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            $object.artifact.path = 'does-not-exist'
            Write-TestFile -Path $badPath -Content ($object | ConvertTo-Json -Depth 8)
            Assert-Throws { Import-VmUiPipelineConfig -Path $badPath } 'missing artifact'
        }
        finally {
            Remove-Item -LiteralPath $directory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects host-side UI testing' {
        $directory = New-TestDirectory
        try {
            $path = New-TestConfig -Directory $directory
            $badPath = Join-Path $directory 'local.json'
            $object = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            $object.launcher.type = 'local'
            Write-TestFile -Path $badPath -Content ($object | ConvertTo-Json -Depth 8)
            Assert-Throws { Import-VmUiPipelineConfig -Path $badPath } 'local launcher'
        }
        finally {
            Remove-Item -LiteralPath $directory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'New-VmUiPipelineSummary' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    }

    It 'aggregates counts and fails when a test failed' {
        $runs = @(
            [pscustomobject]@{
                Vm = 'win10'; Address = '10.0.0.1'; Status = 'completed'
                Passed = 3; Failed = 0; Skipped = 0; Total = 3; DurationMs = 1000
                Tests = @(); Error = $null; ResultsPath = 'x'
            },
            [pscustomobject]@{
                Vm = 'win11'; Address = '10.0.0.2'; Status = 'completed'
                Passed = 2; Failed = 1; Skipped = 1; Total = 4; DurationMs = 2000
                Tests = @(); Error = $null; ResultsPath = 'y'
            }
        )

        $summary = New-VmUiPipelineSummary -Runs $runs -RunId 'run-1' `
            -StartedUtc (Get-Date).AddSeconds(-3) -FinishedUtc (Get-Date)

        Assert-Equal $summary.Passed 5 'Passed'
        Assert-Equal $summary.Failed 1 'Failed'
        Assert-Equal $summary.Skipped 1 'Skipped'
        Assert-Equal $summary.Total 7 'Total'
        Assert-Equal $summary.ExitCode 1 'ExitCode'
    }

    It 'returns exit code 3 when a VM timed out' {
        $runs = @(
            [pscustomobject]@{
                Vm = 'win11'; Address = '10.0.0.2'; Status = 'timeout'
                Passed = 0; Failed = 1; Skipped = 0; Total = 1; DurationMs = 0
                Tests = @(); Error = 'timeout'; ResultsPath = 'y'
            }
        )

        $summary = New-VmUiPipelineSummary -Runs $runs -RunId 'run-2' `
            -StartedUtc (Get-Date).AddSeconds(-1) -FinishedUtc (Get-Date)

        Assert-Equal $summary.ExitCode 3 'ExitCode'
    }
}

Describe 'ConvertTo-VmUiPipelineJUnit' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    }

    It 'writes testsuites with failures and skips' {
        $directory = New-TestDirectory
        try {
            $runs = @(
                [pscustomobject]@{
                    Vm = 'win11'; Address = '10.0.0.2'; Status = 'completed'
                    Passed = 1; Failed = 1; Skipped = 1; Total = 3; DurationMs = 1500
                    Tests = @(
                        [pscustomobject]@{ name = 'launch'; status = 'passed'; durationMs = 12; detail = 'ok' },
                        [pscustomobject]@{ name = 'filter'; status = 'failed'; durationMs = 30; detail = 'expected 2' },
                        [pscustomobject]@{ name = 'screenshot'; status = 'skipped'; durationMs = 0; detail = 'out of scope' }
                    )
                    Error = $null; ResultsPath = 'x'
                }
            )

            $path = Join-Path $directory 'junit.xml'
            ConvertTo-VmUiPipelineJUnit -Runs $runs -Path $path

            [xml]$xml = Get-Content -LiteralPath $path -Raw -Encoding UTF8
            Assert-Equal $xml.testsuites.testsuite.name 'win11' 'suite name'
            Assert-Equal $xml.testsuites.testsuite.tests '3' 'tests'
            Assert-Equal $xml.testsuites.testsuite.failures '1' 'failures'
            Assert-Equal $xml.testsuites.testsuite.skipped '1' 'skipped'
            Assert-Equal $xml.testsuites.testsuite.testcase.Count 3 'testcase count'
            Assert-Equal $xml.testsuites.testsuite.testcase[1].failure.message 'expected 2' 'failure message'
        }
        finally {
            Remove-Item -LiteralPath $directory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
