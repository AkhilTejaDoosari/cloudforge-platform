from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health_returns_ok():
    response = client.get("/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert "uptime_seconds" in body


def test_status_reports_backend_ok():
    response = client.get("/api/status")
    assert response.status_code == 200
    body = response.json()
    assert body["backend"] == "ok"
    # database may be "connected" or "disconnected" depending on environment,
    # but the field must always be present.
    assert body["database"] in ("connected", "disconnected")


def test_root_returns_service_info():
    response = client.get("/")
    assert response.status_code == 200
    assert response.json()["service"] == "cloudforge-backend"
