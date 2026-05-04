<#
.SYNOPSIS
    Azure Infrastructure Deployment Script for Email Assistant

.DESCRIPTION
    Deploys Azure Container Apps infrastructure using Bicep templates.
    Supports validation, what-if preview, and deployment actions with comprehensive error handling.

.PARAMETER ResourceGroup
    The name of the target Azure resource group (must already exist)

.PARAMETER Action
    The deployment action to perform: validate, what-if, or deploy

.PARAMETER SubscriptionId
    Optional Azure subscription ID to use for the deployment

.PARAMETER TemplateFile
    Path to the Bicep template file (default: ./infra/main.bicep)

.PARAMETER ParametersFile
    Path to the Bicep parameters file (default: ./infra/dev.bicepparam)

.PARAMETER DeploymentName
    Custom deployment name (default: auto-generated with timestamp)

.PARAMETER ConfirmDeploy
    Require explicit confirmation before deploying (recommended for production)

.EXAMPLE
    .\deploy.ps1 -ResourceGroup rg-sandbox -Action validate
    .\deploy.ps1 -ResourceGroup rg-prod -Action deploy -SubscriptionId "abc-123" -ConfirmDeploy

.NOTES
    Prerequisites:
    - Azure CLI installed and logged in (az login)
    - Target resource group must already exist
    - User must have appropriate RBAC permissions
#>

param(
    [Parameter(Mandatory = $true, HelpMessage = "Azure resource group name")]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $true, HelpMessage = "Deployment action to perform")]
    [ValidateSet('validate', 'what-if', 'deploy')]
    [string]$Action,

    [Parameter(HelpMessage = "Azure subscription ID (optional)")]
    [string]$SubscriptionId,

    [Parameter(HelpMessage = "Path to Bicep template file")]
    [string]$TemplateFile = "./infra/main.bicep",

    [Parameter(HelpMessage = "Path to Bicep parameters file")]
    [string]$ParametersFile = "./infra/dev.bicepparam",

    [Parameter(HelpMessage = "Custom deployment name")]
    [string]$DeploymentName = "email-assistant-$(Get-Date -Format 'yyyyMMddHHmmss')",

    [Parameter(HelpMessage = "Require confirmation before deploying")]
    [switch]$ConfirmDeploy
)

# ========================================
# Script Configuration
# ========================================

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'  # Suppress progress bars for cleaner output

# ========================================
# Helper Functions
# ========================================

function Write-StatusMessage {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )
    
    $colors = @{
        Info    = 'Cyan'
        Success = 'Green'
        Warning = 'Yellow'
        Error   = 'Red'
    }
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] $Message" -ForegroundColor $colors[$Level]
}

function Assert-Command {
    param([string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        Write-StatusMessage "Required command '$Name' was not found in PATH." -Level Error
        Write-Host "`nPlease install Azure CLI: https://aka.ms/azure-cli" -ForegroundColor Yellow
        throw "Missing required command: $Name"
    }
}

function Test-AzureLogin {
    try {
        $account = az account show 2>$null | ConvertFrom-Json
        if (-not $account) {
            return $false
        }
        return $true
    }
    catch {
        return $false
    }
}

function Assert-FileExists {
    param(
        [string]$Path,
        [string]$Description
    )
    
    if (-not (Test-Path $Path)) {
        Write-StatusMessage "$Description not found at: $Path" -Level Error
        throw "File not found: $Path"
    }
}

# ========================================
# Pre-flight Checks
# ========================================

Write-StatusMessage "Starting Azure deployment script" -Level Info
Write-StatusMessage "Action: $Action | Resource Group: $ResourceGroup" -Level Info

# Check for Azure CLI
Write-StatusMessage "Checking for Azure CLI..." -Level Info
Assert-Command -Name 'az'

# Check Azure CLI version
try {
    $cliVersion = (az version | ConvertFrom-Json).'azure-cli'
    Write-StatusMessage "Azure CLI version: $cliVersion" -Level Success
}
catch {
    Write-StatusMessage "Could not determine Azure CLI version" -Level Warning
}

# Verify Azure login
Write-StatusMessage "Verifying Azure login..." -Level Info
if (-not (Test-AzureLogin)) {
    Write-StatusMessage "Not logged into Azure. Please run 'az login' first." -Level Error
    throw "Azure authentication required"
}

# ========================================
# File Resolution
# ========================================

$repoRoot = Split-Path -Parent $PSScriptRoot

try {
    $resolvedTemplate = Resolve-Path (Join-Path $repoRoot $TemplateFile) -ErrorAction Stop
    Write-StatusMessage "Template file: $resolvedTemplate" -Level Success
    Assert-FileExists -Path $resolvedTemplate -Description "Bicep template"
}
catch {
    Write-StatusMessage "Failed to resolve template file: $TemplateFile" -Level Error
    throw
}

try {
    $resolvedParameters = Resolve-Path (Join-Path $repoRoot $ParametersFile) -ErrorAction Stop
    Write-StatusMessage "Parameters file: $resolvedParameters" -Level Success
    Assert-FileExists -Path $resolvedParameters -Description "Bicep parameters"
}
catch {
    Write-StatusMessage "Failed to resolve parameters file: $ParametersFile" -Level Error
    throw
}

# ========================================
# Azure Context Setup
# ========================================

if ($SubscriptionId) {
    Write-StatusMessage "Setting Azure subscription to: $SubscriptionId" -Level Info
    az account set --subscription $SubscriptionId
    if ($LASTEXITCODE -ne 0) {
        Write-StatusMessage "Failed to set subscription" -Level Error
        throw "Could not set Azure subscription: $SubscriptionId"
    }
}

# Display current Azure context
Write-StatusMessage "Current Azure context:" -Level Info
az account show --output table

# Verify resource group exists
Write-StatusMessage "Verifying resource group '$ResourceGroup' exists..." -Level Info
$rgCheck = az group show --name $ResourceGroup --output json 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-StatusMessage "Resource group '$ResourceGroup' not found" -Level Error
    Write-Host "`nCreate it with: az group create --name $ResourceGroup --location <location>" -ForegroundColor Yellow
    throw "Resource group not found: $ResourceGroup"
}

$rgInfo = $rgCheck | ConvertFrom-Json
Write-StatusMessage "Resource group found in location: $($rgInfo.location)" -Level Success

# ========================================
# Deployment Execution
# ========================================

switch ($Action) {
    'validate' {
        Write-StatusMessage "Running template validation..." -Level Info
        Write-StatusMessage "Deployment name: $DeploymentName-validate" -Level Info
        
        az deployment group validate `
            --name "$DeploymentName-validate" `
            --resource-group $ResourceGroup `
            --template-file $resolvedTemplate `
            --parameters $resolvedParameters `
            --only-show-errors
        
        if ($LASTEXITCODE -eq 0) {
            Write-StatusMessage "✓ Validation completed successfully" -Level Success
        }
        else {
            Write-StatusMessage "✗ Validation failed" -Level Error
            exit $LASTEXITCODE
        }
    }
    
    'what-if' {
        Write-StatusMessage "Running what-if analysis..." -Level Info
        Write-StatusMessage "This will show changes without deploying" -Level Info
        
        az deployment group what-if `
            --name "$DeploymentName-whatif" `
            --resource-group $ResourceGroup `
            --template-file $resolvedTemplate `
            --parameters $resolvedParameters `
            --result-format FullResourcePayloads `
            --only-show-errors
        
        if ($LASTEXITCODE -eq 0) {
            Write-StatusMessage "✓ What-if analysis completed" -Level Success
        }
        else {
            Write-StatusMessage "✗ What-if analysis failed" -Level Error
            exit $LASTEXITCODE
        }
    }
    
    'deploy' {
        # Confirmation prompt for production safety
        if ($ConfirmDeploy) {
            Write-Host "`n" -NoNewline
            $confirmation = Read-Host "Are you sure you want to deploy to '$ResourceGroup'? (yes/no)"
            if ($confirmation -ne 'yes') {
                Write-StatusMessage "Deployment cancelled by user" -Level Warning
                exit 0
            }
        }
        
        Write-StatusMessage "Starting infrastructure deployment..." -Level Info
        Write-StatusMessage "Deployment name: $DeploymentName" -Level Info
        Write-StatusMessage "This may take several minutes..." -Level Info
        
        $deploymentStartTime = Get-Date
        
        az deployment group create `
            --name $DeploymentName `
            --resource-group $ResourceGroup `
            --template-file $resolvedTemplate `
            --parameters $resolvedParameters `
            --output json `
            --only-show-errors
        
        $deploymentExitCode = $LASTEXITCODE
        $deploymentEndTime = Get-Date
        $duration = $deploymentEndTime - $deploymentStartTime
        
        if ($deploymentExitCode -eq 0) {
            Write-StatusMessage "✓ Deployment completed successfully" -Level Success
            Write-StatusMessage "Duration: $($duration.ToString('mm\:ss'))" -Level Success
            
            # Retrieve and display outputs
            Write-StatusMessage "`nRetrieving deployment outputs..." -Level Info
            $outputs = az deployment group show `
                --name $DeploymentName `
                --resource-group $ResourceGroup `
                --query properties.outputs `
                --output json | ConvertFrom-Json
            
            if ($outputs) {
                Write-Host "`n========================================" -ForegroundColor Cyan
                Write-Host "Deployment Outputs" -ForegroundColor Cyan
                Write-Host "========================================" -ForegroundColor Cyan
                $outputs.PSObject.Properties | ForEach-Object {
                    Write-Host "$($_.Name): $($_.Value.value)" -ForegroundColor White
                }
                Write-Host "========================================`n" -ForegroundColor Cyan
            }
        }
        else {
            Write-StatusMessage "✗ Deployment failed" -Level Error
            Write-StatusMessage "Duration: $($duration.ToString('mm\:ss'))" -Level Error
            Write-Host "`nCheck deployment details in Azure Portal or run:" -ForegroundColor Yellow
            Write-Host "az deployment group show --name $DeploymentName --resource-group $ResourceGroup" -ForegroundColor Yellow
            exit $deploymentExitCode
        }
    }
}

Write-StatusMessage "`nScript completed successfully" -Level Success
exit 0