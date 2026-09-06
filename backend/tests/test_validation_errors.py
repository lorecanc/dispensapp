"""C3-1 Red test: RequestValidationError must use {"detail","message"} string shape.

iOS decodes error bodies as [String: String]; FastAPI's default
RequestValidationError body {"detail": [{loc, msg, type}...]} (array)
loses the message -> generic "Errore del server (422)".
Trigger: POST /api/scan with non-numeric barcode violating ^\\d{8,14}$.
"""


def test_scan_invalid_barcode_returns_string_detail(client):
    resp = client.post("/api/scan", json={"barcode": "AB-123-CD"})
    assert resp.status_code == 422, f"expected 422, got {resp.status_code}: {resp.text}"
    body = resp.json()
    assert isinstance(body.get("detail"), str), (
        f"detail must be str (iOS [String:String] shape), got {type(body.get('detail')).__name__}: {body!r}"
    )
    assert isinstance(body.get("message"), str), (
        f"message key must be str, got body: {body!r}"
    )
