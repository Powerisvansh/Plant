from __future__ import annotations

import io

from PIL import Image


def test_diagnosis_upload_creates_record_and_stored_file(auth_client):
    image = io.BytesIO()
    Image.new("RGB", (160, 160), color="green").save(image, format="PNG")
    image.seek(0)

    response = auth_client().client.post(
        "/api/v1/diagnosis",
        files={"file": ("plant.png", image, "image/png")},
        data={"notes": "Test upload"},
        headers=auth_client().auth(),
    )

    assert response.status_code == 201, response.text
    body = response.json()
    assert body["success"] is True
    data = body["data"]
    assert data["status"] == "PENDING"
    assert data["notes"] == "Test upload"
    assert data["image"]["mime_type"] == "image/png"
    assert data["image"]["storage_key"].endswith(".png")


def test_diagnosis_upload_rejects_wrong_mime_type(auth_client):
    payload = io.BytesIO(b"not an image")

    response = auth_client().client.post(
        "/api/v1/diagnosis",
        files={"file": ("bad.txt", payload, "text/plain")},
        headers=auth_client().auth(),
    )

    assert response.status_code in (400, 415)
    body = response.json()
    assert body["success"] is False


def test_diagnosis_history_lists_current_users_records(auth_client):
    user = auth_client()
    image = io.BytesIO()
    Image.new("RGB", (160, 160), color="blue").save(image, format="PNG")
    image.seek(0)

    create = user.client.post(
        "/api/v1/diagnosis",
        files={"file": ("leaf.png", image, "image/png")},
        data={"notes": "history test"},
        headers=user.auth(),
    )
    assert create.status_code == 201, create.text

    list_response = user.client.get("/api/v1/diagnosis", headers=user.auth())
    assert list_response.status_code == 200, list_response.text
    body = list_response.json()
    assert body["success"] is True
    assert isinstance(body["data"], list)
    assert any(item["notes"] == "history test" for item in body["data"])
