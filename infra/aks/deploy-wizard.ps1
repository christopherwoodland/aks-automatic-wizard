<#
.SYNOPSIS
  Launches the AKS deployment wizard UI in your default browser.

.DESCRIPTION
  Opens infra/aks/wizard/index.html, which helps you build deployment commands
  for deploy.ps1 and az deployment sub create with main.bicepparam.
#>
[CmdletBinding()]
param()

$wizardPath = Join-Path $PSScriptRoot 'wizard\index.html'
if (-not (Test-Path $wizardPath)) {
    throw "Wizard file not found: $wizardPath"
}

$uri = [System.Uri]::new($wizardPath).AbsoluteUri
Write-Host "Opening AKS Deployment Wizard..." -ForegroundColor Cyan
Write-Host "  $wizardPath"
Start-Process $uri | Out-Null
