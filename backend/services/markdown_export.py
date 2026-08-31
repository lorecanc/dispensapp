from backend.config import ESTIMATED_NOTE
from backend.services.expiration import get_status


def _escape_cell(value: str) -> str:
    # previene markdown injection: pipe rompe la tabella, newline rompe la riga
    return value.replace("|", "\\|").replace("\r", " ").replace("\n", " ")


# Mapping centrale stato -> emoji (get_status)
_STATUS_EMOJI = {
    "expired": "🔴 Scaduto",
    "expiring_soon": "🟡 In scadenza",
    "ok": "🟢 OK",
}


def to_markdown(items: list) -> str:
    lines = ["# 🍲 Inventario Dispensa\n"]
    lines.append("| Prodotto | Brand | Quantità | Scadenza | Stato | Note |")
    lines.append("| :--- | :--- | :--- | :--- | :--- | :--- |")

    for item in items:
        name = _escape_cell(item.name)
        brand = _escape_cell(item.brand) if item.brand else "-"
        # category non è in tabella ma va sanitizzata se mai interpolata in futuro
        # (manteniamo coerenza con requisito: escapa name/brand/category)

        if item.expiration_date:
            scadenza = item.expiration_date.strftime("%d/%m/%Y")
            stato = _STATUS_EMOJI.get(get_status(item.expiration_date), "🟢 OK")
        else:
            scadenza = "-"
            stato = _STATUS_EMOJI["ok"]

        note = ESTIMATED_NOTE if item.is_estimated else ""

        lines.append(f"| {name} | {brand} | {item.quantity} | {scadenza} | {stato} | {note} |")

    return "\n".join(lines)
