# Contributing to Email Assistant

Check existing issues and pull requests before starting work.
Open an issue to discuss substantial changes to the API, workflow, or deployment.
Keep pull requests focused and describe the behavior they change.

## Set up

Use Python 3.11 or newer and install the development dependencies from the repository root:

```sh
python -m pip install -r requirements-dev.txt
```

See [README.md](README.md) for local API and Docker commands.
Use `.env.example` as the local configuration reference and keep credentials out of Git.
The tests mock workflow execution and do not require live Azure credentials.

## Verify changes

Run the application checks used by [CI](.github/workflows/ci.yml):

```sh
ruff check app tests main.py
ruff format --check app tests main.py
python -m compileall -q app tests main.py
pytest -v --tb=short
```

For deployment or infrastructure changes, explain the validation performed and any checks that could not run.
Do not run a production deployment as part of ordinary pull request verification.

## Submit a pull request

Explain the problem, the change, and any related issue.
List the checks run and their results.
Call out API contract or configuration changes and include examples when useful.
Remove credentials, customer email content, and other sensitive data from code, tests, logs, and screenshots.
