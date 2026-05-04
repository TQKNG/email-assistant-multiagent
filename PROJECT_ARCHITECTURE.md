# Project Architecture Blueprint — Email Assistant

## 1. Architectural Overview

The Email Assistant is a **Python/FastAPI** microservice that exposes a single REST endpoint for email processing. Behind the API, all intelligence is handled by a **LangGraph multi-agent workflow** that orchestrates three specialist AI agents (Orchestrator, KnowledgeBase, Synthesizer) and three function-calling tools against Azure AI Foundry models. The system is packaged as a Docker container and deployed to **Azure Container Apps** via Bicep IaC.

### Guiding Principles

- **Single Responsibility** — each graph node owns one concern: classify → analyse → look up template → synthesize reply.
- **Strict I/O contracts** — Pydantic v2 models with `extra="forbid"` enforce boundaries at the HTTP layer and inside the graph.
- **Managed-identity security** — the container never stores credentials; Azure `DefaultAzureCredential` is used throughout.
- **Declarative workflow** — the graph topology is expressed as a compiled `StateGraph`; routing logic is isolated in a single `should_continue` function.

---

## 2. Architecture Visualization

### 2.1 Component Diagram (C4 Level 2)

```
┌──────────────────────────────────────────────────────────┐
│                   Azure Container Apps                    │
│                                                          │
│  ┌────────────────────────────────────────────────────┐  │
│  │              Email Assistant Container             │  │
│  │                                                    │  │
│  │  ┌─────────────┐     ┌──────────────────────────┐ │  │
│  │  │  FastAPI     │────▶│   LangGraph Workflow     │ │  │
│  │  │  (main.py)  │     │  (email_workflow.py)     │ │  │
│  │  └─────────────┘     └──────────────────────────┘ │  │
│  └────────────────────────────────────────────────────┘  │
│                           │                              │
│       Log Analytics       │  Managed Identity            │
│       Workspace ◀─────────┤  (UAMI)                     │
└───────────────────────────┼──────────────────────────────┘
                            │
              ┌─────────────▼──────────────┐
              │    Azure AI Foundry         │
              │  • GPT-4o-mini (OpenAI)    │
              │  • DeepSeek-R1             │
              │  • knowledge-base Agent    │
              └────────────────────────────┘
```

### 2.2 LangGraph Workflow — Node / Edge Diagram

```
START
  │
  ▼
┌──────────────┐   has tool_calls?   ┌────────────┐
│ Orchestrator │ ─────── yes ──────▶ │   tools    │
│  (GPT-4o-m) │ ◀──────────────────  │ (ToolNode) │
└──────────────┘                      └────────────┘
  │ no tool_calls
  ▼
┌──────────────────┐
│ KnowledgeBaseNode│  (Azure AI Agent — knowledge-base)
└──────────────────┘
  │
  ▼
┌──────────────┐
│  Synthesizer │  (DeepSeek-R1 for reply drafting)
└──────────────┘
  │
  ▼
 END
```

### 2.3 Request / Response Data Flow

```
HTTP POST /api/v1/email/process
        │
        ▼
  InputState (Pydantic)
  subject | title | content
        │
        ▼
  run_email_workflow()
        │
        ├─ Orchestrator → classify_and_summarize (tool)
        │                 analyze_email_content  (tool, parallel)
        │                 get_recommended_actions(tool, parallel)
        │
        ├─ KnowledgeBaseNode → Azure AI Agent → template text
        │
        └─ Synthesizer → DeepSeek-R1 reply draft
        │
        ▼
  OutputState (Pydantic)
  summary | classification | analysis | actions | message
        │
        ▼
HTTP 200 JSON
```

---

## 3. Architectural Layers and Dependencies

| Layer | Module(s) | Responsibility |
|-------|-----------|----------------|
| **Presentation** | `main.py`, `app/api/` | FastAPI app, routing, HTTP serialization |
| **Domain Models** | `app/models/email.py` | Pydantic I/O contracts, LangGraph `TypedDict` state |
| **Workflow / Agents** | `app/services/email_workflow.py` | LangGraph graph, agent nodes, tools, conditional routing |
| **Prompts** | `app/prompts/email_prompts.py` | System prompt strings; isolated for independent tuning |
| **Configuration** | `app/core/settings.py` | Environment variable resolution; single source of truth |
| **Infrastructure** | `infra/` | Bicep IaC, deploy script |

Dependency rule: layers only import **downward**. The API layer never imports from services directly (it uses a late-bound `get_workflow_runner()` factory to enable test-level monkeypatching without importing heavy ML dependencies at module load time).

---

## 4. Core Architectural Components

### 4.1 API Layer (`app/api/`)

- **`router.py`** — aggregates sub-routers via `APIRouter`; sole integration point for adding future routes.
- **`routes/email.py`** — defines `POST /api/v1/email/process`. Uses a factory function (`get_workflow_runner`) for lazy import of the workflow, keeping startup fast and tests isolated.
- Error handling: all workflow exceptions are caught and re-raised as `HTTP 500` with the original message preserved.

### 4.2 Domain Models (`app/models/email.py`)

| Model | Purpose |
|-------|---------|
| `InputState` | Validated request body (subject, title, content) |
| `OutputState` | Validated response (summary, classification, analysis, actions, message) |
| `EmailState` | LangGraph `TypedDict` for shared mutable state across nodes |
| `ClassifyResult` | Structured output contract for the classifier tool |
| `AnalysisResult` | Structured output contract for the analyser tool |
| `TemplateResult` | Structured output contract for knowledge-base result |

All Pydantic models use `extra="forbid"` and non-empty validators on text fields.

### 4.3 LangGraph Workflow (`app/services/email_workflow.py`)

The workflow is a compiled `StateGraph[EmailState]` with four nodes:

| Node | Model | Role |
|------|-------|------|
| `Orchestrator` | GPT-4o-mini + tool binding | Drives tool calls in the correct sequence |
| `tools` | `ToolNode` (LangGraph prebuilt) | Executes whichever tools the Orchestrator requested |
| `KnowledgeBaseNode` | Azure AI Agent (`knowledge-base`) | Retrieves a reply template from a managed knowledge base |
| `Synthesizer` | DeepSeek-R1 | Assembles all results and drafts the final reply |

Routing: `should_continue` is the sole conditional edge — it checks whether the last `AIMessage` contains `tool_calls`; if yes it loops back through `tools → Orchestrator`; if no it proceeds to `KnowledgeBaseNode`.

**Tool functions** (decorated with `@tool`):

| Tool | Returns |
|------|---------|
| `classify_and_summarize` | `ClassifyResult` JSON — label + summary |
| `analyze_email_content` | `AnalysisResult` JSON — risk signals + handling guidance |
| `get_recommended_actions` | JSON list of action strings keyed on classification |

### 4.4 Prompts (`app/prompts/email_prompts.py`)

Four system prompt constants: `ORCHESTRATOR_SYSTEM`, `CLASSIFY_SYSTEM`, `ANALYZER_SYSTEM`, `REPLY_SYSTEM`. Keeping prompts as module-level strings (not embedded in node functions) allows independent review and tuning without touching workflow logic.

### 4.5 Configuration (`app/core/settings.py`)

All configuration is pulled from environment variables with safe defaults:

| Variable | Default |
|----------|---------|
| `AZURE_AI_PROJECT_ENDPOINT` | langchain-academy endpoint |
| `OPENAI_CHAT_MODEL` | `gpt-4o-mini` |
| `DEEPSEEK_CHAT_MODEL` | `DeepSeek-R1` |
| `KNOWLEDGE_BASE_AGENT_NAME` | `knowledge-base` |
| `KNOWLEDGE_BASE_AGENT_VERSION` | `latest` |

---

## 5. Data Architecture

### 5.1 State Flow Through the Graph

```
EmailState (mutable TypedDict)
  ├─ messages: list[BaseMessage]   ← append-only via add_messages reducer
  ├─ subject / title / content     ← set at start, read-only thereafter
  ├─ summary / classification      ← populated by classify_and_summarize tool result
  ├─ analysis                      ← populated by analyze_email_content tool result
  ├─ email_template                ← populated by KnowledgeBaseNode
  ├─ actions: list[str]            ← populated by get_recommended_actions tool result
  └─ final_message                 ← populated by Synthesizer
```

The `_extract_tool_results` helper parses `ToolMessage` payloads from the message list and maps them back to their originating tool by call ID — this avoids threading individual fields through nodes and keeps the graph state minimal.

### 5.2 Data Validation Pattern

Input is validated at two boundaries:
1. **HTTP boundary** — FastAPI + Pydantic validates `InputState` before the workflow is invoked.
2. **Workflow boundary** — `run_email_workflow` re-validates with `InputState.model_validate` and produces output via `OutputState.model_validate`, ensuring internal workflow state does not leak to the caller.

---

## 6. Cross-Cutting Concerns

### 6.1 Authentication & Authorization

- `DefaultAzureCredential` (from `azure-identity`) is used for all Azure service calls — no stored secrets.
- The deployed container runs under a **User-Assigned Managed Identity** (UAMI) granted:
  - `Azure AI User` role at the AI Foundry project scope (when `azureAiAccountName` + `azureAiProjectName` are set).
  - `Cognitive Services OpenAI User` role at the OpenAI account scope (when `openAiAccountName` is set).
  - `AcrPull` role when pulling from a private Azure Container Registry.

### 6.2 Error Handling

- HTTP errors: all exceptions in the route handler are caught and surfaced as `HTTP 500` with the exception detail.
- Workflow errors: `Synthesizer` validates that all required fields are present before proceeding; `KnowledgeBaseNode` validates classification/summary from prior tool results; both raise `ValueError` with descriptive messages.
- MCP approval flow: `KnowledgeBaseNode` handles the `mcp_approval` pending type by automatically re-invoking the agent with `{"approve": true}`.

### 6.3 Observability

- `azure-monitor-opentelemetry` and `opentelemetry-sdk` are declared as runtime dependencies, enabling Azure Monitor integration.
- `PYTHONDONTWRITEBYTECODE` and `PYTHONUNBUFFERED` are set in the container to ensure logs flush immediately.
- Log Analytics Workspace provisioned via Bicep; the Container Apps environment streams logs to it.

### 6.4 Validation

- Pydantic `field_validator` with `mode="before"` (implicit) strips whitespace and rejects empty strings on all text fields in `InputState` and `OutputState`.
- `extra="forbid"` on all Pydantic models rejects unexpected fields at both API and tool-result boundaries.

### 6.5 Configuration Management

- All secrets and endpoints arrive via environment variables injected by Azure Container Apps at runtime.
- Bicep parameters (in `infra/dev.bicepparam`) provide environment-specific overrides at deploy time.
- The `.env` file path is referenced in `langgraph.json` for local development only.

---

## 7. Technology Stack

| Category | Technology | Version Constraint |
|----------|-----------|-------------------|
| Runtime | Python | 3.11 |
| Web framework | FastAPI | `^0.116` |
| ASGI server | Uvicorn | `^0.35` |
| Data validation | Pydantic v2 | `^2.11` |
| AI orchestration | LangGraph | `^0.6` |
| LLM integration | LangChain Azure AI | `^1.2` |
| Azure identity | azure-identity | `^1.23` |
| Observability | azure-monitor-opentelemetry | `^1.8` |
| Containerisation | Docker (multi-stage) | python:3.11-slim base |
| IaC | Azure Bicep | — |
| Hosting | Azure Container Apps | — |
| AI platform | Azure AI Foundry | — |

---

## 8. Deployment Architecture

### 8.1 Container Build (Multi-Stage Dockerfile)

```
Stage 1 — build
  python:3.11-slim
  └─ uv + venv → install requirements.txt → /opt/venv

Stage 2 — runtime
  python:3.11-slim
  └─ copy /opt/venv from build stage
     copy app/, main.py, langgraph.json
     create non-root user 'appuser'
     EXPOSE 8000
     CMD: uvicorn main:app --host 0.0.0.0 --port 8000
```

### 8.2 Azure Infrastructure (Bicep)

```
Resource Group
  ├─ Log Analytics Workspace
  ├─ User-Assigned Managed Identity
  ├─ Container Apps Environment
  │    └─ optional: VNet + NSG + subnet delegation
  ├─ Container App
  │    ├─ ingress: external HTTP, port 8000
  │    ├─ scale: min 1 / max 3 replicas (HTTP concurrent trigger)
  │    ├─ env vars: AZURE_AI_PROJECT_ENDPOINT, model names, agent config
  │    └─ identity: UAMI
  └─ RBAC assignments (conditional)
       ├─ AcrPull → Container Registry
       ├─ Azure AI User → AI Foundry project
       └─ Cognitive Services OpenAI User → OpenAI account
```

---

## 9. Testing Architecture

- **Framework**: `pytest` + FastAPI `TestClient`.
- **Strategy**: the `get_workflow_runner` factory in the route is monkeypatched in tests, preventing any Azure / LLM calls during unit tests.
- **Coverage**:
  - `test_health_endpoint_returns_ok` — verifies the `/health` endpoint.
  - `test_process_email_endpoint_uses_workflow_runner` — verifies the full HTTP request/response cycle with a fake runner returning a controlled `OutputState`.
- **Pattern**: tests operate at the HTTP boundary only; internal workflow nodes are not unit-tested directly (they require live Azure credentials).

---

## 10. Extension and Evolution Patterns

### Adding a New Route

1. Create `app/api/routes/<domain>.py` with a new `APIRouter`.
2. Include it in `app/api/router.py` via `api_router.include_router(...)`.
3. Add corresponding Pydantic models to `app/models/`.

### Adding a New LangGraph Node

1. Write a node function `def my_node(state: EmailState) -> dict` in `email_workflow.py`.
2. Register it: `builder.add_node("MyNode", my_node)`.
3. Wire edges: `builder.add_edge("PreviousNode", "MyNode")`.
4. Update `EmailState` TypedDict if new fields are needed.

### Adding a New Tool

1. Decorate a function with `@tool` and add it to `WORKER_TOOLS`.
2. Update `ORCHESTRATOR_SYSTEM` prompt to instruct the orchestrator when to call it.
3. Parse results in `_extract_tool_results` / `synthesizer_node` as needed.

### Swapping a Model

Update the relevant environment variable (`OPENAI_CHAT_MODEL`, `DEEPSEEK_CHAT_MODEL`) in `infra/dev.bicepparam` (or at the Container App level) — no code changes required.

### Adding a New Classification Label

1. Extend the `ClassificationLabel` `Literal` in `app/models/email.py`.
2. Update `CLASSIFY_SYSTEM` prompt.
3. Update the `action_map` dict in `get_recommended_actions`.
4. Update `REPLY_SYSTEM` prompt for the new label.

---

## 11. Architectural Decision Records

### ADR-001: LangGraph over a Custom Orchestration Loop

**Context**: The workflow requires sequential + conditional tool invocation with shared state.  
**Decision**: Use LangGraph `StateGraph` with a compiled graph and `add_messages` reducer.  
**Rationale**: Eliminates manual message list management; built-in `ToolNode` handles parallel tool calls; graph topology is declarative and inspectable.  
**Trade-offs**: LangGraph adds dependency weight; graph compilation happens at module import time.

### ADR-002: Lazy Import of Workflow in Route Handler

**Context**: Importing `email_workflow` at module level would trigger LLM client instantiation and Azure credential resolution on every test run.  
**Decision**: The route uses `get_workflow_runner()` factory with a local import.  
**Rationale**: Allows `monkeypatch` in tests to replace the runner without Azure credentials.  
**Trade-offs**: Slightly non-idiomatic; import cost is deferred to first request.

### ADR-003: Separate Models for Each AI Output

**Context**: Multiple tools return structured JSON; the graph needs to parse and pass results downstream.  
**Decision**: Dedicated Pydantic models (`ClassifyResult`, `AnalysisResult`, `TemplateResult`) with `extra="forbid"`.  
**Rationale**: Catches hallucinated fields from LLM-structured output early; provides clear contracts for downstream nodes.

### ADR-004: Multi-Stage Docker Build with uv

**Context**: Standard `pip install` in a single stage leads to large final images with build tools.  
**Decision**: Use a `build` stage with `uv` to install into `/opt/venv`, copy only the venv into the `runtime` stage.  
**Rationale**: Smaller production image; `uv` is significantly faster than pip for dependency resolution.

### ADR-005: User-Assigned Managed Identity for All Azure Access

**Context**: The container needs to call Azure AI Foundry APIs without storing credentials.  
**Decision**: Provision a UAMI and assign least-privilege RBAC roles via Bicep.  
**Rationale**: No secret rotation; identity is portable across redeployments; aligns with Azure security best practices.

---

## 12. Architecture Governance

- **Type safety**: Pydantic v2 with `extra="forbid"` acts as a compile-time-like contract at runtime.
- **Dependency direction**: enforced by convention — lower layers (models, prompts, settings) have no upward imports.
- **Infrastructure as code**: all Azure resources are declared in `infra/main.bicep`; no manual portal changes are expected.
- **Deployment validation**: `infra/deploy.ps1` supports `validate` and `what-if` actions (exposed as VS Code tasks) to catch Bicep errors before deployment.
- **Prompt management**: system prompts live exclusively in `app/prompts/email_prompts.py` — changes to LLM behavior require modifications only to that file.
