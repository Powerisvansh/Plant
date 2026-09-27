from __future__ import annotations


def test_plants_list_endpoint_returns_success_payload(client):
    response = client.get("/api/v1/plants")
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["success"] is True
    assert "items" in body["data"]
    assert "total" in body["data"]


def test_sources_endpoint_returns_known_catalog(client):
    response = client.get("/api/v1/sources")
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["success"] is True
    assert isinstance(body["data"], dict)
    assert "items" in body["data"]
    assert "total" in body["data"]


def test_symptoms_and_treatments_endpoints_are_available(client):
    for path in ("/api/v1/symptoms", "/api/v1/treatments", "/api/v1/medicines", "/api/v1/doctors"):
        response = client.get(path)
        assert response.status_code == 200, response.text
        assert response.json()["success"] is True
