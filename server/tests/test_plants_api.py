from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_get_plants_returns_list():
    response = client.get("/api/v1/plants")
    assert response.status_code == 200
    data = response.json()
    assert "items" in data
    assert isinstance(data["items"], list)


def test_get_plant_by_id():
    response = client.get("/api/v1/plants/1")
    if response.status_code == 404:
        return
    assert response.status_code == 200
    payload = response.json()
    assert "id" in payload
    assert payload["id"] == 1


def test_search_plants():
    response = client.get("/api/v1/plants/search?q=neem")
    assert response.status_code == 200
    payload = response.json()
    assert "items" in payload
    assert isinstance(payload["items"], list)


def test_invalid_plant_id():
    response = client.get("/api/v1/plants/999999")
    assert response.status_code == 404


def test_empty_search():
    response = client.get("/api/v1/plants/search?q=")
    assert response.status_code == 422
