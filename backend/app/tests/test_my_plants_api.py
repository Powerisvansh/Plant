from __future__ import annotations


def test_create_and_list_saved_plants(auth_client):
    user = auth_client(email="owner@example.test", full_name="Owner Person")

    response = user.client.post(
        "/api/v1/my-plants",
        headers=user.auth(),
        json={
            "nickname": "Mango Tree",
            "common_name": "Mango",
            "scientific_name_claimed": "Mangifera indica",
            "location_note": "Kitchen window",
            "is_potted": True,
            "notes": "Loves the morning sun",
        },
    )
    assert response.status_code == 201, response.text
    payload = response.json()["data"]
    assert payload["nickname"] == "Mango Tree"
    assert payload["user_id"] == str(user.user.id)

    listing = user.client.get("/api/v1/my-plants", headers=user.auth())
    assert listing.status_code == 200, listing.text
    items = listing.json()["data"]
    assert any(item["id"] == payload["id"] for item in items)


def test_user_cannot_read_another_users_saved_plant(auth_client):
    owner = auth_client(email="owner2@example.test", full_name="Owner Two")
    other = auth_client(email="other@example.test", full_name="Other Person")

    created = owner.client.post(
        "/api/v1/my-plants",
        headers=owner.auth(),
        json={
            "nickname": "Rose Bush",
            "common_name": "Rose",
            "scientific_name_claimed": "Rosa",
        },
    )
    plant_id = created.json()["data"]["id"]

    response = other.client.get(f"/api/v1/my-plants/{plant_id}", headers=other.auth())
    assert response.status_code == 404


def test_add_note_to_saved_plant(auth_client):
    user = auth_client(email="planner@example.test", full_name="Plant Planner")

    created = user.client.post(
        "/api/v1/my-plants",
        headers=user.auth(),
        json={
            "nickname": "Basil Pot",
            "common_name": "Basil",
            "scientific_name_claimed": "Ocimum basilicum",
        },
    )
    plant_id = created.json()["data"]["id"]

    note_response = user.client.post(
        f"/api/v1/my-plants/{plant_id}/notes",
        headers=user.auth(),
        json={"body": "Watered this morning", "tags": ["watering"]},
    )
    assert note_response.status_code == 201, note_response.text
    note = note_response.json()["data"]
    assert note["body"] == "Watered this morning"

    detail = user.client.get(f"/api/v1/my-plants/{plant_id}", headers=user.auth())
    assert detail.status_code == 200, detail.text
    assert any(item["body"] == "Watered this morning" for item in detail.json()["data"]["notes_history"])
