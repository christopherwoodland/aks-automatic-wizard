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

    # ---------- PowerShell version ----------
    Write-Host "  Checking PowerShell..."
    if ($PSVersionTable.PSVersion -lt [Version]'7.0') {
        Write-Warn2 "PowerShell $($PSVersionTable.PSVersion) detected; 7.0+ recommended (PSNativeCommandUseErrorActionPreference, ternary, etc.)."
    } else {
        Write-Ok "PowerShell $($PSVersionTable.PSVersion)"
    }

    # ---------- Azure CLI (auto-install via winget on Windows) ----------
    Write-Host "  Checking Azure CLI..."
    $cli = $null
    try { $cli = az version --output json 2>$null | ConvertFrom-Json } catch {}
    if (-not $cli) {
        Write-Warn2 "Azure CLI not found."
        if ($IsWindows -or $env:OS -eq 'Windows_NT') {
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                Write-Host "  Installing via winget..."
                winget install --id Microsoft.AzureCLI -e --accept-source-agreements --accept-package-agreements --silent | Out-Null
                $env:PATH = "$env:ProgramFiles\Microsoft SDKs\Azure\CLI2\wbin;$env:PATH"
                $cli = az version --output json 2>$null | ConvertFrom-Json
            }
        }
        if (-not $cli) { throw "Azure CLI not found. Install: https://aka.ms/azure-cli" }
    }
    $cliVer = [Version]$cli.'azure-cli'
    if ($cliVer -lt [Version]'2.77.0') {
        Write-Warn2 "Azure CLI $cliVer < 2.77.0 required. Upgrading..."
        az upgrade --yes --only-show-errors 2>&1 | Out-Null
        $cli = az version --output json | ConvertFrom-Json
        $cliVer = [Version]$cli.'azure-cli'
        if ($cliVer -lt [Version]'2.77.0') { throw "Azure CLI $cliVer still < 2.77.0 after upgrade." }
    }
    Write-Ok "Azure CLI $cliVer"

    # ---------- Bicep CLI (bundled with az; install if missing) ----------
    Write-Host "  Checking Bicep CLI..."
    $bicep = $null
    try { $bicep = (az bicep version 2>$null) } catch {}
    if (-not $bicep) {
        Write-Warn2 "Bicep not installed. Installing..."
        az bicep install --only-show-errors 2>&1 | Out-Null
        $bicep = az bicep version 2>$null
    } else {
        az bicep upgrade --only-show-errors 2>&1 | Out-Null
    }
    Write-Ok "Bicep: $($bicep -replace 'Bicep CLI version ','')"

    # ---------- aks-preview extension ----------
    Write-Host "  Checking aks-preview extension..."
    $ext = az extension list --query "[?name=='aks-preview']" --output json | ConvertFrom-Json
    if (-not $ext) {
        Write-Warn2 "aks-preview not installed. Installing..."
        az extension add --name aks-preview --only-show-errors | Out-Null
    } else {
        az extension update --name aks-preview --only-show-errors 2>$null | Out-Null
    }
    Write-Ok "aks-preview ready"

    # ---------- kubectl (auto-install via 'az aks install-cli') ----------
    Write-Host "  Checking kubectl..."
    if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
        Write-Warn2 "kubectl not found. Installing via 'az aks install-cli'..."
        $prevPref = $PSNativeCommandUseErrorActionPreference
        try {
            $PSNativeCommandUseErrorActionPreference = $false
            az aks install-cli --only-show-errors 2>&1 | Out-Null
        } finally { $PSNativeCommandUseErrorActionPreference = $prevPref }
        if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
            Write-Warn2 "kubectl install location may not be on PATH. Smoke test will surface this if it's missing."
        } else {
            Write-Ok "kubectl installed"
        }
    } else {
        Write-Ok "kubectl present"
    }

    # ---------- Login ----------
    Write-Host "  Checking login..."
    $acct = az account show --output json 2>$null | ConvertFrom-Json
    if (-not $acct) {
        Write-Warn2 "Not logged in. Launching 'az login'..."
        az login --only-show-errors | Out-Null
        $acct = az account show --output json | ConvertFrom-Json
    }

    if ($SubscriptionId) {
        if ($acct.id -ne $SubscriptionId) {
            az account set --subscription $SubscriptionId | Out-Null
            $acct = az account show --output json | ConvertFrom-Json
        }
    }
    Write-Ok "Subscription: $($acct.name)  ($($acct.id))"
    Write-Ok "Tenant:       $($acct.tenantId)"

    # ---------- RBAC sanity ----------
    Write-Host "  Checking caller RBAC on subscription..."
    $me = az ad signed-in-user show --query id -o tsv 2>$null
    if ($me) {
        $roles = az role assignment list --assignee $me --scope "/subscriptions/$($acct.id)" --include-inherited --query "[].roleDefinitionName" -o tsv 2>$null
        if ($roles -match 'Owner|Contributor|User Access Administrator') {
            Write-Ok "Caller has: $(($roles | Sort-Object -Unique) -join ', ')"
        } else {
            Write-Warn2 "Caller roles: $(@($roles) -join ', '). Need Contributor + (User Access Administrator OR Owner) for role assignments."
        }
    } else {
        Write-Warn2 "Could not resolve signed-in user (service principal?). Skipping RBAC sanity check."
    }

    # ---------- Provider registration ----------
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

    # ---------- Region availability for AKS ----------
    Write-Host "  Checking AKS availability in '$Location'..."
    $locs = az provider show --namespace Microsoft.ContainerService --query "resourceTypes[?resourceType=='managedClusters'].locations[]" -o tsv 2>$null
    if ($locs) {
        $normalized = $locs | ForEach-Object { ($_ -replace '\s','').ToLower() }
        if ($normalized -notcontains $Location.ToLower()) {
            Write-Warn2 "Location '$Location' is not in the AKS region list. Continuing, but deployment may fail."
        } else {
            Write-Ok "AKS available in '$Location'"
        }
    }

    if ($Mode -eq 'automaticManaged') {
        Write-Host "  Checking preview feature AKS-AutomaticHostedSystemProfilePreview..."
        $feat = az feature show --namespace Microsoft.ContainerService --name AKS-AutomaticHostedSystemProfilePreview --output json | ConvertFrom-Json
        if ($feat.properties.state -ne 'Registered') {
            Write-Warn2 "Feature not registered. Registering now (this can take several minutes)..."
            $prevPref = $PSNativeCommandUseErrorActionPreference
            try {
                $PSNativeCommandUseErrorActionPreference = $false
                az feature register --namespace Microsoft.ContainerService --name AKS-AutomaticHostedSystemProfilePreview 2>&1 | Out-Null
                do {
                    Start-Sleep -Seconds 20
                    $feat = az feature show --namespace Microsoft.ContainerService --name AKS-AutomaticHostedSystemProfilePreview --output json | ConvertFrom-Json
                    Write-Host "    state: $($feat.properties.state)"
                } while ($feat.properties.state -ne 'Registered')
                az provider register --namespace Microsoft.ContainerService 2>&1 | Out-Null
            } finally { $PSNativeCommandUseErrorActionPreference = $prevPref }
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
    if (-not $outputs) {
        if (-not (Test-Path $outputsFile)) {
            throw "No deployment outputs found at $outputsFile. Run the Deploy stage first (or pass -Resume after a previous Deploy)."
        }
        $outputs = (Get-Content $outputsFile -Raw | ConvertFrom-Json)
    }
    $rg = $outputs.resourceGroupName.value
    $cluster = $outputs.clusterName.value
    Write-Host "  az aks get-credentials -g $rg -n $cluster --overwrite-existing"
    az aks get-credentials --resource-group $rg --name $cluster --overwrite-existing | Out-Null
    Write-Host "  kubectl get nodes"
    & kubectl get nodes
    if ($outputs.PSObject.Properties.Name -contains 'oidcIssuerUrl' -and $outputs.oidcIssuerUrl.value) {
        Write-Host ""
        Write-Host "OIDC issuer URL : $($outputs.oidcIssuerUrl.value)"
        Write-Host "  (use for Workload Identity federated credentials -- see README)"
    }
    Write-Ok "Cluster reachable"
}

# ============================================================================
#  Driver
# ============================================================================
try {
    $st = if ($Resume) { Get-DeployState } else { [pscustomobject]@{} }

    # Build parameter overrides (auto-names + CLI overrides)
    $overrides = @{}

    # On -Resume, restore the original auto-generated names + saved CLI overrides
    # so we don't try to create a *different* set of resources with a new random suffix.
    if ($Resume -and $st.PSObject.Properties.Name -contains 'overrides' -and $st.overrides) {
        foreach ($p in $st.overrides.PSObject.Properties) { $overrides[$p.Name] = $p.Value }
        if ($AutoName) { Write-Warn2 "-Resume detected: reusing names from prior run (ignoring -AutoName regeneration)." }
    }
    elseif ($AutoName -or $Interactive) {
        $auto = New-AutoName -workload $WorkloadName -env $Environment -loc $Location
        foreach ($k in @($auto.Keys)) {
            $val = Confirm-Or-Default "  $k" $auto[$k]
            $overrides[$k] = $val
        }
    }
    # CLI -Overrides always win (last) so users can patch a resumed run.
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
    if ($Stage -in 'All','Smoke')     { Invoke-Smoke -outputs ($st.outputs) }

    Write-Section "DONE"
    Write-Host "Next: kubectl get pods -A"
}
catch {
    Write-Err $_.Exception.Message
    Write-Host "`nRe-run with -Resume to retry from the failed stage:" -ForegroundColor Yellow
    Write-Host "  .\deploy.ps1 -Resume" -ForegroundColor Yellow
    exit 1
}
