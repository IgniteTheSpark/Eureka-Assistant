"""Single source of truth for contact 名片 extras: the supported social-media
platforms and the notes-as-markdown helpers.

§ Why a fixed social list (user requirement): socials are chosen from a
supported set, not free-form — we only store the *handle/account* per platform.
The frontend renders the same list (kept in sync; see spec/04-frontend.md
§4.5.3a) and the agent prompt names these keys so the LLM can map "他的微信是X"
→ socials.wechat.

§ Notes are append-only on the agent path (user requirement): the MCP
update_contact appends to the existing notes rather than replacing — a contact's
"where we met / how I know them" history accumulates, never gets wiped by a new
remark. notes is a list of markdown-capable annotation lines; `notes_to_md`
renders it as one markdown document (legacy rows may hold a bare string).
"""
from typing import List

# platform key (stored, lowercase, stable) → display label (UI / agent-facing).
# Keys are the contract: DB stores these keys, frontend + agent map to them.
SUPPORTED_SOCIALS: dict = {
    "x":           "X",
    "telegram":    "Telegram",
    "linkedin":    "LinkedIn",
    "wechat":      "微信",
    "xiaohongshu": "小红书",
    "instagram":   "Instagram",
}


def clean_socials(raw) -> dict:
    """Keep only supported platforms with a non-empty handle (drop unknowns).

    Accepts a dict {platform: handle}. Unknown platforms and blank handles are
    dropped so the agent / a stale client can't write junk keys.
    """
    if not isinstance(raw, dict):
        return {}
    out = {}
    for k, v in raw.items():
        key = str(k).strip().lower()
        handle = str(v).strip() if v is not None else ""
        if key in SUPPORTED_SOCIALS and handle:
            out[key] = handle
    return out


def merge_socials(current, updates) -> dict:
    """Merge `updates` onto `current` (per-platform). A blank handle removes
    that platform; supported-only. Used by the agent path (add one platform
    without clobbering the rest)."""
    base = clean_socials(current)
    if not isinstance(updates, dict):
        return base
    for k, v in updates.items():
        key = str(k).strip().lower()
        if key not in SUPPORTED_SOCIALS:
            continue
        handle = str(v).strip() if v is not None else ""
        if handle:
            base[key] = handle
        else:
            base.pop(key, None)  # explicit blank → unset
    return base


def notes_to_list(raw) -> List[str]:
    """Normalize stored notes → list of non-empty annotation lines.
    Legacy rows may hold a bare markdown string (split on newlines)."""
    if isinstance(raw, list):
        return [str(x).strip() for x in raw if str(x).strip()]
    if isinstance(raw, str) and raw.strip():
        return [ln.strip() for ln in raw.splitlines() if ln.strip()]
    return []


def notes_to_md(raw) -> str:
    """Render stored notes as a single markdown document (one line per note)."""
    return "\n".join(notes_to_list(raw))


def append_notes(current, additions) -> List[str]:
    """Append one or more annotations to existing notes (never replace).
    `additions` may be a str or a list of str. Returns the new notes list."""
    out = notes_to_list(current)
    if isinstance(additions, str):
        additions = [additions]
    if isinstance(additions, list):
        for a in additions:
            line = str(a).strip()
            if line:
                out.append(line)
    return out
