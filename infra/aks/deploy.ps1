<#
.SYNOPSIS
    User-friendly, progressive deploy for an AKS Automatic cluster (Bicep).

.DESCRIPTION
    Stages:
      0  Preflight       Checks az login, subscription, CLI/extension/feature
      1  Plan            Runs what-if and prints the diff
      2  Deploy          Submits main.bicep at subscription scope
      3  Smoke           az aks get-credentials + kubectl get nodes

    Each stage is restartable.  Use -Stage <name> to run one stage at a time.

.EXAMPLE
    # Fully automated, public managed cluster
    .\deploy.ps1 -SubscriptionId <sub> -Location westus3 -AutoName

.EXAMPLE
    # Private cluster, interactive name confirmation, custom workload prefix
    .\deploy.ps1 -SubscriptionId <sub> -Location eastus2 -Mode automaticPrivate `
        -WorkloadName payments -Interactive

.EXAMPLE
    # Resume from where a previous run failed
    .\deploy.ps1 -Resume
#>
[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Colored CLI output for end-users')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Parameters consumed at script scope by inner functions')]
param(
    [string]$SubscriptionId,
    [string]$Location = 'westus3',
    [ValidateSet('automaticManaged','automaticPrivate')]
    [string]$Mode = 'automaticManaged',
    [string]$WorkloadName = 'aks',
    [string]$Environment = 'dev',
    [string]$ParametersFile = "$PSScriptRoot\main.bicepparam",
    [switch]$AutoName,
    [switch]$Interactive,
    [switch]$Resume,
    [ValidateSet('Preflight','Plan','Deploy','Smoke','All')]
    [string]$Stage = 'All',
    [switch]$SkipWhatIf,
    [string]$DeploymentName,
    [hashtable]$Overrides = @{}
)

$ErrorActionPreference = 'Stop'
$state = Join-Path $PSScriptRoot '.deploy'
New-Item -ItemType Directory -Force -Path $state | Out-Null
$stateFile = Join-Path $state 'state.json'
$outputsFile = Join-Path $state 'outputs.json'

function Write-Section($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Write-Ok($msg)      { Write-Host "  [OK]  $msg" -ForegroundColor Green }
function Write-Warn2($msg)   { Write-Host "  [!!]  $msg" -ForegroundColor Yellow }
function Write-Err($msg)     { Write-Host "  [XX]  $msg" -ForegroundColor Red }

function Get-DeployState { if (Test-Path $stateFile) { Get-Content $stateFile -Raw | ConvertFrom-Json } else { [pscustomobject]@{} } }
function Save-DeployState($s) { $s | ConvertTo-Json -Depth 10 | Set-Content -Path $stateFile -Encoding UTF8 }

function Confirm-Or-Default($prompt, $default) {
    if (-not $Interactive) { return $default }
    $ans = Read-Host "$prompt [$default]"
    if ([string]::IsNullOrWhiteSpace($ans)) { return $default } else { return $ans }
}

function New-AutoName {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure name generator, no side effects')]
    [CmdletBinding()]
    param($workload, $env, $loc)
    $shortLoc = ($loc -replace '[^a-z0-9]','').Substring(0, [Math]::Min(6, $loc.Length))
    $suffix = -join ((1..4) | ForEach-Object { [char[]](48..57+97..122) | Get-Random })
    $base = "$workload-$env-$shortLoc-$suffix".ToLower()
    $cluster = "aks-$base"
    @{
        resourceGroupName        = "rg-$base"
        clusterName              = $cluster
        nodeResourceGroupName    = "rg-$base-nodes"
        dnsPrefix                = $cluster
        controlPlaneIdentityName = "id-$base-cp"
        kubeletIdentityName      = "id-$base-kubelet"
        logAnalyticsWorkspaceName = "log-$base"
        azureMonitorWorkspaceName = "amw-$base"
        managedGrafanaName       = "amg-$base"
        acrName                  = ("acr" + ($base -replace '[^a-z0-9]','')).Substring(0, [Math]::Min(50,("acr"+($base -replace '[^a-z0-9]','')).Length))
        vnetName                 = "vnet-$base"
        aksSubnetName            = 'snet-aks'
        privateEndpointSubnetName = 'snet-pe'
        aksNsgName               = "nsg-aks-$base"
        privateDnsZoneName       = "privatelink.$loc.azmk8s.io"
        privateDnsVnetLinkName   = "link-$base"
    }
}

# ============================================================================
#  STAGE: Preflight
# ============================================================================
function Invoke-Preflight {
    Write-Section "Stage 1/4  Preflight"

    Write-Host "  Checking Azure CLI..."
    $cli = az version --output json 2>$null | ConvertFrom-Json
    if (-not $cli) { throw "Azure CLI not found. Install: https://aka.ms/azure-cli" }
    $cliVer = [Version]$cli.'azure-cli'
    if ($cliVer -lt [Version]'2.77.0') { throw "Azure CLI $cliVer < 2.77.0 required for AKS Automatic + managed system node pools." }
    Write-Ok "Azure CLI $cliVer"

    Write-Host "  Checking aks-preview extension..."
    $ext = az extension list --query "[?name=='aks-preview']" --output json | ConvertFrom-Json
    if (-not $ext) {
        Write-Warn2 "aks-preview not installed. Installing..."
        az extension add --name aks-preview --only-show-errors | Out-Null
    } else {
        az extension update --name aks-preview --only-show-errors 2>$null | Out-Null
    }
    Write-Ok "aks-preview ready"

    Write-Host "  Checking login..."
    $acct = az account show --output json 2>$null | ConvertFrom-Json
    if (-not $acct) { throw "Not logged in. Run: az login" }

    if ($SubscriptionId) {
        if ($acct.id -ne $SubscriptionId) {
            az account set --subscription $SubscriptionId | Out-Null
            $acct = az account show --output json | ConvertFrom-Json
        }
    }
    Write-Ok "Subscription: $($acct.name)  ($($acct.id))"
    Write-Ok "Tenant:       $($acct.tenantId)"

    Write-Host "  Registering providers (idempotent)..."
    $providers = @(
        'Microsoft.ContainerService','Microsoft.Network','Microsoft.ManagedIdentity',
        'Microsoft.OperationalInsights','Microsoft.OperationsManagement','Microsoft.Insights',
        'Microsoft.Monitor','Microsoft.Dashboard','Microsoft.ContainerRegistry','Microsoft.Authorization'
    )
    # az emits "Registering is still on-going" warnings to stderr; in PS 7.4+ that can terminate.
    $prevPref = $PSNativeCommandUseErrorActionPreference
    try {
        $PSNativeCommandUseErrorActionPreference = $false
        foreach ($p in $providers) { az provider register --namespace $p --consent-to-permissions 2>&1 | Out-Null }
    } finally { $PSNativeCommandUseErrorActionPreference = $prevPref }
    Write-Ok "Providers registered (async)"

    if ($Mode -eq 'automaticManaged') {
        Write-Host "  Checking preview feature AKS-AutomaticHostedSystemProfilePreview..."
        $feat = az feature show --namespace Microsoft.ContainerService --name AKS-AutomaticHostedSystemProfilePreview --output json | ConvertFrom-Json
        if ($feat.properties.state -ne 'Registered') {
            Write-Warn2 "Feature not registered. Registering now (this can take several minutes)..."
            az feature register --namespace Microsoft.ContainerService --name AKS-AutomaticHostedSystemProfilePreview | Out-Null
            do {
                Start-Sleep -Seconds 20
                $feat = az feature show --namespace Microsoft.ContainerService --name AKS-AutomaticHostedSystemProfilePreview --output json | ConvertFrom-Json
                Write-Host "    state: $($feat.properties.state)"
            } while ($feat.properties.state -ne 'Registered')
            az provider register --namespace Microsoft.ContainerService | Out-Null
        }
        Write-Ok "Feature registered"
    }

    @{ subscriptionId = $acct.id; tenantId = $acct.tenantId }
}

# ============================================================================
#  STAGE: Plan
# ============================================================================
function Invoke-Plan {
    param($paramOverrides)
    Write-Section "Stage 2/4  Plan"
    if ($SkipWhatIf) { Write-Warn2 "Skipping what-if (per -SkipWhatIf)"; return }

    $azArgs = @(
        'deployment','sub','what-if',
        '--location', $Location,
        '--name',     $DeploymentName,
        '--template-file', "$PSScriptRoot\main.bicep",
        '--parameters', $ParametersFile
    )
    foreach ($k in $paramOverrides.Keys) { $azArgs += @('--parameters', "$k=$($paramOverrides[$k])") }

    Write-Host "  Running az $($azArgs -join ' ')"
    & az @azArgs
    if ($LASTEXITCODE -ne 0) { throw "what-if failed" }

    if ($Interactive) {
        $go = Read-Host "Proceed with deployment? (y/N)"
        if ($go -notmatch '^(y|yes)$') { throw "Aborted by user." }
    }
}

# ============================================================================
#  STAGE: Deploy
# ============================================================================
function Invoke-Deploy {
    param($paramOverrides)
    Write-Section "Stage 3/4  Deploy"

    $azArgs = @(
        'deployment','sub','create',
        '--location', $Location,
        '--name',     $DeploymentName,
        '--template-file', "$PSScriptRoot\main.bicep",
        '--parameters', $ParametersFile
    )
    foreach ($k in $paramOverrides.Keys) { $azArgs += @('--parameters', "$k=$($paramOverrides[$k])") }

    Write-Host "  Submitting deployment '$DeploymentName'..."
    $result = & az @azArgs --output json
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Deployment failed. Recent operation errors:"
        az deployment sub operation list --name $DeploymentName --query "[?properties.provisioningState!='Succeeded'].{Op:properties.targetResource.resourceName,State:properties.provisioningState,Status:properties.statusMessage}" --output table
        throw "Deployment failed."
    }
    $r = $result | ConvertFrom-Json
    $r.properties.outputs | ConvertTo-Json -Depth 10 | Set-Content -Path $outputsFile -Encoding UTF8
    Write-Ok "Deployment succeeded. Outputs -> $outputsFile"
    $r.properties.outputs
}

# ============================================================================
#  STAGE: Smoke
# ============================================================================
function Invoke-Smoke {
    param($outputs)
    Write-Section "Stage 4/4  Smoke test"
    if (-not $outputs) { $outputs = (Get-Content $outputsFile -Raw | ConvertFrom-Json) }
    $rg = $outputs.resourceGroupName.value
    $cluster = $outputs.clusterName.value
    Write-Host "  az aks get-credentials -g $rg -n $cluster --overwrite-existing"
    az aks get-credentials --resource-group $rg --name $cluster --overwrite-existing | Out-Null
    Write-Host "  kubectl get nodes"
    & kubectl get nodes
    Write-Ok "Cluster reachable"
}

# ============================================================================
#  Driver
# ============================================================================
try {
    $st = if ($Resume) { Get-DeployState } else { [pscustomobject]@{} }

    # Build parameter overrides (auto-names + CLI overrides)
    $overrides = @{}
    if ($AutoName -or $Interactive) {
        $auto = New-AutoName -workload $WorkloadName -env $Environment -loc $Location
        foreach ($k in @($auto.Keys)) {
            $val = Confirm-Or-Default "  $k" $auto[$k]
            $overrides[$k] = $val
        }
    }
    foreach ($k in @($Overrides.Keys)) { $overrides[$k] = $Overrides[$k] }
    $overrides['mode'] = $Mode
    $overrides['location'] = $Location

    if (-not $DeploymentName) {
        $DeploymentName = "aks-automatic-$(Get-Date -Format yyyyMMdd-HHmmss)"
        if ($Resume -and $st.deploymentName) { $DeploymentName = $st.deploymentName }
    }
    $st | Add-Member -NotePropertyName deploymentName -NotePropertyValue $DeploymentName -Force
    $st | Add-Member -NotePropertyName overrides       -NotePropertyValue $overrides       -Force
    Save-DeployState $st

    if ($Stage -in 'All','Preflight') { $pf = Invoke-Preflight; $st | Add-Member -NotePropertyName preflight -NotePropertyValue $pf -Force; Save-DeployState $st }
    if ($Stage -in 'All','Plan')      { Invoke-Plan -paramOverrides $overrides }
    if ($Stage -in 'All','Deploy')    { $outs = Invoke-Deploy -paramOverrides $overrides; $st | Add-Member -NotePropertyName outputs -NotePropertyValue $outs -Force; Save-DeployState $st }
    if ($Stage -in 'All','Smoke')     { Invoke-Smoke -outputs $st.outputs }

    Write-Section "DONE"
    Write-Host "Next: kubectl get pods -A"
}
catch {
    Write-Err $_.Exception.Message
    Write-Host "`nRe-run with -Resume to retry from the failed stage:" -ForegroundColor Yellow
    Write-Host "  .\deploy.ps1 -Resume" -ForegroundColor Yellow
    exit 1
}
