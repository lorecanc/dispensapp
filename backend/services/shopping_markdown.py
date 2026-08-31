def _escape(value: str) -> str:
    # come T1: previene markdown injection e rottura righe
    return value.replace("|", "\\|").replace("\r", " ").replace("\n", " ")


def to_shopping_markdown(shopping_list, items: list) -> str:
    """Genera markdown per shopping list raggruppata per comparto.

    Requisiti:
    - per comparto (frigo/cantina/dispensa) raggruppa items
    - checklist `- [ ]` / `- [x]` per checked
    - include quantità
    - escape pipe/newline come markdown_export
    """
    name = _escape(shopping_list.name) if shopping_list and shopping_list.name else "Spesa"
    lines = [f"# 🛒 {name}", ""]

    if not items:
        lines.append("_Nessun articolo_")
        return "\n".join(lines) + "\n"

    # raggruppamento per comparto normalizzato
    groups: dict[str, list] = {"frigo": [], "cantina": [], "dispensa": []}
    altro: list = []
    for it in items:
        raw = getattr(it, "compartment", None)
        comp = (raw or "").strip().lower()
        if comp in groups:
            groups[comp].append(it)
        elif comp == "":
            # senza comparto -> dispensa (default)
            groups["dispensa"].append(it)
        else:
            altro.append(it)

    labels = {
        "frigo": "## 🧊 Frigo",
        "cantina": "## 🍷 Cantina",
        "dispensa": "## 🏠 Dispensa",
    }

    for key in ("frigo", "cantina", "dispensa"):
        lst = groups[key]
        if not lst:
            continue
        lines.append(labels[key])
        lines.append("")
        for it in lst:
            box = "x" if getattr(it, "checked", False) else " "
            item_name = _escape(it.name)
            qty = getattr(it, "quantity", 1)
            lines.append(f"- [{box}] {item_name} x{qty}")
        lines.append("")

    if altro:
        lines.append("## 📦 Altro")
        lines.append("")
        for it in altro:
            box = "x" if getattr(it, "checked", False) else " "
            item_name = _escape(it.name)
            qty = getattr(it, "quantity", 1)
            lines.append(f"- [{box}] {item_name} x{qty}")
        lines.append("")

    return "\n".join(lines).strip() + "\n"
