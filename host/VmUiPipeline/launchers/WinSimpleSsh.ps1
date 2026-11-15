# Copyright (c) Files Community and VmUiPipeline contributors.
# SPDX-License-Identifier: MPL-2.0

<#
WinSimpleSSH launcher adapter.

Dependency contract: WinSimpleSSH is used only to start the run.cmd in the guest's
logged-on interactive console session. Its service runs as LocalSystem and calls
WTSQueryUserToken + CreateProcessAsUser with lpDesktop = "WinSta0\Default".
Nothing else in the pipeline depends on it: files move over SMB, results are JSON
written by VmUiPipeline.Runner, and pass/fail is decided by the runner.
#>

function Initialize-VmSshService {
    param(
        [Parameter(Mandatory = $true)][object]$Vm,
        [Parameter(Mandatory = $true)][object]$Launcher,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$UncGuestRoot,
        [Parameter(Mandatory = $true)][string]$GuestRoot
    )

    if (Test-VmTcpPort -ComputerName $Vm.Address -Port $Launcher.Port) {
        return
    }

    Write-Host "    installing WinSimpleSSH service on $($Vm.Address):$($Launcher.Port)"
    $sshUnc = Join-Path $UncGuestRoot 'ssh'
    New-Item -ItemType Directory -Force -Path $sshUnc | Out-Null
    Copy-Item -LiteralPath $Launcher.SshServerExe -Destination (Join-Path $sshUnc 'SSHServer.exe') -Force

    $serverJson = ConvertTo-Json -InputObject ([pscustomobject]@{
        port        = [int]$Launcher.Port
        ipWhitelist = @($Launcher.IpWhitelist)
        users       = @([pscustomobject]@{
            username = $Vm.User
            password = $Password
        })
    }) -Depth 6
    Write-Utf8File -Path (Join-Path $sshUnc 'server.json') -Content $serverJson

    $secure = ConvertTo-SecureString $Password -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($Vm.User, $secure)
    $serverGuestPath = Join-Path (Join-Path $GuestRoot 'ssh') 'SSHServer.exe'
    $command = 'cmd.exe /c ""{0}" --install"' -f $serverGuestPath

    Invoke-WmiMethod -ComputerName $Vm.Address -Credential $credential -Class Win32_Process `
        -Name Create -ArgumentList $command -ErrorAction Stop | Out-Null

    if (-not (Wait-VmTcpPort -ComputerName $Vm.Address -Port $Launcher.Port -TimeoutSeconds 90)) {
        throw "WinSimpleSSH service did not open port $($Launcher.Port) on $($Vm.Address)."
    }
}

function Invoke-VmSshExec {
    param(
        [Parameter(Mandatory = $true)][object]$Vm,
        [Parameter(Mandatory = $true)][object]$Launcher,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$Command
    )

    $env:SSHC_PASSWORD = $Password
    $arguments = @(
        'exec',
        $Vm.Address,
        '-u', $Vm.User,
        '--port', [string]$Launcher.Port,
        '--json',
        $Command
    )

    & $Launcher.SshcPath @arguments 2>$null | Out-Null
    return $LASTEXITCODE
}

function Start-VmSshProcess {
    param(
        [Parameter(Mandatory = $true)][object]$Vm,
        [Parameter(Mandatory = $true)][object]$Launcher,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$Program
    )

    $env:SSHC_PASSWORD = $Password
    $arguments = @(
        'start',
        $Vm.Address,
        '-u', $Vm.User,
        '--port', [string]$Launcher.Port,
        $Program
    )

    & $Launcher.SshcPath @arguments 2>$null | Out-Null
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "SSHC start failed with exit code $exitCode for '$Program'."
    }
}

function Stop-VmSshProcesses {
    param(
        [Parameter(Mandatory = $true)][object]$Vm,
        [Parameter(Mandatory = $true)][object]$Launcher,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string[]]$ProcessNames
    )

    $commands = @()
    foreach ($name in $ProcessNames) {
        if ([string]::IsNullOrWhiteSpace($name)) {
            continue
        }

        $commands += ('taskkill /IM {0}.exe /F /T' -f $name)
    }

    if ($commands.Count -eq 0) {
        return
    }

    $command = ($commands -join ' & ') + ' > nul 2>&1'
    Invoke-VmSshExec -Vm $Vm -Launcher $Launcher -Password $Password -Command $command | Out-Null
}

function Test-VmTcpPort {
    param(
        [Parameter(Mandatory = $true)][string]$ComputerName,
        [Parameter(Mandatory = $true)][int]$Port,
        [int]$TimeoutMilliseconds = 1500
    )

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $result = $client.BeginConnect($ComputerName, $Port, $null, $null)
        if (-not $result.AsyncWaitHandle.WaitOne($TimeoutMilliseconds)) {
            return $false
        }

        $client.EndConnect($result)
        return $true
    }
    catch {
        return $false
    }
    finally {
        $client.Close()
    }
}

function Wait-VmTcpPort {
    param(
        [Parameter(Mandatory = $true)][string]$ComputerName,
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-VmTcpPort -ComputerName $ComputerName -Port $Port) {
            return $true
        }

        Start-Sleep -Seconds 3
    }

    return $false
}
