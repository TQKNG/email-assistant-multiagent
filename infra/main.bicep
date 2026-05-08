targetScope = 'resourceGroup'

@description('Short prefix used in generated resource names. Use lowercase letters, numbers, and hyphens.')
param namePrefix string = 'email-assistant'

@description('Azure region for all resources. Defaults to the current resource group location.')
param location string = resourceGroup().location

@description('Full container image reference, for example myregistry.azurecr.io/email-assistant:latest.')
param containerImage string

@description('Existing Azure Container Registry name in the same resource group. Leave empty when using a public image or an image from another registry already configured for pull access.')
param containerRegistryName string = ''

@description('External ingress toggle. Keep true for a public HTTP API.')
param ingressExternal bool = true

@description('Port the application listens on inside the container. The current FastAPI app uses 8000.')
param targetPort int = 8000

@allowed([
  'auto'
  'http'
  'http2'
  'tcp'
])
@description('Ingress transport protocol for the container app.')
param ingressTransport string = 'auto'

@description('Minimum replicas. Use 1 for low-latency interactive APIs; set to 0 for lower dev cost with cold starts.')
param minReplicas int = 1

@description('Maximum replicas for the container app.')
param maxReplicas int = 3

@description('Approximate concurrent HTTP requests per replica before scaling out.')
param httpConcurrentRequests int = 10

@description('Container CPU cores.')
param cpuCores int = 1

@description('Container memory allocation.')
param memory string = '2Gi'

@description('Log Analytics retention in days.')
param logRetentionInDays int = 30

@description('Whether the Container Apps managed environment should be zone redundant.')
param zoneRedundant bool = false

@description('Deploy a customer-managed virtual network layer for the Container Apps environment.')
param enableNetworkLayer bool = false

@description('Virtual network name used by the Container Apps environment when the network layer is enabled.')
param virtualNetworkName string = ''

@description('Address space for the virtual network. Use a private CIDR that does not overlap with connected networks.')
param virtualNetworkAddressPrefix string = '10.40.0.0/23'

@description('Delegated infrastructure subnet name for Azure Container Apps.')
param infrastructureSubnetName string = 'aca-infra'

@description('Address prefix for the delegated infrastructure subnet. A workload profiles environment supports /27 or larger.')
param infrastructureSubnetAddressPrefix string = '10.40.0.0/27'

@description('Network security group name for the delegated Container Apps subnet when the network layer is enabled.')
param networkSecurityGroupName string = ''

@description('Set true to create an internal-only Container Apps environment load balancer. When enabled, consider setting ingressExternal to false.')
param internalManagedEnvironment bool = false

@description('Azure AI project endpoint used by the app.')
param azureAiProjectEndpoint string

@description('Optional Azure AI Foundry account name that owns the target project. When set together with azureAiProjectName, the container app managed identity receives the Azure AI User role at the project scope.')
param azureAiAccountName string = ''

@description('Optional Azure AI Foundry project name used by the app. Leave empty to skip project-level RBAC assignment.')
param azureAiProjectName string = ''

@description('Optional Azure OpenAI or Azure AI Services account name for direct account-scope inference. When set, the container app managed identity receives the Cognitive Services OpenAI User role at that scope.')
param openAiAccountName string = ''

@description('Primary chat model name used by the app.')
param openAiChatModel string = 'gpt-4o-mini'

@description('Secondary reasoning model name used by the app.')
param deepseekChatModel string = 'DeepSeek-R1'

@description('Azure AI agent name for knowledge base lookup.')
param knowledgeBaseAgentName string = 'knowledge-base'

@description('Azure AI agent version for knowledge base lookup.')
param knowledgeBaseAgentVersion string = 'latest'

@description('Optional tags applied to all created resources.')
param tags object = {}

var sanitizedPrefix = toLower(replace(namePrefix, ' ', '-'))
var suffix = uniqueString(resourceGroup().id, sanitizedPrefix, location)
var containerAppName = take('ca-${sanitizedPrefix}-${suffix}', 32)
var environmentName = take('cae-${sanitizedPrefix}-${suffix}', 40)
var logAnalyticsWorkspaceName = take('law-${sanitizedPrefix}-${suffix}', 63)
var userAssignedIdentityName = take('id-${sanitizedPrefix}-${suffix}', 128)
var resolvedVirtualNetworkName = !empty(virtualNetworkName) ? virtualNetworkName : take('vnet-${sanitizedPrefix}-${suffix}', 64)
var resolvedNetworkSecurityGroupName = !empty(networkSecurityGroupName) ? networkSecurityGroupName : take('nsg-${sanitizedPrefix}-${suffix}', 80)
var useAcr = !empty(containerRegistryName)
var useNetworkLayer = enableNetworkLayer
var assignAzureAiProjectRole = !empty(azureAiAccountName) && !empty(azureAiProjectName)
var assignOpenAiAccountRole = !empty(openAiAccountName)
var managedEnvironmentNetworkProperties = useNetworkLayer ? {
  workloadProfiles: [
    {
      name: 'Consumption'
      workloadProfileType: 'Consumption'
    }
  ]
  vnetConfiguration: union({
    infrastructureSubnetId: infrastructureSubnet.id
  }, internalManagedEnvironment ? {
    internal: true
  } : {})
} : {}
var commonTags = union(tags, {
  workload: 'email-assistant'
  hosting: 'azure-container-apps'
  managedBy: 'bicep'
})
var acrPullRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
var azureAiUserRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '53ca6127-db72-4b80-b1b0-d745d6d5456d')
var cognitiveServicesOpenAiUserRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-07-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: commonTags
  properties: {
    retentionInDays: logRetentionInDays
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: userAssignedIdentityName
  location: location
  tags: commonTags
}

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2024-05-01' = if (useNetworkLayer) {
  name: resolvedNetworkSecurityGroupName
  location: location
  tags: commonTags
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2025-05-01' = if (useNetworkLayer) {
  name: resolvedVirtualNetworkName
  location: location
  tags: commonTags
  properties: {
    addressSpace: {
      addressPrefixes: [
        virtualNetworkAddressPrefix
      ]
    }
  }
}

resource infrastructureSubnet 'Microsoft.Network/virtualNetworks/subnets@2025-05-01' = if (useNetworkLayer) {
  parent: virtualNetwork
  name: infrastructureSubnetName
  properties: {
    addressPrefix: infrastructureSubnetAddressPrefix
    networkSecurityGroup: {
      id: networkSecurityGroup.id
    }
    delegations: [
      {
        name: 'aca-environment-delegation'
        properties: {
          serviceName: 'Microsoft.App/environments'
        }
      }
    ]
  }
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' existing = if (useAcr) {
  name: containerRegistryName
}

resource azureAiAccount 'Microsoft.CognitiveServices/accounts@2026-03-01' existing = if (assignAzureAiProjectRole) {
  name: azureAiAccountName
}

resource azureAiProject 'Microsoft.CognitiveServices/accounts/projects@2026-03-01' existing = if (assignAzureAiProjectRole) {
  parent: azureAiAccount
  name: azureAiProjectName
}

resource openAiAccount 'Microsoft.CognitiveServices/accounts@2026-03-01' existing = if (assignOpenAiAccountRole) {
  name: openAiAccountName
}

resource managedEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: environmentName
  location: location
  tags: commonTags
  properties: union({
    zoneRedundant: zoneRedundant
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
  }, managedEnvironmentNetworkProperties)
}

resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (useAcr) {
  name: guid(containerRegistry.id, userAssignedIdentity.id, 'acrpull')
  scope: containerRegistry
  properties: {
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: acrPullRoleDefinitionId
  }
}

resource azureAiProjectRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (assignAzureAiProjectRole) {
  name: guid(azureAiProject.id, userAssignedIdentity.id, 'azure-ai-user')
  scope: azureAiProject
  properties: {
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: azureAiUserRoleDefinitionId
  }
}

resource openAiAccountRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (assignOpenAiAccountRole) {
  name: guid(openAiAccount.id, userAssignedIdentity.id, 'openai-user')
  scope: openAiAccount
  properties: {
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: cognitiveServicesOpenAiUserRoleDefinitionId
  }
}

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: containerAppName
  location: location
  tags: commonTags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentity.id}': {}
    }
  }
  properties: {
    environmentId: managedEnvironment.id
    configuration: {
      activeRevisionsMode: 'Single'
      maxInactiveRevisions: 2
      ingress: {
        external: ingressExternal
        allowInsecure: false
        targetPort: targetPort
        transport: ingressTransport
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      registries: useAcr ? [
        {
          server: '${containerRegistryName}.azurecr.io'
          identity: userAssignedIdentity.id
        }
      ] : []
    }
    template: {
      containers: [
        {
          name: 'email-assistant'
          image: containerImage
          env: [
            {
              name: 'AZURE_CLIENT_ID'
              value: userAssignedIdentity.properties.clientId
            }
            {
              name: 'AZURE_AI_PROJECT_ENDPOINT'
              value: azureAiProjectEndpoint
            }
            {
              name: 'OPENAI_CHAT_MODEL'
              value: openAiChatModel
            }
            {
              name: 'DEEPSEEK_CHAT_MODEL'
              value: deepseekChatModel
            }
            {
              name: 'KNOWLEDGE_BASE_AGENT_NAME'
              value: knowledgeBaseAgentName
            }
            {
              name: 'KNOWLEDGE_BASE_AGENT_VERSION'
              value: knowledgeBaseAgentVersion
            }
            {
              name: 'PORT'
              value: string(targetPort)
            }
          ]
          probes: [
            {
              type: 'Startup'
              httpGet: {
                path: '/health'
                port: targetPort
              }
              initialDelaySeconds: 5
              periodSeconds: 10
              timeoutSeconds: 5
              failureThreshold: 12
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/health'
                port: targetPort
              }
              initialDelaySeconds: 5
              periodSeconds: 10
              timeoutSeconds: 5
              failureThreshold: 3
            }
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: targetPort
              }
              initialDelaySeconds: 20
              periodSeconds: 20
              timeoutSeconds: 5
              failureThreshold: 3
            }
          ]
          resources: {
            cpu: cpuCores
            memory: memory
          }
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: [
          {
            name: 'http-scale'
            http: {
              metadata: {
                concurrentRequests: string(httpConcurrentRequests)
              }
            }
          }
        ]
      }
    }
  }
}

output containerAppName string = containerApp.name
output containerAppUrl string = 'https://${containerApp.properties.latestRevisionFqdn}'
output managedEnvironmentName string = managedEnvironment.name
output managedIdentityClientId string = userAssignedIdentity.properties.clientId
output managedIdentityPrincipalId string = userAssignedIdentity.properties.principalId
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name
output azureAiProjectRoleAssigned bool = assignAzureAiProjectRole
output openAiAccountRoleAssigned bool = assignOpenAiAccountRole
output virtualNetworkName string = useNetworkLayer ? virtualNetwork.name : ''
output infrastructureSubnetId string = useNetworkLayer ? infrastructureSubnet.id : ''
output networkSecurityGroupId string = useNetworkLayer ? networkSecurityGroup.id : ''
