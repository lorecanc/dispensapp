# Red test (T2): i modelli Out devono serializzare i datetime UTC naive con
# suffisso timezone (+00:00), altrimenti il decoder iOS non li accetta.
# Nessun DB richiesto: si costruiscono i modelli Out direttamente.
import json
from datetime import datetime

import pytest

from backend.schemas import (
    ConsumptionEventOut,
    InventoryOut,
    InviteOut,
    MemberOut,
    PantryOut,
    ShoppingListItemOut,
    ShoppingListOut,
)

NAIVE_UTC = datetime(2026, 9, 6, 10, 2, 0)
EXPECTED = "2026-09-06T10:02:00+00:00"


def _inventory_out():
    return InventoryOut(id=1, name="Latte", created_at=NAIVE_UTC)


def _consumption_event_out():
    return ConsumptionEventOut(
        id=1, pantry_id=1, name_snapshot="Latte", delta=1, created_at=NAIVE_UTC
    )


def _pantry_out():
    return PantryOut(id=1, name="Dispensa", created_at=NAIVE_UTC)


def _invite_out():
    return InviteOut(
        id=1,
        pantry_id=1,
        token="t0k3n",
        status="pending",
        expires_at=NAIVE_UTC,
        created_at=NAIVE_UTC,
    )


def _member_out():
    return MemberOut(pantry_id=1, role="member", joined_at=NAIVE_UTC)


def _shopping_list_item_out():
    return ShoppingListItemOut(
        id=1, shopping_list_id=1, name="Pane", quantity=1, checked=False, created_at=NAIVE_UTC
    )


def _shopping_list_out():
    return ShoppingListOut(id=1, pantry_id=1, name="Spesa", created_at=NAIVE_UTC)


@pytest.mark.parametrize(
    "model_factory,fields",
    [
        (_inventory_out, ["created_at"]),
        (_consumption_event_out, ["created_at"]),
        (_pantry_out, ["created_at"]),
        (_invite_out, ["expires_at", "created_at"]),
        (_member_out, ["joined_at"]),
        (_shopping_list_item_out, ["created_at"]),
        (_shopping_list_out, ["created_at"]),
    ],
    ids=[
        "InventoryOut.created_at",
        "ConsumptionEventOut.created_at",
        "PantryOut.created_at",
        "InviteOut.expires_at+created_at",
        "MemberOut.joined_at",
        "ShoppingListItemOut.created_at",
        "ShoppingListOut.created_at",
    ],
)
def test_out_models_serialize_naive_utc_with_timezone_suffix(model_factory, fields):
    payload = json.loads(model_factory().model_dump_json())
    for field in fields:
        actual = payload[field]
        assert actual == EXPECTED, (
            f"{model_factory.__name__}.{field} serializzato senza suffisso "
            f"timezone: {actual!r} (atteso {EXPECTED!r})"
        )


# Il return_type elaborato di UtcDatetime (schemas.py) esiste solo per
# preservare format: date-time nello schema OpenAPI: senza questo test,
# un ritorno a plain str sarebbe invisibile.
@pytest.mark.parametrize(
    "model,fields",
    [
        (InventoryOut, ["created_at"]),
        (ConsumptionEventOut, ["created_at"]),
        (PantryOut, ["created_at"]),
        (InviteOut, ["expires_at", "created_at"]),
        (MemberOut, ["joined_at"]),
        (ShoppingListItemOut, ["created_at"]),
        (ShoppingListOut, ["created_at"]),
    ],
    ids=[
        "InventoryOut.created_at",
        "ConsumptionEventOut.created_at",
        "PantryOut.created_at",
        "InviteOut.expires_at+created_at",
        "MemberOut.joined_at",
        "ShoppingListItemOut.created_at",
        "ShoppingListOut.created_at",
    ],
)
def test_serialization_schema_keeps_date_time_format(model, fields):
    props = model.model_json_schema(mode="serialization")["properties"]
    for field in fields:
        prop = props[field]
        assert prop["type"] == "string", f"{model.__name__}.{field}: {prop!r}"
        assert prop["format"] == "date-time", f"{model.__name__}.{field}: {prop!r}"
