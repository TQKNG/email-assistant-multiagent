from fastapi.testclient import TestClient

import app.api.routes.email as email_route_module
from main import app


def test_health_endpoint_returns_ok() -> None:
    client = TestClient(app)
    response = client.get('/health')

    assert response.status_code == 200
    assert response.json() == {'status': 'ok'}


def test_process_email_endpoint_uses_workflow_runner(monkeypatch) -> None:
    def fake_runner(_: dict) -> dict:
        return {
            'summary': 'Synthetic summary',
            'classification': 'Normal',
            'analysis': 'Synthetic analysis',
            'actions': ['route_to_inbox_queue'],
            'message': 'Synthetic reply',
        }

    monkeypatch.setattr(email_route_module, 'get_workflow_runner', lambda: fake_runner)

    client = TestClient(app)
    response = client.post(
        '/api/v1/email/process',
        json={
            'subject': 'Test subject',
            'title': 'Test title',
            'content': 'Test content',
        },
    )

    assert response.status_code == 200
    assert response.json()['classification'] == 'Normal'
    assert response.json()['actions'] == ['route_to_inbox_queue']
