from __future__ import annotations

import asyncio
import json
import sys

from core.flash_service import process_flash_text


DEFAULT_USER_ID = "9a01c5e0cec74a48bf0d32299fff1c4c"
DEFAULT_TEXT = (
    "【测试normalizer】今天早上吃早餐花了8块钱。然后买咖啡花了25块钱。"
    "今天下午3点钟有一个培训。然后今天早上11点钟有一场网球比赛。"
    "然后今天晚上8~9点，有一个线上面试要参加一下。"
)


async def main() -> None:
    user_id = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_USER_ID
    text = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_TEXT
    result = await process_flash_text(
        user_id,
        text,
        source="typed",
        capture_session_type="manual",
    )
    print(json.dumps({
        "ok": result.get("ok"),
        "session_id": result.get("session_id"),
        "input_turn_id": result.get("input_turn_id"),
        "summary": result.get("summary"),
        "cards": result.get("cards"),
        "derived_assets": result.get("derived_assets"),
        "derived_events": result.get("derived_events"),
        "error": result.get("error"),
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    asyncio.run(main())
