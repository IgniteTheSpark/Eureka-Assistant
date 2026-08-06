from __future__ import annotations

from pydantic import BaseModel, Field


class FlashIntent(BaseModel):
    type: str = Field(min_length=1, max_length=100)
    source_text: str = Field(min_length=1, max_length=4000)
    domain: str | None = Field(default=None, max_length=100)


class FlashDispatchResult(BaseModel):
    intents: list[FlashIntent] = Field(default_factory=list, max_length=20)


def build_dispatcher_messages(
    *,
    transcript: str,
    reference_datetime: str,
    custom_skills: list[dict],
) -> list[dict[str, str]]:
    custom_lines = "\n".join(
        f"- {item['machine_name']} ({item['display_name']}): "
        f"{item.get('description') or ''}; schema={item.get('schema') or {}}"
        for item in custom_skills
    ) or "(无)"
    instruction = f"""
FLASH_DISPATCHER
你是 Eureka 闪念输入的意图分发器。只输出符合给定 schema 的 JSON，不调用工具。

硬规则：
1. event 只有在完整时段（开始+结束、开始+时长、或全天）时成立；单个时刻或只有日期的未来事项是 todo。
2. 同一文字片段只归一个最具体类型。expense/contact/event/todo 不能再重复落 notes。
3. 一段输入可以拆成多个原子 intent；两笔消费必须是两个 expense intent。
4. 自由文本统一归 notes，不输出 idea、misc、other。
5. 联系人的新增、补充字段、修改、删除都归 contact。
6. 问题或查询归 qa；外部系统动作当前不可执行，也归 qa。
7. 除 qa 外，每条 intent 按内容给 domain：工作/学习/健康/运动/社交/娱乐/生活/灵感；不确定用生活。
8. source_text 必须是原话中支持该 intent 的最小完整片段。

用户自定义 Skill：
{custom_lines}

自定义 Skill 只压过 notes；绝不覆盖 expense/contact/event/todo。未来计划不能写入记录型自定义 Skill，只有已发生的记录才可匹配。
""".strip()
    return [
        {"role": "system", "content": instruction},
        {
            "role": "user",
            "content": (
                f"reference_datetime={reference_datetime}\n"
                "BEGIN_UNTRUSTED_TRANSCRIPT\n"
                f"{transcript}\n"
                "END_UNTRUSTED_TRANSCRIPT"
            ),
        },
    ]
