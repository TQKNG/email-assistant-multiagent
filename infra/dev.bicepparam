using './main.bicep'

// ========================================
// General Configuration
// ========================================

param namePrefix = 'email-assistant-dev'

// ========================================
// Container Configuration
// ========================================

param containerImage = 'myregistry.azurecr.io/email-assistant:latest'

// Set this only when the image lives in an ACR in the same resource group.
// Leave empty for public images or images from external registries.
param containerRegistryName = ''

// ========================================
// Ingress and Scaling
// ========================================

param ingressExternal = true
param targetPort = 8000
param minReplicas = 0  // Set to 0 for dev to save costs (allows scale-to-zero)
param maxReplicas = 3
param httpConcurrentRequests = 10
param cpuCores = 1  // Container CPU cores (supports fractional values via code change)
param memory = '2Gi'

// ========================================
// Networking Configuration
// ========================================

param zoneRedundant = false  // Set to true for production
// param environmentPublicNetworkAccess = 'Enabled'  // Not supported in stable API version
param enableNetworkLayer = true
param virtualNetworkName = 'vnet-email-assistant-dev'
param virtualNetworkAddressPrefix = '10.40.0.0/23'
param infrastructureSubnetName = 'aca-infra'
param infrastructureSubnetAddressPrefix = '10.40.0.0/27'
param networkSecurityGroupName = 'nsg-email-assistant-dev'
param internalManagedEnvironment = false

// ========================================
// Azure AI Configuration
// ========================================

// Required for runtime calls through DefaultAzureCredential.
param azureAiProjectEndpoint = 'https://langchain-academy-resource.services.ai.azure.com/api/projects/langchain-academy'

// Note: Log retention and diagnostics are configured in the main template
// with default values (30 days retention, diagnostics enabled)

// Optional but recommended. When both names are set, the template grants Azure AI User to the container app identity.
// The Foundry account and project must be in the same resource group as this deployment.
param azureAiAccountName = 'langchain-academy-resource'
param azureAiProjectName = 'langchain-academy'

// Leave empty unless the app also needs direct account-scope OpenAI calls.
// The account must be in the same resource group as this deployment.
param openAiAccountName = ''

param openAiChatModel = 'gpt-4o-mini'
param deepseekChatModel = 'DeepSeek-R1'
param knowledgeBaseAgentName = 'knowledge-base'
param knowledgeBaseAgentVersion = 'latest'

// ========================================
// Resource Tagging
// ========================================

param tags = {
  environment: 'dev'
  app: 'email-assistant'
  costCenter: 'sandbox'
  owner: 'devops-team'
}
