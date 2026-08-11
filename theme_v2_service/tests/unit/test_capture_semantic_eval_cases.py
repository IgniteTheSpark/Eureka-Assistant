import pytest

from app.domains.capture.dispatcher import FlashIntent
from evals.capture_semantic_cases import (
    SEMANTIC_CASES,
    SemanticRouteMismatch,
    assert_semantic_routes,
)


def test_live_semantic_matrix_contains_natural_positive_negative_and_multi_intent_cases():
    case_ids = {case.case_id for case in SEMANTIC_CASES}

    assert {
        "water_interleaved_quantity",
        "water_brand_natural",
        "water_latte_negative",
        "water_purchase_is_expense",
        "water_reminder_is_todo",
        "running_natural",
        "running_future_is_todo",
        "dance_natural",
        "dance_future_is_todo",
        "tennis_natural",
        "mixed_dance_expense_water",
        "mixed_real_dance_water_expense",
        "water_update",
        "running_delete",
        "water_query",
        "notes_fallback",
    }.issubset(case_ids)


def test_semantic_assertion_requires_exact_custom_skill_id_and_operation():
    case = next(
        item for item in SEMANTIC_CASES if item.case_id == "water_interleaved_quantity"
    )

    with pytest.raises(SemanticRouteMismatch, match="water_interleaved_quantity"):
        assert_semantic_routes(
            case,
            [
                FlashIntent(
                    type="daily_water_intake",
                    operation="create",
                    source_text=case.utterance,
                    custom_skill_id="wrong-skill-id",
                )
            ],
            stage="raw",
        )


def test_raw_semantic_assertion_treats_stable_custom_skill_id_as_authoritative():
    case = next(
        item for item in SEMANTIC_CASES if item.case_id == "water_interleaved_quantity"
    )
    raw = [
        FlashIntent(
            type="custom",
            operation="create",
            source_text=case.utterance,
            custom_skill_id="skill-water",
        )
    ]

    assert_semantic_routes(case, raw, stage="raw")
    with pytest.raises(SemanticRouteMismatch, match="normalized"):
        assert_semantic_routes(case, raw, stage="normalized")


def test_semantic_assertion_rejects_an_extra_custom_asset():
    case = next(
        item for item in SEMANTIC_CASES if item.case_id == "water_purchase_is_expense"
    )

    with pytest.raises(SemanticRouteMismatch, match="actual"):
        assert_semantic_routes(
            case,
            [
                FlashIntent(
                    type="expense",
                    operation="create",
                    source_text=case.utterance,
                ),
                FlashIntent(
                    type="daily_water_intake",
                    operation="create",
                    source_text=case.utterance,
                    custom_skill_id="skill-water",
                ),
            ],
            stage="normalized",
        )
