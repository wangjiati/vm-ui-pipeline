# Copyright (c) Files Community and VmUiPipeline contributors.
# SPDX-License-Identifier: MPL-2.0
#requires -Version 5.1

<#
.SYNOPSIS
运行 pipeline.json 描述的 VM UI 测试流水线。

.EXAMPLE
$env:VM_WIN11_PASSWORD = '<密码>'
.\vm-ui-pipeline.ps1 -Config .\pipeline.json -Vm win11

.EXAMPLE
.\vm-ui-pipeline.ps1 -Config .\pipeline.sample.json
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
