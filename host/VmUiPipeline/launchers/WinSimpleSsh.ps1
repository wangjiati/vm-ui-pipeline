# Copyright (c) Files Community and VmUiPipeline contributors.
# SPDX-License-Identifier: MPL-2.0

<#
WinSimpleSSH 启动适配器。

依赖契约：WinSimpleSSH 只用于在客户机已登录交互式控制台会话中启动 run.cmd。
其服务以 LocalSystem 运行，调用 WTSQueryUserToken + CreateProcessAsUser，
并设置 lpDesktop = "WinSta0\Default"。流水线中其他部分都不依赖它：文件走 SMB，
结果由 VmUiPipeline.Runner 写成 JSON，通过/失败由 Runner 判定。
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

    # SSHC 会把“认证成功”写到 stderr；在 Stop 模式下 PowerShell 5.1 会把它
    # 当成终止错误。这里局部放宽，避免把成功提示误判为失败。
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $Launcher.SshcPath @arguments 2>$null | Out-Null
        return $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previous
    }
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

    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $Launcher.SshcPath @arguments 2>$null | Out-Null
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previous
    }

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
