"""Deletion coverage guard (§10.3).

Every model with a user_id column must be registered in the account deletion
graph. A new user-owned table that is not registered fails this test, so
forgotten data becomes a test failure instead of a silent leak.
"""
from __future__ import annotations

import re
from pathlib import Path

from app.account.deletion import DELETION_GRAPH
from app.auth import models as auth_models  # noqa: F401
from app.db import models as domain_models  # noqa: F401
from app.db.base import Base
from app.domains.capture import models as capture_models  # noqa: F401
from app.domains.devices import models as device_models  # noqa: F401
from app.domains.notifications import models as notification_models  # noqa: F401
from app.domains.onboarding.service import AssetResultMarker  # noqa: F401
from app.domains.reports import models as report_models  # noqa: F401
from app.domains.reka import models as reka_models  # noqa: F401
from app.domains.sessions import models as session_models  # noqa: F401
from app.domains.triggers import models as trigger_models  # noqa: F401


def _all_model_tables() -> list[str]:
    return sorted(Base.metadata.tables.keys())


def _tables_with_user_id() -> list[str]:
    """Tables whose mapped model declares a user_id column."""
    result = []
    for table in Base.metadata.sorted_tables:
        if "user_id" in table.c:
            result.append(table.name)
    return sorted(result)


def _deletion_graph_tables() -> list[str]:
    return sorted(DELETION_GRAPH)


def test_every_user_id_table_is_registered_in_deletion_graph():
    registered = set(_deletion_graph_tables())
    missing = [t for t in _tables_with_user_id() if t not in registered]
    assert missing == [], (
        f"user-owned table(s) missing from DELETION_GRAPH: {missing}. "
        "Add them to app/account/deletion.py so account deletion removes them."
    )


def test_deletion_graph_only_contains_real_tables():
    real = set(_all_model_tables())
    phantom = [t for t in _deletion_graph_tables() if t not in real]
    assert phantom == [], (
        f"DELETION_GRAPH references non-existent table(s): {phantom}."
    )


def test_deletion_graph_is_not_empty():
    assert len(DELETION_GRAPH) >= 10
