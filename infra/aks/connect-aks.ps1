<#
.SYNOPSIS
Connects to an AKS cluster created by this repo, including private mode fallback.

.DESCRIPTION
- Reads deployment outputs from .deploy/outputs.json (or explicit names passed as parameters).
- Tries direct local access first: az aks get-credentials + kubectl get nodes.
- For private clusters, can fall back to Bastion + jumpbox tunnel and run kubectl on the jumpbox.

.EXAMPLE
# Auto-detect from .deploy/outputs.json and connect
.\connect-aks.ps1

.EXAMPLE
# Force private fallback through Bastion/jumpbox
.\connect-aks.ps1 -UsePrivatePath

.EXAMPLE
# Explicit target values
.\connect-aks.ps1 -ResourceGroupName rg-demo -ClusterName aks-demo
#>
[CmdletBinding()]
param(
    [string]$SubscriptionId,
    [string]$ResourceGroupName,
    [string]$ClusterName,
    [string]$OutputsFile = "$PSScriptRoot\.deploy\outputs.json",
    [switch]$UsePrivatePath,
    [string]$BastionName,
    [string]$JumpboxName,
    [string]$JumpboxUser = 'azureuser',
    [string]$JumpboxSshKeyPath = "$PSScriptRoot\.deploy\jumpbox_id_rsa",
    [int]$LocalTunnelPort = 50022,
    [switch]$KeepTunnelOpen
)

$ErrorActionPreference = 'Stop'

function Write-Section($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Write-Ok($msg) { Write-Host "  [OK]  $msg" -ForegroundColor Green }
function Write-Warn2($msg) { Write-Host "  [!!]  $msg" -ForegroundColor Yellow }
function Write-Err($msg) { Write-Host "  [XX]  $msg" -ForegroundColor Red }

function Get-RequiredCommand {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $Name"
    }
}

function Get-OutputValue {
    param(
        [psobject]$Outputs,
        [string]$Name
    )
    if (-not $Outputs) { return '' }
    if (-not ($Outputs.PSObject.Properties.Name -contains $Name)) { return '' }
    $entry = $Outputs.$Name
    if (-not $entry) { return '' }
    if ($entry.PSObject.Properties.Name -contains 'value') {
        return [string]$entry.value
    }
    return ''
}

function Test-TcpPortOpen {
    param(
        [string]$ComputerName = '127.0.0.1',
        [int]$Port,
        [int]$TimeoutMs = 1000
    )

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($ComputerName, $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { return $false }
        $null = $client.EndConnect($iar)
        return $true
    }
    catch {
        return $false
    }
    finally {
        $client.Dispose()
    }
}

function Resolve-Target {
    param([psobject]$Outputs)

    $resolved = [ordered]@{}
    $resolved.ResourceGroupName = if ($ResourceGroupName) { $ResourceGroupName } else { Get-OutputValue -Outputs $Outputs -Name 'resourceGroupName' }
    $resolved.ClusterName = if ($ClusterName) { $ClusterName } else { Get-OutputValue -Outputs $Outputs -Name 'clusterName' }
    $resolved.ClusterFqdn = Get-OutputValue -Outputs $Outputs -Name 'clusterFqdn'
    $resolved.ClusterPrivateFqdn = Get-OutputValue -Outputs $Outputs -Name 'clusterPrivateFqdn'
    $resolved.BastionName = if ($BastionName) { $BastionName } else { Get-OutputValue -Outputs $Outputs -Name 'bastionName' }
    $resolved.JumpboxName = if ($JumpboxName) { $JumpboxName } else { Get-OutputValue -Outputs $Outputs -Name 'jumpboxName' }

    if (-not $resolved.ResourceGroupName) {
        throw 'Could not resolve resource group. Pass -ResourceGroupName or ensure outputs.json exists.'
    }
    if (-not $resolved.ClusterName) {
        throw 'Could not resolve cluster name. Pass -ClusterName or ensure outputs.json exists.'
    }

    return [pscustomobject]$resolved
}

function Set-SubscriptionContext {
    if ($SubscriptionId) {
        Write-Host "  Setting subscription: $SubscriptionId"
        az account set --subscription $SubscriptionId | Out-Null
        return
    }

    $current = az account show --query id -o tsv 2>$null
    if (-not $current) {
        throw 'No active Azure login/subscription. Run az login first, or pass -SubscriptionId.'
    }
    $script:SubscriptionId = [string]$current
}

function Invoke-DirectConnect {
    param(
        [string]$Rg,
        [string]$Cluster
    )

    Write-Section 'Direct cluster connect'
    Write-Host "  az aks get-credentials -g $Rg -n $Cluster --overwrite-existing"
    az aks get-credentials --resource-group $Rg --name $Cluster --overwrite-existing | Out-Null

    Write-Host '  kubectl get nodes --request-timeout=12s'
    & kubectl get nodes --request-timeout=12s
    if ($LASTEXITCODE -ne 0) {
        throw 'kubectl could not reach the cluster from this network path.'
    }

    Write-Ok 'Local kubeconfig updated and cluster reachable from this machine.'
}

function Invoke-PrivateJumpboxConnect {
    param(
        [string]$Rg,
        [string]$Cluster,
        [string]$Bastion,
        [string]$Jumpbox,
        [string]$KeyPath,
        [string]$JumpUser,
        [int]$Port,
        [bool]$LeaveTunnelOpen
    )

    Write-Section 'Private fallback via Bastion + jumpbox'
    Get-RequiredCommand -Name 'ssh'

    if (-not $Bastion) { throw 'Bastion name not found. Deploy Bastion or pass -BastionName.' }
    if (-not $Jumpbox) { throw 'Jumpbox name not found. Deploy jumpbox or pass -JumpboxName.' }
    if (-not (Test-Path $KeyPath)) {
        throw "Jumpbox key file not found: $KeyPath"
    }

    $vmId = az vm show -g $Rg -n $Jumpbox --query id -o tsv 2>$null
    if (-not $vmId) {
        throw "Could not resolve jumpbox VM id for '$Jumpbox' in resource group '$Rg'."
    }

    Write-Host "  Starting Bastion tunnel on 127.0.0.1:$Port"
    $tunnelArgs = @(
        'network', 'bastion', 'tunnel',
        '--name', $Bastion,
        '--resource-group', $Rg,
        '--target-resource-id', $vmId,
        '--resource-port', '22',
        '--port', "$Port"
    )

    $tunnelProc = Start-Process -FilePath 'az' -ArgumentList $tunnelArgs -PassThru -WindowStyle Hidden

    try {
        $ready = $false
        for ($i = 0; $i -lt 30; $i++) {
            Start-Sleep -Milliseconds 500
            if (Test-TcpPortOpen -Port $Port) {
                $ready = $true
                break
            }
            if ($tunnelProc.HasExited) {
                throw 'Bastion tunnel process exited before becoming ready.'
            }
        }
        if (-not $ready) {
            throw 'Timed out waiting for Bastion tunnel port to open.'
        }

        $remote = @(
            'set -e',
            'az login --identity --allow-no-subscriptions >/dev/null 2>&1 || true',
            "az account set --subscription '$SubscriptionId'",
            "az aks get-credentials --resource-group '$Rg' --name '$Cluster' --overwrite-existing",
            'kubectl get nodes -o wide'
        ) -join '; '

        $sshArgs = @(
            '-o', 'StrictHostKeyChecking=accept-new',
            '-i', $KeyPath,
            '-p', "$Port",
            "$JumpUser@127.0.0.1",
            $remote
        )

        Write-Host '  Running AKS connect/check from jumpbox...'
        & ssh @sshArgs
        if ($LASTEXITCODE -ne 0) {
            throw 'SSH/jumpbox path failed. Validate Bastion tunnel, key path, jumpbox identity login, and AKS RBAC.'
        }

        Write-Ok 'Connected via jumpbox path. kubectl get nodes succeeded on jumpbox.'

        if ($LeaveTunnelOpen) {
            Write-Warn2 "Tunnel left open on 127.0.0.1:$Port (process id $($tunnelProc.Id))."
            Write-Host "  To stop it: Stop-Process -Id $($tunnelProc.Id)"
            $script:KeepTunnelProcess = $true
        }
    }
    finally {
        if (-not $script:KeepTunnelProcess -and $tunnelProc -and -not $tunnelProc.HasExited) {
            Stop-Process -Id $tunnelProc.Id -Force
            Write-Host '  Bastion tunnel stopped.'
        }
    }
}

try {
    Get-RequiredCommand -Name 'az'
    Get-RequiredCommand -Name 'kubectl'

    Set-SubscriptionContext

    $outputs = $null
    if (Test-Path $OutputsFile) {
        $outputs = Get-Content -Raw $OutputsFile | ConvertFrom-Json
    }

    $target = Resolve-Target -Outputs $outputs

    $isPrivate = $false
    if ($target.ClusterPrivateFqdn) { $isPrivate = $true }
    elseif ($target.ClusterFqdn -match '\.privatelink\.') { $isPrivate = $true }

    Write-Section 'Target'
    Write-Host "  Subscription : $SubscriptionId"
    Write-Host "  ResourceGroup: $($target.ResourceGroupName)"
    Write-Host "  Cluster      : $($target.ClusterName)"
    Write-Host "  PrivateMode  : $isPrivate"

    if (-not $UsePrivatePath) {
        try {
            Invoke-DirectConnect -Rg $target.ResourceGroupName -Cluster $target.ClusterName
            exit 0
        }
        catch {
            if (-not $isPrivate) {
                throw
            }
            Write-Warn2 $_.Exception.Message
            Write-Warn2 'Cluster appears private. Trying Bastion + jumpbox fallback.'
        }
    }

    Invoke-PrivateJumpboxConnect `
        -Rg $target.ResourceGroupName `
        -Cluster $target.ClusterName `
        -Bastion $target.BastionName `
        -Jumpbox $target.JumpboxName `
        -KeyPath $JumpboxSshKeyPath `
        -JumpUser $JumpboxUser `
        -Port $LocalTunnelPort `
        -LeaveTunnelOpen:$KeepTunnelOpen

    Write-Section 'DONE'
}
catch {
    Write-Err $_.Exception.Message
    Write-Host ''
    Write-Host 'Try:' -ForegroundColor Yellow
    Write-Host '  1) Verify az login and subscription.' -ForegroundColor Yellow
    Write-Host '  2) For private mode, deploy Bastion + jumpbox and ensure .deploy/jumpbox_id_rsa exists.' -ForegroundColor Yellow
    Write-Host '  3) Pass explicit values: -ResourceGroupName, -ClusterName, -BastionName, -JumpboxName.' -ForegroundColor Yellow
    exit 1
}
