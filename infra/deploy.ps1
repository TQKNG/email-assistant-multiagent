param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $true)]
    [ValidateSet('validate', 'what-if', 'deploy')]
    [string]$Action,

    [string]$SubscriptionId,

    [string]$TemplateFile = "./infra/main.bicep",

    [string]$ParametersFile = "./infra/dev.bicepparam",

    [string]$DeploymentName = "email-assistant-$(Get-Date -Format 'yyyyMMddHHmmss')"
)

$ErrorActionPreference = 'Stop'

function Assert-Command {
    param([string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found in PATH."
    }
}

Assert-Command -Name 'az'

$repoRoot = Split-Path -Parent $PSScriptRoot
$resolvedTemplate = Resolve-Path (Join-Path $repoRoot $TemplateFile)
$resolvedParameters = Resolve-Path (Join-Path $repoRoot $ParametersFile)

if ($SubscriptionId) {
    Write-Host "Setting Azure subscription to $SubscriptionId" -ForegroundColor Cyan
    az account set --subscription $SubscriptionId
}

Write-Host "Checking Azure login context" -ForegroundColor Cyan
az account show --output table

Write-Host "Checking target resource group '$ResourceGroup'" -ForegroundColor Cyan
az group show --name $ResourceGroup --output table | Out-Null

switch ($Action) {
    'validate' {
        Write-Host "Running preflight validation" -ForegroundColor Cyan
        az deployment group validate `
            --name "$DeploymentName-validate" `
            --resource-group $ResourceGroup `
            --template-file $resolvedTemplate `
            --parameters $resolvedParameters `
            --only-show-errors
    }
    'what-if' {
        Write-Host "Running what-if preview" -ForegroundColor Cyan
        az deployment group what-if `
            --name "$DeploymentName-whatif" `
            --resource-group $ResourceGroup `
            --template-file $resolvedTemplate `
            --parameters $resolvedParameters `
            --result-format FullResourcePayloads `
            --only-show-errors
    }
    'deploy' {
        Write-Host "Starting deployment" -ForegroundColor Cyan
        az deployment group create `
            --name $DeploymentName `
            --resource-group $ResourceGroup `
            --template-file $resolvedTemplate `
            --parameters $resolvedParameters `
            --only-show-errors
    }
}
