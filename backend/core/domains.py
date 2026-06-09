"""
§8 Domain system — single source of truth for the 8 life-domain labels.

`domain` ∈ DOMAINS or None. Stored on:
  - `assets.domain`       — per-record truth (agent tags by content; user can edit)
  - `user_skills.domain`  — per-skill prior / default (seeds the fallback)
  - `global_skills.domain` — provisioning default copied into user_skills

See spec/08-domain-system.md. This is Layer A (label + display + read); the
§7 gamemode 日环/岛 layer rides on top later.
"""
from typing import Optional

# 8 bounded life domains. Order is canonical (used by UI filter bars, etc.).
DOMAINS = ["工作", "学习", "健康", "运动", "社交", "娱乐", "生活", "灵感"]
DOMAIN_SET = set(DOMAINS)

# Per-skill default domain (prior) for the BASE provisioned skills. Custom
# skills get their prior from the design agent at creation time. machine_name →
# domain. Skills absent here (todo / qa / external_ref / event) have no stable
# prior — their domain is decided by content (or stays null).
SKILL_DOMAIN_PRIOR = {
    "expense": "生活",   # 记账
    "notes":   "灵感",   # 随记 → 灵感
    "contact": "社交",   # 名片(定义即社交)
}


def normalize_domain(value: Optional[str]) -> Optional[str]:
    """Coerce an arbitrary value to a valid domain label or None.

    Drops empty / 'null' / unknown / whitespace-only so a bad agent value never
    lands in the column. Callers treat None as 'not assigned'.
    """
    if not value or not isinstance(value, str):
        return None
    v = value.strip()
    return v if v in DOMAIN_SET else None


def prior_for_skill(machine_name: Optional[str]) -> Optional[str]:
    """Default domain for a base skill machine_name (None if no stable prior)."""
    if not machine_name:
        return None
    return SKILL_DOMAIN_PRIOR.get(machine_name)
