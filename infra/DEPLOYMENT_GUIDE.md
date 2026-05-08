# Azure Infrastructure Deployment Guide

## Overview

This guide describes the revised Bicep infrastructure templates and deployment process for the Email Assistant application on Azure Container Apps.

## What's New

### 🔧 Bicep Template Improvements ([main.bicep](main.bicep))

#### 1. **Stable API Versions**
- Updated all resources to use production-stable API versions
- Moved away from preview/future API versions for reliability
- **Log Analytics**: `2023-09-01`
- **Managed Identity**: `2023-01-31`
- **Networking**: `2023-11-01`
- **Container Apps**: `2024-03-01`
- **Container Registry**: `2023-11-01-preview`
- **Cognitive Services**: `2024-10-01`

#### 2. **Enhanced Security Features**
- **Network Security Groups**: Pre-configured rules for Container Apps
  - HTTPS inbound traffic (port 443)
  - Container Apps control plane communication
- **Diagnostic Settings**: Added for monitoring and security auditing
  - NSG flow logs to Log Analytics
  - Container Apps Environment logs
  - Container App application logs and metrics

#### 3. **Better Parameter Validation**
- Added `@minLength`, `@maxLength` constraints on critical parameters
- Added `@minValue`, `@maxValue` for numeric parameters
- Added `@allowed` attribute for restricted value sets
- Improved parameter descriptions and help text

#### 4. **Improved Code Organization**
- Added section headers for better readability
- Grouped related parameters together
- Separated concerns (general, container, networking, AI config)
- Enhanced comments throughout

#### 5. **Comprehensive Outputs**
- Added resource IDs for all major resources
- Included networking details when VNet is enabled
- Added FQDN and URL outputs for the Container App
- Grouped outputs by category

#### 6. **Enhanced Tagging Strategy**
- Auto-generated deployment timestamp
- Consistent tagging across all resources
- Support for custom tags via parameters

### 📝 Parameter File Improvements ([dev.bicepparam](dev.bicepparam))

- Organized parameters into logical sections
- Added inline comments explaining each configuration
- Included best practice recommendations (e.g., minReplicas=0 for dev)
- Documented dependencies between parameters

### 🚀 Deployment Script Enhancements ([deploy.ps1](deploy.ps1))

#### New Features
1. **Enhanced Error Handling**
   - Better error messages with actionable guidance
   - Pre-flight validation checks
   - Azure CLI version detection

2. **Improved User Experience**
   - Color-coded status messages (Info, Success, Warning, Error)
   - Timestamp logging for all operations
   - Progress indicators and duration tracking
   - Comprehensive help documentation

3. **Safety Features**
   - Azure login verification before deployment
   - Resource group existence check
   - Optional deployment confirmation (`-ConfirmDeploy` switch)
   - File existence validation

4. **Deployment Outputs**
   - Automatically displays deployment outputs after successful deployment
   - Shows deployment duration
   - Links to Azure Portal for troubleshooting

5. **Better Documentation**
   - PowerShell help comments with examples
   - Parameter descriptions
   - Prerequisites clearly documented

## Quick Start

### Prerequisites

1. **Azure CLI** installed and configured
   ```powershell
   az --version  # Verify installation
   az login      # Authenticate
   ```

2. **Resource Group** must exist
   ```powershell
   az group create --name rg-sandbox --location eastus
   ```

3. **Configuration** - Update [dev.bicepparam](dev.bicepparam):
   - Set your container image reference
   - Configure Azure AI endpoint
   - Set the Azure AI account name, and set the project name only if you use Azure AI Foundry projects
   - Adjust networking parameters if needed

### Deployment Workflow

#### 1. Validate Template
```powershell
./infra/deploy.ps1 -ResourceGroup rg-sandbox -Action validate
```

Checks template syntax and parameter validity without deploying anything.

#### 2. Preview Changes (What-If)
```powershell
./infra/deploy.ps1 -ResourceGroup rg-sandbox -Action what-if
```

Shows what resources will be created, modified, or deleted.

#### 3. Deploy Infrastructure
```powershell
./infra/deploy.ps1 -ResourceGroup rg-sandbox -Action deploy
```

For production deployments with confirmation:
```powershell
./infra/deploy.ps1 -ResourceGroup rg-prod -Action deploy -ConfirmDeploy
```

With specific subscription:
```powershell
./infra/deploy.ps1 -ResourceGroup rg-prod -SubscriptionId "your-sub-id" -Action deploy
```

### VS Code Tasks

Use the Command Palette (`Ctrl+Shift+P`) and run:
- `Tasks: Run Task` → `Azure: Validate`
- `Tasks: Run Task` → `Azure: What-If`
- `Tasks: Run Task` → `Azure: Deploy`

## Architecture

### Resources Deployed

1. **Log Analytics Workspace**
   - Centralized logging and monitoring
   - Configurable retention period (default: 30 days)

2. **User-Assigned Managed Identity**
   - Used by Container App for Azure service authentication
   - Automatically granted necessary RBAC roles

3. **Virtual Network** (optional, enabled by default in dev)
   - Custom address space configuration
   - Delegated subnet for Container Apps

4. **Network Security Group** (when VNet enabled)
   - Pre-configured security rules
   - Diagnostic logging enabled

5. **Container Apps Environment**
   - Hosts the container application
   - Connected to Log Analytics
   - Optional zone redundancy for production

6. **Container App**
   - Runs the Email Assistant application
   - Auto-scaling based on HTTP requests
   - Health probes (startup, readiness, liveness)
   - Environment variables for Azure AI integration

### RBAC Assignments

The managed identity automatically receives:
- **ACR Pull** role (if using Azure Container Registry)
- **Azure AI User** role at the Cognitive Services account scope (if `azureAiAccountName` is configured)
- **Cognitive Services OpenAI User** role (if OpenAI account configured)

## Configuration Reference

### Key Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `namePrefix` | `email-assistant` | Prefix for resource names |
| `location` | Resource Group location | Azure region |
| `minReplicas` | 1 | Minimum container instances (0 for scale-to-zero) |
| `maxReplicas` | 3 | Maximum container instances |
| `cpuCores` | 1 | CPU cores per container |
| `memory` | `2Gi` | Memory per container |
| `enableNetworkLayer` | false | Deploy custom VNet |
| `zoneRedundant` | false | Enable zone redundancy (prod) |
| `logRetentionInDays` | 30 | Log retention period |

### Environment Variables

The Container App automatically configures:
- `AZURE_CLIENT_ID` - Managed identity client ID
- `AZURE_AI_PROJECT_ENDPOINT` - AI project endpoint
- `OPENAI_CHAT_MODEL` - Primary chat model
- `DEEPSEEK_CHAT_MODEL` - Reasoning model
- `KNOWLEDGE_BASE_AGENT_NAME` - Knowledge base agent
- `KNOWLEDGE_BASE_AGENT_VERSION` - Agent version
- `PORT` - Application port (8000)

## Monitoring and Troubleshooting

### Azure AI resource type troubleshooting

Azure supports two different AI resource layouts, and the Bicep parameters need to match the one you actually deployed:

#### Azure AI Foundry

Use this when your endpoint and resources follow a hub/project structure:

```text
AI Hub (Microsoft.CognitiveServices/accounts)
  └─ Project (Microsoft.CognitiveServices/accounts/projects)
      └─ Models and agents
```

- Keep `azureAiAccountName` set to the hub/account name.
- Set `azureAiProjectName` to the project name when your runtime endpoint includes `/projects/<project-name>`.

#### Standard Cognitive Services with model deployments

Use this when your resource group only contains a Cognitive Services account plus model deployments:

```text
Account (Microsoft.CognitiveServices/accounts)
  └─ Deployments (gpt-4o-mini, DeepSeek-R1, text-embedding-3-small, ...)
```

- Set `azureAiAccountName` to the Cognitive Services account name.
- Leave `azureAiProjectName` empty.
- The template now assigns the managed identity's **Azure AI User** role at the account scope, so deployment does not depend on a Foundry project resource that may not exist.

### View Deployment Status
```powershell
az deployment group show \
  --name <deployment-name> \
  --resource-group rg-sandbox \
  --output table
```

### Check Container App Logs
```powershell
az containerapp logs show \
  --name <container-app-name> \
  --resource-group rg-sandbox \
  --follow
```

### Verify RBAC Assignments
```powershell
az role assignment list \
  --assignee <managed-identity-principal-id> \
  --all \
  --output table
```

### Network Diagnostics
```powershell
# View NSG rules
az network nsg show \
  --name <nsg-name> \
  --resource-group rg-sandbox

# Check VNet configuration
az network vnet show \
  --name <vnet-name> \
  --resource-group rg-sandbox
```

## Best Practices

### Development Environment
- Set `minReplicas = 0` to enable scale-to-zero (cost savings)
- Use smaller CPU/memory allocations
- Shorter log retention (30 days)
- Single zone deployment

### Production Environment
- Set `minReplicas >= 1` for zero cold-start latency
- Enable `zoneRedundant = true` for high availability
- Increase `maxReplicas` based on load testing
- Longer log retention (90+ days)
- Set `environmentPublicNetworkAccess = 'Disabled'` if using private endpoints
- Consider `internalManagedEnvironment = true` for internal apps

### Security Recommendations
1. **Never commit secrets** to parameter files
2. **Use Key Vault** for sensitive configuration
3. **Enable diagnostic settings** for audit logging
4. **Review NSG rules** for your specific requirements
5. **Implement Azure Policy** for governance
6. **Enable Microsoft Defender** for Container Apps

## Cost Optimization

- **Scale to Zero**: Set `minReplicas = 0` in non-prod environments
- **Right-size resources**: Start with smaller CPU/memory, scale up as needed
- **Log retention**: Adjust based on compliance requirements
- **Zone redundancy**: Only enable for production workloads
- **VNet**: Use only when network isolation is required

## CI/CD Integration

The deployment script is designed to work with:
- **GitHub Actions** (see [.github/workflows/deploy.yml](../.github/workflows/deploy.yml))
- **Azure DevOps Pipelines**
- **Local development** workflows

Example GitHub Actions step:
```yaml
- name: Deploy Infrastructure
  run: |
    ./infra/deploy.ps1 `
      -ResourceGroup ${{ vars.AZURE_RESOURCE_GROUP }} `
      -SubscriptionId ${{ secrets.AZURE_SUBSCRIPTION_ID }} `
      -Action deploy
```

## Migration from Previous Version

### Breaking Changes
None - the revised templates are backward compatible.

### New Features Available
1. Diagnostic settings for monitoring
2. Enhanced NSG rules
3. Better outputs for operational visibility
4. Improved deployment script error handling

### Recommended Actions
1. Review and update your [dev.bicepparam](dev.bicepparam) file
2. Test deployment in a non-production environment first
3. Review the new outputs after deployment
4. Update your runbooks with new error handling capabilities

## Support and Resources

- [Azure Container Apps Documentation](https://learn.microsoft.com/azure/container-apps/)
- [Bicep Language Reference](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)
- [Azure CLI Reference](https://learn.microsoft.com/cli/azure/)
- [Project README](../README.md)

## Troubleshooting Common Issues

### Error: "Resource group not found"
**Solution**: Create the resource group first:
```powershell
az group create --name rg-sandbox --location eastus
```

### Error: "Template validation failed"
**Solution**: Run validation to see detailed errors:
```powershell
./infra/deploy.ps1 -ResourceGroup rg-sandbox -Action validate
```

### Error: "Insufficient permissions"
**Solution**: Ensure you have at least Contributor role on the resource group.

### Error: "Container image pull failed"
**Solution**: 
1. Verify the image exists and is accessible
2. Check ACR configuration if using private registry
3. Verify managed identity has AcrPull role

### Deployment takes too long
**Expected**: Initial deployment typically takes 5-10 minutes. Container Apps environment creation is the longest step.

## Changelog

### Version 2.0 (Current)
- ✅ Stable API versions across all resources
- ✅ Diagnostic settings for monitoring
- ✅ Enhanced network security rules
- ✅ Comprehensive outputs
- ✅ Improved deployment script with error handling
- ✅ Better parameter validation
- ✅ Enhanced documentation

### Version 1.0 (Previous)
- Basic Bicep template
- Simple deployment script
- Minimal error handling
