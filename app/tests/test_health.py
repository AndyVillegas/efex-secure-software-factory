def test_health_check(client):
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json()["status"] == "ok"


def test_payment_rejects_invalid_amount(client):
    response = client.post(
        "/payments",
        json={
            "source_clabe": "002010077777777771",
            "destination_clabe": "002010088888888881",
            "amount": -10.0,
            "concept": "invalid payment test",
        },
    )

    assert response.status_code == 200
    assert response.json()["status"] == "rejected"


def test_payment_accepts_valid_amount(client):
    response = client.post(
        "/payments",
        json={
            "source_clabe": "002010077777777771",
            "destination_clabe": "002010088888888881",
            "amount": 10.0,
            "concept": "valid payment test",
        },
    )

    assert response.status_code == 200
    assert response.json()["status"] == "accepted"


def test_debug_config_is_disabled(client):
    response = client.get("/debug/config")

    assert response.status_code == 404
    body = response.json()
    assert "api_secret" not in str(body)
    assert "secret" not in str(body).lower()


def test_customers_search_returns_empty_for_unknown_email(client):
    response = client.get("/customers/search", params={"email": "notexistent@fake.com"})

    assert response.status_code == 200
    assert response.json()["results"] == []
