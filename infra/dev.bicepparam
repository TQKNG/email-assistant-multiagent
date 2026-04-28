using './main.bicep'

param namePrefix = 'email-assistant-dev'
param containerImage = 'myregistry.azurecr.io/email-assistant:latest'

// Set this only when the image lives in an ACR in the same resource group.
param containerRegistryName = ''

param ingressExternal = true
param targetPort = 8000
param minReplicas = 0
param maxReplicas = 3
param httpConcurrentRequests = 10
param cpuCores = 1
param memory = '2Gi'

param enableNetworkLayer = true
param virtualNetworkName = 'vnet-email-assistant-dev'
param virtualNetworkAddressPrefix = '10.40.0.0/23'
param infrastructureSubnetName = 'aca-infra'
param infrastructureSubnetAddressPrefix = '10.40.0.0/27'
param networkSecurityGroupName = 'nsg-email-assistant-dev'
param internalManagedEnvironment = false

// Required for runtime calls through DefaultAzureCredential.
param azureAiProjectEndpoint = 'https://your-project.services.ai.azure.com/api/projects/your-project'

// Optional but recommended. When both names are set, the template grants Azure AI User to the container app identity.
// The Foundry account and project must be in the same resource group as this deployment.
param azureAiAccountName = '<foundry-account-name>'
param azureAiProjectName = '<foundry-project-name>'

// Leave empty unless the app also needs direct account-scope OpenAI calls.
// The account must be in the same resource group as this deployment.
param openAiAccountName = ''

param openAiChatModel = 'gpt-4o-mini'
param deepseekChatModel = 'DeepSeek-R1'
param knowledgeBaseAgentName = 'knowledge-base'
param knowledgeBaseAgentVersion = 'latest'

param tags = {
  environment: 'dev'
  app: 'email-assistant'
  costCenter: 'sandbox'
}
