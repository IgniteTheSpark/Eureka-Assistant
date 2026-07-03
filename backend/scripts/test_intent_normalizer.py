from __future__ import annotations

from agents.intent_normalizer import normalize_intents


CUSTOM_SKILLS = {
    "tennis_match": {
        "display_name": "网球比赛",
        "payload_schema": {"date": {"type": "date", "description": "比赛日期"}},
        "render_spec": {},
    },
    "running": {
        "display_name": "跑步训练",
        "payload_schema": {"distance": {"type": "number", "description": "距离"}},
        "render_spec": {},
    },
}


CASES = [
    {
        "name": "multi expense plus future schedule",
        "input": [
            {
                "type": "expense",
                "domain": "生活",
                "source_text": "今天早上吃早餐花了8块钱。然后买咖啡花了25块钱。",
            },
            {
                "type": "tennis_match",
                "domain": "运动",
                "source_text": "今天早上11点钟有一场网球比赛。",
            },
            {
                "type": "event",
                "domain": "工作",
                "source_text": "今天晚上8~9点，有一个线上面试要参加一下。",
            },
        ],
        "expected": [
            ("expense", "今天早上吃早餐花了8块钱"),
            ("expense", "买咖啡花了25块钱"),
            ("todo", "今天早上11点钟有一场网球比赛。"),
            ("event", "今天晚上8~9点，有一个线上面试要参加一下。"),
        ],
    },
    {
        "name": "future ranged custom sports becomes event",
        "input": [
            {
                "type": "tennis_match",
                "domain": "运动",
                "source_text": "明天下午3点到5点有一场网球比赛。",
            }
        ],
        "expected": [("event", "明天下午3点到5点有一场网球比赛。")],
    },
    {
        "name": "completed custom sports stays record",
        "input": [
            {
                "type": "tennis_match",
                "domain": "运动",
                "source_text": "今天上午打了一场网球比赛，比分6比4赢了。",
            }
        ],
        "expected": [("tennis_match", "今天上午打了一场网球比赛，比分6比4赢了。")],
    },
    {
        "name": "single expense remains one intent",
        "input": [
            {
                "type": "expense",
                "domain": "生活",
                "source_text": "中午吃麦当劳花了32元。",
            }
        ],
        "expected": [("expense", "中午吃麦当劳花了32元。")],
    },
    {
        "name": "malformed dispatcher entries are dropped",
        "input": [
            "bad",
            {"type": "running", "source_text": "今天早上跑了5公里。"},
        ],
        "expected": [("running", "今天早上跑了5公里。")],
    },
]


def main() -> None:
    for case in CASES:
        normalized = normalize_intents(case["input"], CUSTOM_SKILLS)
        actual = [(item.get("type"), item.get("source_text")) for item in normalized]
        assert actual == case["expected"], (
            f"{case['name']} failed\nexpected={case['expected']}\nactual={actual}"
        )
        print(f"ok - {case['name']}: {actual}")


if __name__ == "__main__":
    main()
