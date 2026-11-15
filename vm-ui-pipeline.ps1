# Copyright (c) Files Community and VmUiPipeline contributors.
# SPDX-License-Identifier: MPL-2.0
#requires -Version 5.1

<#
.SYNOPSIS
Runs a VM UI test pipeline described by pipeline.json.

.EXAMPLE
$env:VM_WIN11_PASSWORD = '<password>'
.\vm-ui-pipeline.ps1 -Config .\pipeline.json -Vm win11

.EXAMPLE
.\vm-ui-pipeline.ps1 -Config .\samples\local.pipeline.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Config,

    [string[]]$Vm,

    [switch]$RevertSnapshots,

    [string]$OutputDirectory,

    [switch]$KeepWorkDirectory
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'host\VmUiPipeline\VmUiPipeline.psd1') -Force

$summary = Invoke-VmUiPipeline -ConfigPath $Config -Vm $Vm -RevertSnapshots:$RevertSnapshots `
    -OutputDirectory $OutputDirectory -KeepWorkDirectory:$KeepWorkDirectory

exit $summary.ExitCode
