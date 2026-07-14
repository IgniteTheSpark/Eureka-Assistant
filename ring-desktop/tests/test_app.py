from ring_desktop import app


def test_status_icon_stays_compact():
    assert app.status_icon("connected", recording=False) == "🟢"
    assert app.status_icon("scanning", recording=False) == "⚪️"
    assert app.status_icon("connected", recording=True) == "🎙"
