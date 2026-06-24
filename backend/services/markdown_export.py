from datetime import date, timedelta

from backend.config import ESTIMATED_NOTE, EXPIRING_SOON_DAYS


def to_markdown(items: list) -> str:
    today = date.today()
    lines = ["# 🍲 Inventario Dispensa\n"]
    lines.append("| Prodotto | Brand | Quantità | Scadenza | Stato | Note |")
    lines.append("| :--- | :--- | :--- | :--- | :--- | :--- |")

    for item in items:
        name = item.name
        brand = item.brand or "-"

        if item.expiration_date:
            scadenza = item.expiration_date.strftime("%d/%m/%Y")
            if item.expiration_date < today:
                stato = "🔴 Scaduto"
            elif item.expiration_date <= today + timedelta(days=EXPIRING_SOON_DAYS):
                stato = "🟡 In scadenza"
            else:
                stato = "🟢 OK"
        else:
            scadenza = "-"
            stato = "🟢 OK"

        note = ESTIMATED_NOTE if item.is_estimated else ""

        lines.append(f"| {name} | {brand} | {item.quantity} | {scadenza} | {stato} | {note} |")

    return "\n".join(lines)
