import inspect

from scripts import smoke_flash_provider
from scripts.smoke_flash_provider import SYNTHETIC_CASES


def test_full_provider_smoke_asserts_exact_custom_skill_routes():
    cases = {case.case_id: case for case in SYNTHETIC_CASES}

    assert cases["mixed_expense_water"].expected_types == (
        "expense",
        "daily_water_intake",
    )
    assert cases["running_natural"].expected_types == ("running_log",)
    assert cases["knowledge_qa"].expected_types == ("qa",)


def test_full_provider_smoke_has_no_test_only_eval_dependency():
    assert "from evals" not in inspect.getsource(smoke_flash_provider)
