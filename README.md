# Email Assistant

Email Assistant is a FastAPI service that processes incoming emails with a LangGraph workflow.

It classifies email priority, analyzes risk/context, recommends actions, and drafts a response message.

## Features

- FastAPI HTTP API
- LangGraph orchestration workflow
- Structured input/output validation with Pydantic
- Azure AI model integration
- Automated API tests with pytest

## Project Structure

```text
email-assistant/
  app/
    api/
      routes/
        email.py
      router.py
    core/
      settings.py
    models/
      email.py
    prompts/
      email_prompts.py
    services/
      email_workflow.py
  tests/
    test_api.py
  langgraph.json
  main.py
  requirements.txt
  requirements-dev.txt
```

## Requirements

- Python 3.11+
- Azure credentials available for runtime workflow calls

Install dependencies:

```powershell
python -m pip install -r requirements.txt
```

Install development dependencies (tests, lint, security checks):

```powershell
python -m pip install -r requirements-dev.txt
```

## Package With Docker

Build the image locally from the repo root:

```powershell
docker build -t email-assistant:local .
```

Run it locally:

```powershell
docker run --rm -p 8000:8000 email-assistant:local
```

## Run The API

Option 1 (direct):

```powershell
python main.py
```

Option 2 (recommended uvicorn CLI):

```powershell
python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

## API Endpoints

- `GET /health`
  - Returns service health.

- `POST /api/v1/email/process`
  - Processes an email payload.

### Example Request

```json
{
  "subject": "Login issue on portal",
  "title": "Unable to access account after password reset",
  "content": "The user reports that after resetting their password, they still cannot log in to the system."
}
```

### Example Response

```json
{
  "summary": "User cannot log in after reset and needs support.",
  "classification": "Urgent",
  "analysis": "Authentication issue blocks access and should be escalated quickly.",
  "actions": ["escalate_to_on_call", "notify_team_channel", "flag_for_review"],
  "message": "Thanks for reporting this. We are investigating immediately and will update you shortly."
}
```


## Azure Deploy Flow

The repo includes three standalone deployment commands:

1. preflight validation
2. what-if preview
3. deployment

PowerShell:

```powershell
./infra/deploy.ps1 -ResourceGroup rg-sandbox -Action validate
./infra/deploy.ps1 -ResourceGroup rg-sandbox -Action what-if
./infra/deploy.ps1 -ResourceGroup rg-sandbox -Action deploy
```

Optional subscription override:

```powershell
./infra/deploy.ps1 -ResourceGroup rg-sandbox -SubscriptionId b3ba82f5-6f28-48e9-ad64-0bad3f15e101 -Action validate
```

The script uses these Azure CLI commands under the hood:

```powershell
az deployment group validate --resource-group <rg> --template-file infra/main.bicep --parameters infra/dev.bicepparam
az deployment group what-if --resource-group <rg> --template-file infra/main.bicep --parameters infra/dev.bicepparam
az deployment group create --resource-group <rg> --template-file infra/main.bicep --parameters infra/dev.bicepparam
```

Prerequisites:

- `az login` completed successfully
- target resource group already exists
- `infra/dev.bicepparam` filled with real image and Azure AI resource values
- the container image is already pushed and reachable by Azure Container Apps

In VS Code you can also run the `Azure: Validate`, `Azure: What-If`, and `Azure: Deploy` tasks from the Command Palette or Tasks runner.

## GitHub Actions

The repo now includes two workflows:

- `.github/workflows/ci.yml`: installs development dependencies, lints (`ruff`), compiles Python, imports the FastAPI app, runs `pytest`, runs dependency audit (`pip-audit`), and builds the Docker image.
- `.github/workflows/deploy.yml`: logs into Azure, builds and pushes the image to ACR, runs `validate`, runs `what-if`, and then deploys the Bicep template.

Required GitHub repository secrets:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`

Required GitHub repository variables:

- `AZURE_RESOURCE_GROUP`
- `AZURE_CONTAINER_REGISTRY_NAME`
- `AZURE_CONTAINER_REGISTRY_LOGIN_SERVER`
- `IMAGE_REPOSITORY` (optional, defaults to `email-assistant` in the workflow)

Deployment trigger and approvals:

- The deploy workflow is manual-only (`workflow_dispatch`).
- The deploy job targets the GitHub Environment named `production`.
- Configure required reviewers in repository settings for the `production` environment to enforce manual approval before deployment runs.
- `resource_group` and `image_repository` can be overridden when launching the workflow manually.

Registry discovery behavior:

- `AZURE_CONTAINER_REGISTRY_NAME` and `AZURE_CONTAINER_REGISTRY_LOGIN_SERVER` are required.
- The deploy workflow fails fast when either value is missing to avoid deploying to the wrong registry.

The deploy workflow expects Azure federated credentials or another OIDC trust configuration for `azure/login@v2`.

The deployment references these Microsoft samples and docs:

- https://learn.microsoft.com/azure/container-apps/github-actions
- https://learn.microsoft.com/azure/container-apps/migrate-heroku#7---set-up-cicd
- https://learn.microsoft.com/azure/container-apps/vnet-custom

## LangGraph Config

The graph export is configured in `langgraph.json`:

- `email_assistant_graph`: `./app/services/email_workflow.py:graph`

## Notes

- Unit tests mock workflow execution to stay fast and independent from Azure runtime services.
- Real workflow execution requires valid Azure environment and permissions.

## Local Env Example

Use `.env.example` as the baseline environment file for local runs and containers.
