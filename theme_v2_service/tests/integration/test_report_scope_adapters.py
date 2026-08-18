from datetime import datetime, timedelta, timezone

from app.db.models import Asset, Event, UserSkill
from app.domains.reports.scope_adapters import (
    infer_scope_adapter,
    initial_scope,
    list_scope_candidates,
)


NOW = datetime(2026, 8, 11, 12, 0, tzinfo=timezone.utc)


def test_report_scope_router_recognizes_categories_without_exact_sentence_matches():
    assert infer_scope_adapter("请准备明晚会议的会前背景") == "pre_event_briefing"
    assert infer_scope_adapter("复盘本周的喝水和跑步数据") == "period_summary"
    assert infer_scope_adapter("研究一下欧洲足球青训") == "generic"


def test_period_summary_initial_scope_resolves_the_local_week():
    draft = initial_scope(
        "帮我汇总一下这周我的几个记录的数据",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert draft.adapter_kind == "period_summary"
    assert draft.time_range is not None
    assert draft.time_range.from_at.isoformat() == "2026-08-10T00:00:00+08:00"
    assert draft.time_range.to_at.isoformat() == "2026-08-17T00:00:00+08:00"


async def test_pre_event_candidates_are_only_the_next_three_active_events(session):
    starts = [
        ("past", NOW - timedelta(minutes=30), "scheduled"),
        ("first", NOW + timedelta(minutes=30), "scheduled"),
        ("cancelled", NOW + timedelta(minutes=45), "cancelled"),
        ("second", NOW + timedelta(hours=1), "scheduled"),
        ("third", NOW + timedelta(hours=2), "scheduled"),
        ("fourth", NOW + timedelta(hours=3), "scheduled"),
    ]
    for event_id, start, status in starts:
        session.add(
            Event(
                id=event_id,
                user_id="user-1",
                title=event_id,
                description=f"{event_id} notes",
                start_at=start.replace(tzinfo=None),
                end_at=(start + timedelta(hours=1)).replace(tzinfo=None),
                all_day=False,
                status=status,
            )
        )
    await session.commit()

    response = await list_scope_candidates(
        session,
        user_id="user-1",
        adapter_kind="pre_event_briefing",
        intent="会前调研",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert [event.reference.id for event in response.events] == [
        "first",
        "second",
        "third",
    ]
    assert [event.local_start for event in response.events] == [
        "20:30",
        "21:00",
        "22:00",
    ]
    assert response.events[0].notes == "first notes"


async def test_period_summary_defaults_all_aggregatable_in_period_records(session):
    water = UserSkill(
        id="skill-water",
        user_id="user-1",
        machine_name="water_intake_log",
        display_name="喝水记录",
        schema_json={
            "type": "object",
            "properties": {"volume_ml": {"type": "number"}},
        },
    )
    running = UserSkill(
        id="skill-running",
        user_id="user-1",
        machine_name="running_log",
        display_name="跑步记录",
        schema_json={
            "type": "object",
            "properties": {"distance_km": {"type": "number"}},
        },
    )
    notes = UserSkill(
        id="skill-notes",
        user_id="user-1",
        machine_name="notes",
        display_name="随记",
        schema_json={
            "type": "object",
            "properties": {"content": {"type": "string"}},
        },
    )
    session.add_all([water, running, notes])
    await session.flush()
    session.add_all(
        [
            Asset(
                id="water-1",
                user_id="user-1",
                user_skill_id=water.id,
                payload_json={"volume_ml": 500},
                effective_at=datetime(2026, 8, 10, 1, 0),
            ),
            Asset(
                id="run-1",
                user_id="user-1",
                user_skill_id=running.id,
                payload_json={"distance_km": 5},
                effective_at=datetime(2026, 8, 11, 1, 0),
            ),
            Asset(
                id="note-1",
                user_id="user-1",
                user_skill_id=notes.id,
                payload_json={"content": "ordinary note"},
                effective_at=datetime(2026, 8, 11, 2, 0),
            ),
            Asset(
                id="water-old",
                user_id="user-1",
                user_skill_id=water.id,
                payload_json={"volume_ml": 250},
                effective_at=datetime(2026, 8, 8, 1, 0),
            ),
        ]
    )
    await session.commit()

    response = await list_scope_candidates(
        session,
        user_id="user-1",
        adapter_kind="period_summary",
        intent="汇总这周我的记录",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert [group.skill_id for group in response.record_groups] == [
        "skill-running",
        "skill-water",
    ]
    assert all(group.default_selected for group in response.record_groups)
    assert {
        record.reference.id
        for group in response.record_groups
        for record in group.records
    } == {"water-1", "run-1"}
    assert response.default_scope.skill_ids == ["skill-running", "skill-water"]
    assert response.default_scope.additional_focus == ""


async def _seed_report_record_types(session):
    skills = [
        UserSkill(
            id=skill_id,
            user_id="user-1",
            machine_name=machine_name,
            display_name=display_name,
            description=description,
            domain=domain,
            schema_json={
                "type": "object",
                "properties": {"value": {"type": "number"}},
            },
        )
        for skill_id, machine_name, display_name, description, domain in [
            (
                "skill-running",
                "running_log",
                "跑步记录",
                "记录跑步距离",
                "健康",
            ),
            ("skill-expense", "expense", "消费", "记录支出金额", "财务"),
            (
                "skill-water",
                "water_log",
                "喝水记录",
                "记录饮水量",
                "健康",
            ),
            ("skill-dance", "dance_log", "跳舞记录", "记录舞蹈时长", "运动"),
        ]
    ]
    session.add_all(skills)
    await session.flush()
    session.add_all(
        [
            Asset(
                id=f"asset-{index}",
                user_id="user-1",
                user_skill_id=skill.id,
                payload_json={"value": index + 1},
                effective_at=datetime(2026, 8, 10, 1 + index, 0),
            )
            for index, skill in enumerate(skills)
        ]
    )
    await session.commit()


async def test_vague_recent_running_matches_only_running_and_requires_time(session):
    await _seed_report_record_types(session)

    response = await list_scope_candidates(
        session,
        user_id="user-1",
        adapter_kind="period_summary",
        intent="总结最近的跑步情况",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert [group.machine_name for group in response.record_groups] == [
        "running_log"
    ]
    assert response.default_scope.skill_ids == ["skill-running"]
    assert response.default_scope.time_range is None
    assert response.default_scope.missing_dimensions == ["time_range"]
    assert response.default_scope.supporting_references == []
    assert response.default_scope.selection.auto_references == []


async def test_explicit_period_selects_only_matching_running_assets(session):
    await _seed_report_record_types(session)
    session.add(
        Asset(
            id="run-2",
            user_id="user-1",
            user_skill_id="skill-running",
            payload_json={"value": 8},
            effective_at=datetime(2026, 8, 11, 1, 0),
        )
    )
    await session.commit()

    response = await list_scope_candidates(
        session,
        user_id="user-1",
        adapter_kind="period_summary",
        intent="总结过去 30 天的跑步情况",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert [group.skill_id for group in response.record_groups] == [
        "skill-running"
    ]
    assert {
        reference.id for reference in response.default_scope.supporting_references
    } == {"asset-0", "run-2"}


async def test_english_skill_name_matches_an_english_request(session):
    await _seed_report_record_types(session)

    response = await list_scope_candidates(
        session,
        user_id="user-1",
        adapter_kind="period_summary",
        intent="总结过去 30 天的 Running Log",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert [group.skill_id for group in response.record_groups] == [
        "skill-running"
    ]


async def test_custom_english_skill_name_matches_without_a_built_in_alias(session):
    skills = [
        UserSkill(
            id="skill-strength",
            user_id="user-1",
            machine_name="strength_training_log",
            display_name="Strength Training Log",
            description="Tracks lifted weights",
            schema_json={
                "type": "object",
                "properties": {"weight": {"type": "number"}},
            },
        ),
        UserSkill(
            id="skill-sleep",
            user_id="user-1",
            machine_name="sleep_log",
            display_name="Sleep Log",
            description="Tracks sleep duration",
            schema_json={
                "type": "object",
                "properties": {"hours": {"type": "number"}},
            },
        ),
    ]
    session.add_all(skills)
    await session.flush()
    session.add_all(
        [
            Asset(
                id=f"custom-{index}",
                user_id="user-1",
                user_skill_id=skill.id,
                payload_json={"value": index + 1},
                effective_at=datetime(2026, 8, 10, index + 1, 0),
            )
            for index, skill in enumerate(skills)
        ]
    )
    await session.commit()

    response = await list_scope_candidates(
        session,
        user_id="user-1",
        adapter_kind="period_summary",
        intent="总结过去 30 天的 strength training",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert [group.skill_id for group in response.record_groups] == [
        "skill-strength"
    ]


async def test_english_alias_matches_a_separator_delimited_skill_name(session):
    skills = [
        UserSkill(
            id="skill-running",
            user_id="user-1",
            machine_name="running_log",
            display_name="Running Log",
            description="Tracks running distance",
            schema_json={
                "type": "object",
                "properties": {"distance_km": {"type": "number"}},
            },
        ),
        UserSkill(
            id="skill-sleep",
            user_id="user-1",
            machine_name="sleep_log",
            display_name="Sleep Log",
            description="Tracks sleep duration",
            schema_json={
                "type": "object",
                "properties": {"hours": {"type": "number"}},
            },
        ),
    ]
    session.add_all(skills)
    await session.flush()
    session.add_all(
        [
            Asset(
                id=f"english-{index}",
                user_id="user-1",
                user_skill_id=skill.id,
                payload_json={"value": index + 1},
                effective_at=datetime(2026, 8, 10, index + 1, 0),
            )
            for index, skill in enumerate(skills)
        ]
    )
    await session.commit()

    response = await list_scope_candidates(
        session,
        user_id="user-1",
        adapter_kind="period_summary",
        intent="总结过去 30 天的 run",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert [group.skill_id for group in response.record_groups] == [
        "skill-running"
    ]

    phrase_response = await list_scope_candidates(
        session,
        user_id="user-1",
        adapter_kind="period_summary",
        intent="总结过去 30 天的 run log",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert [group.skill_id for group in phrase_response.record_groups] == [
        "skill-running"
    ]


async def test_multiple_explicit_skill_terms_keep_each_matching_group(session):
    await _seed_report_record_types(session)

    response = await list_scope_candidates(
        session,
        user_id="user-1",
        adapter_kind="period_summary",
        intent="总结过去 30 天的跑步和喝水情况",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert [group.skill_id for group in response.record_groups] == [
        "skill-running",
        "skill-water",
    ]
    assert {
        reference.id for reference in response.default_scope.supporting_references
    } == {"asset-0", "asset-2"}


async def test_explicit_domain_term_matches_only_groups_in_that_domain(session):
    await _seed_report_record_types(session)

    response = await list_scope_candidates(
        session,
        user_id="user-1",
        adapter_kind="period_summary",
        intent="总结过去 30 天的健康情况",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert [group.skill_id for group in response.record_groups] == [
        "skill-running",
        "skill-water",
    ]


async def test_explicit_skill_identity_takes_precedence_over_shared_domain(session):
    await _seed_report_record_types(session)

    response = await list_scope_candidates(
        session,
        user_id="user-1",
        adapter_kind="period_summary",
        intent="总结过去 30 天健康领域的跑步情况",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert [group.skill_id for group in response.record_groups] == [
        "skill-running"
    ]


async def test_cjk_alias_does_not_match_inside_a_custom_skill_name(session):
    await _seed_report_record_types(session)
    research = UserSkill(
        id="skill-consumer-research",
        user_id="user-1",
        machine_name="consumer_research",
        display_name="消费者研究",
        description="记录消费者访谈结论",
        domain="研究",
        schema_json={
            "type": "object",
            "properties": {"interview_count": {"type": "number"}},
        },
    )
    session.add(research)
    await session.flush()
    session.add(
        Asset(
            id="consumer-research-1",
            user_id="user-1",
            user_skill_id=research.id,
            payload_json={"interview_count": 6},
            effective_at=datetime(2026, 8, 10, 6, 0),
        )
    )
    await session.commit()

    response = await list_scope_candidates(
        session,
        user_id="user-1",
        adapter_kind="period_summary",
        intent="总结过去 30 天的消费者研究",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert [group.skill_id for group in response.record_groups] == [
        "skill-consumer-research"
    ]


async def test_custom_identity_does_not_inherit_an_embedded_expense_alias(session):
    await _seed_report_record_types(session)
    research = UserSkill(
        id="skill-consumer-research",
        user_id="user-1",
        machine_name="consumer_research",
        display_name="消费者研究",
        description="记录消费者访谈结论",
        domain="研究",
        schema_json={
            "type": "object",
            "properties": {"interview_count": {"type": "number"}},
        },
    )
    session.add(research)
    await session.flush()
    session.add(
        Asset(
            id="consumer-research-1",
            user_id="user-1",
            user_skill_id=research.id,
            payload_json={"interview_count": 6},
            effective_at=datetime(2026, 8, 10, 6, 0),
        )
    )
    await session.commit()

    for intent in ("总结过去 30 天的消费情况", "总结过去 30 天的消费额"):
        response = await list_scope_candidates(
            session,
            user_id="user-1",
            adapter_kind="period_summary",
            intent=intent,
            now=NOW,
            timezone_name="Asia/Shanghai",
        )

        assert [group.skill_id for group in response.record_groups] == [
            "skill-expense"
        ]
        assert [
            reference.id
            for reference in response.default_scope.supporting_references
        ] == ["asset-1"]


async def test_cjk_alias_still_matches_a_natural_expense_request(session):
    await _seed_report_record_types(session)

    response = await list_scope_candidates(
        session,
        user_id="user-1",
        adapter_kind="period_summary",
        intent="总结最近的消费情况",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert [group.skill_id for group in response.record_groups] == [
        "skill-expense"
    ]
    assert response.default_scope.time_range is None
    assert response.default_scope.supporting_references == []


async def test_cjk_alias_matches_an_open_ended_amount_compound(session):
    await _seed_report_record_types(session)

    response = await list_scope_candidates(
        session,
        user_id="user-1",
        adapter_kind="period_summary",
        intent="总结过去 30 天的消费额",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert [group.skill_id for group in response.record_groups] == [
        "skill-expense"
    ]
    assert [
        reference.id for reference in response.default_scope.supporting_references
    ] == ["asset-1"]


async def test_cjk_alias_matches_a_colloquial_question_suffix(session):
    await _seed_report_record_types(session)

    response = await list_scope_candidates(
        session,
        user_id="user-1",
        adapter_kind="period_summary",
        intent="总结过去 30 天消费怎么样",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert [group.skill_id for group in response.record_groups] == [
        "skill-expense"
    ]
    assert [
        reference.id for reference in response.default_scope.supporting_references
    ] == ["asset-1"]


async def test_cjk_alias_matches_an_unlisted_metric_compound(session):
    await _seed_report_record_types(session)

    response = await list_scope_candidates(
        session,
        user_id="user-1",
        adapter_kind="period_summary",
        intent="总结过去 30 天跑步里程",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert [group.skill_id for group in response.record_groups] == [
        "skill-running"
    ]
    assert [
        reference.id for reference in response.default_scope.supporting_references
    ] == ["asset-0"]


async def test_description_derived_alias_matches_without_identity_metadata(session):
    metric = UserSkill(
        id="skill-fitness-metric",
        user_id="user-1",
        machine_name="fitness_metric",
        display_name="训练指标",
        description="记录跑步距离",
        domain="健康",
        schema_json={
            "type": "object",
            "properties": {"distance_km": {"type": "number"}},
        },
    )
    unrelated = UserSkill(
        id="skill-expense",
        user_id="user-1",
        machine_name="expense",
        display_name="消费",
        description="记录支出金额",
        domain="财务",
        schema_json={
            "type": "object",
            "properties": {"amount": {"type": "number"}},
        },
    )
    session.add_all([metric, unrelated])
    await session.flush()
    session.add_all(
        [
            Asset(
                id="metric-1",
                user_id="user-1",
                user_skill_id=metric.id,
                payload_json={"distance_km": 5},
                effective_at=datetime(2026, 8, 10, 1, 0),
            ),
            Asset(
                id="expense-1",
                user_id="user-1",
                user_skill_id=unrelated.id,
                payload_json={"amount": 20},
                effective_at=datetime(2026, 8, 10, 2, 0),
            ),
        ]
    )
    await session.commit()

    response = await list_scope_candidates(
        session,
        user_id="user-1",
        adapter_kind="period_summary",
        intent="总结过去 30 天跑步里程",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert [group.skill_id for group in response.record_groups] == [
        "skill-fitness-metric"
    ]
    assert [
        reference.id for reference in response.default_scope.supporting_references
    ] == ["metric-1"]


async def test_additive_domain_and_identity_terms_union_matching_groups(session):
    await _seed_report_record_types(session)

    response = await list_scope_candidates(
        session,
        user_id="user-1",
        adapter_kind="period_summary",
        intent="总结过去 30 天健康和消费情况",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert [group.skill_id for group in response.record_groups] == [
        "skill-expense",
        "skill-running",
        "skill-water",
    ]


async def test_additive_identity_and_domain_terms_union_matching_groups(session):
    await _seed_report_record_types(session)

    response = await list_scope_candidates(
        session,
        user_id="user-1",
        adapter_kind="period_summary",
        intent="总结过去 30 天跑步和财务情况",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert [group.skill_id for group in response.record_groups] == [
        "skill-expense",
        "skill-running",
    ]


async def test_additive_relation_only_applies_to_adjacent_semantic_spans(session):
    await _seed_report_record_types(session)

    response = await list_scope_candidates(
        session,
        user_id="user-1",
        adapter_kind="period_summary",
        intent="总结过去 30 天健康领域的跑步和消费情况",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert [group.skill_id for group in response.record_groups] == [
        "skill-expense",
        "skill-running",
    ]


async def test_unmatched_or_generic_terms_retain_all_groups_for_confirmation(session):
    await _seed_report_record_types(session)

    unmatched = await list_scope_candidates(
        session,
        user_id="user-1",
        adapter_kind="period_summary",
        intent="总结过去 30 天的营养情况",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )
    generic = await list_scope_candidates(
        session,
        user_id="user-1",
        adapter_kind="period_summary",
        intent="总结过去 30 天的记录数据",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    expected = ["skill-dance", "skill-expense", "skill-running", "skill-water"]
    assert [group.skill_id for group in unmatched.record_groups] == expected
    assert [group.skill_id for group in generic.record_groups] == expected


async def test_short_english_alias_does_not_match_inside_an_unrelated_word(session):
    await _seed_report_record_types(session)

    response = await list_scope_candidates(
        session,
        user_id="user-1",
        adapter_kind="period_summary",
        intent="总结过去 30 天的 brunch 消费",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert [group.skill_id for group in response.record_groups] == [
        "skill-expense"
    ]
