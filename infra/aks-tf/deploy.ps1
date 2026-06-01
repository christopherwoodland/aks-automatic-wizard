param(
  [switch]$Init,
  [switch]$Upgrade,
  [switch]$Plan,
  [switch]$Apply,
  [switch]$Destroy,
  [switch]$AutoApprove
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

function Invoke-Terraform {
  param(
    [Parameter(Mandatory = $true)][string[]]$Arguments
  )

  & terraform @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "terraform $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
  }
}

if (-not (Test-Path -LiteralPath (Join-Path $scriptDir 'terraform.tfvars'))) {
  Write-Host 'terraform.tfvars not found. Copy terraform.tfvars.example and fill in values before applying.'
}

if ($Init) {
  $initArgs = @('init')
  if ($Upgrade) {
    $initArgs += '-upgrade'
  }
  Invoke-Terraform -Arguments $initArgs
  return
}

Invoke-Terraform -Arguments @('init')
Invoke-Terraform -Arguments @('fmt', '-check', '-recursive')
Invoke-Terraform -Arguments @('validate')

if ($Plan) {
  Invoke-Terraform -Arguments @('plan')
  return
}

if ($Destroy) {
  $destroyArgs = @('destroy')
  if ($AutoApprove) {
    $destroyArgs += '-auto-approve'
  }
  Invoke-Terraform -Arguments $destroyArgs
  return
}

if ($Apply) {
  $applyArgs = @('apply')
  if ($AutoApprove) {
    $applyArgs += '-auto-approve'
  }
  Invoke-Terraform -Arguments $applyArgs
  return
}

Invoke-Terraform -Arguments @('plan')
