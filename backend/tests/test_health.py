def test_health_endpoint_returns_healthy(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "healthy"}


def test_root_endpoint_returns_running(client):
    response = client.get("/")
    assert response.status_code == 200
    assert response.json() == {"message": "Pharos API is running"}
