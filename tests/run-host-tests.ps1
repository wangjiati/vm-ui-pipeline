# Copyright (c) Files Community and VmUiPipeline contributors.
# SPDX-License-Identifier: MPL-2.0

param(
    [string]$Path = (Join-Path $PSScriptRoot 'host')
)

$ErrorActionPreference = 'Stop'

$pester = Get-Module -ListAvailable Pester |
    Sort-Object Version -Descending |
    Select-Object -First 1

if ($null -eq $pester) {
    throw 'Pester is required. Install-Module Pester -Force -Scope CurrentUser'
}

Import-Module $pester.Path -Force

$result = Invoke-Pester -Path $Path -PassThru
if ($result.FailedCount -gt 0) {
    Write-Host "Pester failed: $($result.FailedCount) test(s)." -ForegroundColor Red
    exit 1
}

Write-Host "Pester passed: $($result.PassedCount) test(s)." -ForegroundColor Green
exit 0
