from app.domains.capture.target_resolver import (
    TargetCandidate,
    resolve_target_candidates,
)


def _candidate(entity_id: str, source: str) -> TargetCandidate:
    return TargetCandidate(
        entity_id=entity_id,
        entity_type="expense",
        source=source,
        snapshot={"asset_id": entity_id},
    )


def test_explicit_owned_id_has_highest_priority():
    resolved = resolve_target_candidates(
        explicit=[_candidate("explicit", "explicit_id")],
        prior_turn=[_candidate("prior", "prior_input_turn")],
        result_card=[_candidate("card", "result_card")],
        exact=[_candidate("exact", "exact_match")],
        safe=[_candidate("safe", "safe_candidate")],
    )

    assert resolved.status == "resolved"
    assert resolved.entity_id == "explicit"
    assert resolved.source == "explicit_id"


def test_latest_prior_turn_root_wins_over_result_card_and_search():
    resolved = resolve_target_candidates(
        explicit=[],
        prior_turn=[_candidate("prior", "prior_input_turn")],
        result_card=[_candidate("card", "result_card")],
        exact=[_candidate("exact", "exact_match")],
        safe=[_candidate("safe", "safe_candidate")],
    )

    assert resolved.status == "resolved"
    assert resolved.entity_id == "prior"
    assert resolved.source == "prior_input_turn"


def test_ambiguous_higher_priority_candidates_do_not_fall_through():
    resolved = resolve_target_candidates(
        explicit=[],
        prior_turn=[
            _candidate("prior-1", "prior_input_turn"),
            _candidate("prior-2", "prior_input_turn"),
        ],
        result_card=[],
        exact=[_candidate("exact", "exact_match")],
        safe=[],
    )

    assert resolved.status == "ambiguous"
    assert resolved.entity_id is None
    assert [item.entity_id for item in resolved.candidates] == [
        "prior-1",
        "prior-2",
    ]


def test_unique_exact_match_precedes_safe_candidate():
    resolved = resolve_target_candidates(
        explicit=[],
        prior_turn=[],
        result_card=[],
        exact=[_candidate("exact", "exact_match")],
        safe=[_candidate("safe", "safe_candidate")],
    )

    assert resolved.status == "resolved"
    assert resolved.entity_id == "exact"


def test_multiple_safe_candidates_are_not_resolved_by_recency():
    resolved = resolve_target_candidates(
        explicit=[],
        prior_turn=[],
        result_card=[],
        exact=[],
        safe=[
            _candidate("safe-1", "safe_candidate"),
            _candidate("safe-2", "safe_candidate"),
        ],
    )

    assert resolved.status == "ambiguous"
    assert resolved.entity_id is None


def test_no_candidate_returns_not_found():
    resolved = resolve_target_candidates(
        explicit=[],
        prior_turn=[],
        result_card=[],
        exact=[],
        safe=[],
    )

    assert resolved.status == "not_found"
    assert resolved.entity_id is None
