from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)


def test_health_check():
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json()["status"] == "ok"


def test_payment_rejects_invalid_amount():
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


def test_payment_accepts_valid_amount():
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