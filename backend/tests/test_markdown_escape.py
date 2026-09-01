from datetime import date, timedelta
from types import SimpleNamespace

from backend.services.markdown_export import to_markdown, _escape_cell
from backend.services.shopping_markdown import to_shopping_markdown


def _make_inventory(name, brand=None, quantity=1, expiration_date=None, is_estimated=False):
    return SimpleNamespace(
        name=name,
        brand=brand,
        quantity=quantity,
        expiration_date=expiration_date,
        is_estimated=is_estimated,
    )


def test_escape_cell_pipe():
    assert _escape_cell("a|b") == "a\\|b"
    assert _escape_cell("Latte | Fresco") == "Latte \\| Fresco"


def test_escape_cell_newline_and_cr():
    assert _escape_cell("a\nb") == "a b"
    assert _escape_cell("a\rb") == "a b"
    assert _escape_cell("a\r\nb") == "a  b"


def test_to_markdown_pipe_escape_no_extra_columns():
    item = _make_inventory(name="Latte|Fresco", brand="Gran|arolo", quantity=2, expiration_date=date.today() + timedelta(days=5))
    md = to_markdown([item])
    lines = md.splitlines()
    data_line = [l for l in lines if "Latte" in l][0]
    # escaped pipe should be present
    assert "\\|" in data_line
    # data line contains exactly 2 escaped pipes (one per cell)
    assert data_line.count("\\|") == 2
    # total pipes = header 7 + escaped 2 = 9
    assert data_line.count("|") == 9


def test_to_markdown_newline_not_breaking_row():
    item = _make_inventory(name="Latte\nFresco", brand="Brand\r\nTest", quantity=1)
    md = to_markdown([item])
    # no literal newline inside cell line; the item row should be single line
    assert "Latte Fresco" in md
    assert "Brand  Test" in md or "Brand Test" in md
    # ensure not two lines for one item: title, blank, header, separator, data = 5
    lines = md.splitlines()
    assert len(lines) == 5
    # the data line is the last one and contains both fields on one line
    assert lines[-1].count("|") >= 7


def test_shopping_markdown_pipe_escape():
    shopping_list = SimpleNamespace(name="Spesa|Test")
    items = [
        SimpleNamespace(name="Latte|Fresco", quantity=1, checked=False, compartment="frigo"),
        SimpleNamespace(name="Pane\ncon\rpipe|", quantity=2, checked=True, compartment="dispensa"),
    ]
    md = to_shopping_markdown(shopping_list, items)
    assert "Spesa\\|Test" in md
    assert "Latte\\|Fresco" in md
    # newline escaped
    assert "Pane con pipe\\|" in md or "Pane con pipe" in md
    # checklist markers
    assert "- [ ] Latte\\|Fresco x1" in md
    assert "- [x]" in md


def test_shopping_markdown_grouping_and_compartment_default():
    shopping_list = SimpleNamespace(name="Spesa")
    items = [
        SimpleNamespace(name="Yogurt", quantity=1, checked=False, compartment=None),
        SimpleNamespace(name="Vino", quantity=1, checked=False, compartment="cantina"),
        SimpleNamespace(name="Gelato", quantity=1, checked=False, compartment="frigo"),
        SimpleNamespace(name="Strano", quantity=1, checked=False, compartment="garage"),
    ]
    md = to_shopping_markdown(shopping_list, items)
    # default None -> Dispensa Secca (supermercato)
    assert "Dispensa Secca" in md
    assert "Yogurt" in md
    assert "Cantina" in md
    assert "Latticini e Uova" in md
    assert "Altro" in md
    assert "Strano" in md


def test_to_markdown_status_and_estimated_note():
    today = date.today()
    expired = _make_inventory(name="Scaduto", expiration_date=today - timedelta(days=1))
    soon = _make_inventory(name="Scadenza", expiration_date=today + timedelta(days=1))
    ok_item = _make_inventory(name="Ok", expiration_date=today + timedelta(days=10))
    md = to_markdown([expired, soon, ok_item])
    assert "🔴 Scaduto" in md
    assert "🟡 In scadenza" in md
    assert "🟢 OK" in md
    # is_estimated note
    est = _make_inventory(name="Stimato", expiration_date=today + timedelta(days=5), is_estimated=True)
    md2 = to_markdown([est])
    assert "⚠️" in md2
