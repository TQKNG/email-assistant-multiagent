# Changelog

All notable changes to this project are documented in this file.

## [1.0.0] - 2026-04-21

### Added

- FastAPI app entrypoint in main.py with health endpoint.
- API router and email processing route:
  - GET /health
  - POST /api/v1/email/process
- Modular project package layout under app/:
  - api, core, models, prompts, services
- Centralized settings module for Azure model/agent configuration.
- Dedicated prompt module for orchestration, classification, analysis, and reply prompts.
- Typed Pydantic models for input/output and workflow tool payloads.
- Endpoint test suite with pytest and FastAPI TestClient.
- requirements.txt with pinned runtime and test dependencies.

### Changed

- Refactored monolithic workflow logic into app/services/email_workflow.py.
- Updated langgraph.json graph export path to:
  - ./app/services/email_workflow.py:graph
- Updated API route to lazy-load workflow runner to avoid import-time Azure dependency issues during test collection.

### Fixed

- Resolved pytest collection failure caused by eager Azure tracing imports by using lazy workflow import in route layer.
