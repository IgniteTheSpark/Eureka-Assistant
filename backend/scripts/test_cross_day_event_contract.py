from __future__ import annotations

import ast
from datetime import datetime, timedelta, timezone
from pathlib import Path


TOOLS_PATH = Path(__file__).resolve().parents[1] / "mcp_server" / "tools.py"


def _load_normalizer():
    """Load the pure helper without importing the database-backed tools module."""
    tree = ast.parse(TOOLS_PATH.read_text(encoding="utf-8"))
    helper = next(
        (
            node
            for node in tree.body
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
            and node.name == "_normalize_event_end"
        ),
        None,
    )
    assert helper is not None, "mcp_server.tools must define _normalize_event_end"
    namespace: dict[str, object] = {}
    exec(compile(ast.Module(body=[helper], type_ignores=[]), str(TOOLS_PATH), "exec"), namespace)
    return namespace["_normalize_event_end"]


def main() -> None:
    normalize = _load_normalizer()
    local_tz = timezone(timedelta(hours=8))

    start = datetime(2026, 8, 18, 23, 0, tzinfo=local_tz)
    implicit_same_day_end = datetime(2026, 8, 18, 2, 0, tzinfo=local_tz)
    assert normalize(start, implicit_same_day_end, True) == datetime(
        2026, 8, 19, 2, 0, tzinfo=local_tz
    )

    valid_end = datetime(2026, 8, 19, 1, 30, tzinfo=local_tz)
    assert normalize(start, valid_end, True) == valid_end

    try:
        normalize(start, implicit_same_day_end, False)
    except ValueError as exc:
        assert str(exc) == "invalid_event_range"
    else:
        raise AssertionError("an explicit invalid range must not be rolled forward")

    print("ok - cross-day event normalization contract")


if __name__ == "__main__":
    main()
