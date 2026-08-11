from __future__ import annotations

import re


_CURRENCY_RE = re.compile(
    r"(?:人民币|美元|美金|港币|港元|欧元|日元|英镑|RMB|CNY|USD|HKD|EUR|JPY|GBP|"
    r"[¥￥$])|(?:\d+(?:\.\d+)?\s*(?:块钱|块|元))",
    re.IGNORECASE,
)
_FINANCIAL_ACTION_RE = re.compile(
    r"(?:消费|支付|付款|付了|买单|结账|报销|账单|收款|入账|转账|退款|收入|支出|"
    r"价格|价钱|费用|花费|购买|购入|买了?|多少钱)"
)
_BARE_SPEND_RE = re.compile(r"花(?:了)?\s*(\d+(?:\.\d+)?)")
_NON_MONEY_UNIT_RE = re.compile(
    r"^(?:毫?秒|分钟|小时|天|周|个月|年|毫升|ml|升|l|克|kg|公斤|斤|公里|km|米|m|"
    r"次|个|组|局|场)",
    re.IGNORECASE,
)


def has_expense_evidence(source_text: str) -> bool:
    """Return whether one intent slice contains explicit financial evidence.

    This deliberately evaluates only the dispatcher's atomic source slice. It is
    a mutation safety check, not a replacement for model-based classification.
    """

    source = source_text.strip()
    if not source:
        return False
    if _CURRENCY_RE.search(source) or _FINANCIAL_ACTION_RE.search(source):
        return True
    for match in _BARE_SPEND_RE.finditer(source):
        trailing = source[match.end() :].lstrip()
        if not _NON_MONEY_UNIT_RE.match(trailing):
            return True
    return False
