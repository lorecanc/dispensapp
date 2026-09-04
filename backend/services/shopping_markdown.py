from backend.config import SUPER_MARKET_COMPARTMENTS

# Icone per headings supermercato
_COMPARTMENT_ICONS: dict[str, str] = {
    "Ortofrutta": "🥬",
    "Latticini e Uova": "🥛",
    "Salumi e Formaggi": "🧀",
    "Carne e Pesce": "🥩",
    "Surgelati": "🧊",
    "Dispensa Secca": "🥫",
    "Bevande": "🥤",
    "Cantina": "🍷",
    "Forno e Panetteria": "🥖",
    "Igiene e Casa": "🧹",
}

# Mappatura legacy frigo/cantina/dispensa/altro -> nuovi comparti (compatibilità, come iOS normalized)
_LEGACY_MAP: dict[str, str] = {
    "frigo": "Latticini e Uova",
    "cantina": "Cantina",
    "dispensa": "Dispensa Secca",
    "altro": "Dispensa Secca",
}


def _escape(value: str) -> str:
    # come T1: previene markdown injection e rottura righe
    return value.replace("|", "\\|").replace("\r", " ").replace("\n", " ")


def _normalize_compartment(raw: str | None) -> str:
    if not raw or not raw.strip():
        return "Dispensa Secca"
    stripped = raw.strip()
    low = stripped.lower()
    if low in _LEGACY_MAP:
        return _LEGACY_MAP[low]
    # match case-insensitive tra comparti noti
    for c in SUPER_MARKET_COMPARTMENTS:
        if c.lower() == low:
            return c
    # se contiene già canonical con diversa capitalizzazione, ritorna canonical
    return stripped


def to_shopping_markdown(shopping_list, items: list) -> str:
    """Genera markdown per shopping list raggruppata per comparto supermercato.

    - raggruppa per SUPER_MARKET_COMPARTMENTS usando COMPARTMENT_MAP ordinamento
    - headings `## 🥬 Ortofrutta` etc.
    - sezioni collassabili via <details>
    - checklist `- [ ]` / `- [x]` per checked
    - include quantità
    - escape pipe/newline
    """
    name = _escape(shopping_list.name) if shopping_list and shopping_list.name else "Spesa"
    lines = [f"# 🛒 {name}", ""]

    if not items:
        lines.append("_Nessun articolo_")
        return "\n".join(lines) + "\n"

    # raggruppamento per comparto supermercato
    groups: dict[str, list] = {c: [] for c in SUPER_MARKET_COMPARTMENTS}
    altro: list = []
    for it in items:
        raw = getattr(it, "compartment", None)
        comp = _normalize_compartment(raw)
        if comp in groups:
            groups[comp].append(it)
        else:
            altro.append(it)

    for comp in SUPER_MARKET_COMPARTMENTS:
        lst = groups[comp]
        if not lst:
            continue
        icon = _COMPARTMENT_ICONS.get(comp, "📦")
        heading = f"## {icon} {comp}"
        # sezione collassabile
        lines.append(f"<details open>")
        lines.append(f"<summary>{heading}</summary>")
        lines.append("")
        for it in lst:
            box = "x" if getattr(it, "checked", False) else " "
            item_name = _escape(it.name)
            qty = getattr(it, "quantity", 1)
            lines.append(f"- [{box}] {item_name} x{qty}")
        lines.append("")
        lines.append("</details>")
        lines.append("")

    if altro:
        lines.append("<details open>")
        lines.append("<summary>## 📦 Altro</summary>")
        lines.append("")
        for it in altro:
            box = "x" if getattr(it, "checked", False) else " "
            item_name = _escape(it.name)
            qty = getattr(it, "quantity", 1)
            lines.append(f"- [{box}] {item_name} x{qty}")
        lines.append("")
        lines.append("</details>")
        lines.append("")

    return "\n".join(lines).strip() + "\n"
