"""
Agent eval runner — drives evals/scenarios.py against the RUNNING backend and
checks observable behavior (tool calls / skill / domain / redirect / cards).

Run inside the backend container (has DB + LLM env):
    docker exec eureka-assistant-backend-1 python -m evals.run_evals
    docker exec eureka-assistant-backend-1 python -m evals.run_evals --repeat 3
    docker exec eureka-assistant-backend-1 python -m evals.run_evals --only water-route,query-domain

Exit code 0 iff every scenario passed every repeat. This is the regression net
for the AgentRunner / IntentRouter refactor: keep it green.
"""
import json
import sys
import urllib.request
import urllib.error

from core.security import create_token
from evals.scenarios import SCENARIOS

UID = "c737604ad1ab4b36acce3c00c9814948"   # test user (has todo/expense/notes + daily_water/running/work_log/book_note)
BASE = "http://localhost:8000"
TOKEN = create_token(UID)
_HDR = {"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"}


def _post_sse(path, body, timeout=120):
    """POST and parse an SSE stream → list of (event, data_dict)."""
    req = urllib.request.Request(BASE + path, data=json.dumps(body).encode(), headers=_HDR, method="POST")
    out, cur = [], None
    with urllib.request.urlopen(req, timeout=timeout) as r:
        for raw in r:
            line = raw.decode("utf-8", "replace").rstrip("\n")
            if line.startswith("event:"):
                cur = line[6:].strip()
            elif line.startswith("data:"):
                try:
                    out.append((cur, json.loads(line[5:].strip())))
                except ValueError:
                    pass
    return out


def _post_json(path, body, timeout=120):
    req = urllib.request.Request(BASE + path, data=json.dumps(body).encode(), headers=_HDR, method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8", "replace"))


def _run_chat(text):
    evs = _post_sse("/api/chat", {"user_text": text})
    calls = [d for (e, d) in evs if e == "tool_call" and isinstance(d, dict)]
    reply = "".join(d.get("text", "") for (e, d) in evs if e == "token" and isinstance(d, dict))
    return calls, reply, []


def _run_flash(text):
    res = _post_json("/api/flash", {"text": text})
    return [], res.get("reply", "") or res.get("summary", ""), (res.get("cards") or [])


def _evaluate(scn, calls, reply, cards):
    exp = scn["expect"]
    creates = [c for c in calls if "create" in (c.get("name") or "")]
    queries = [c for c in calls if "query" in (c.get("name") or "")]
    fails = []
    if exp.get("create") and not creates:
        fails.append("expected a create, none called")
    if exp.get("no_create") and creates:
        fails.append(f"expected NO create, got {[c.get('name') for c in creates]}")
    if exp.get("no_tool") and calls:
        fails.append(f"expected NO tool call (pure chat/answer), got {[c.get('name') for c in calls]}")
    if exp.get("event") and not any("create_event" in (c.get("name") or "") for c in calls):
        fails.append(f"expected an event create, got {[c.get('name') for c in calls]}")
    if exp.get("query") and not queries:
        fails.append("expected a query_* call, none seen")
    if exp.get("tool") and not any(exp["tool"] in (c.get("name") or "") for c in calls):
        fails.append(f"expected a tool containing '{exp['tool']}', got {[c.get('name') for c in calls]}")
    if exp.get("skill"):
        skills = [(c.get("args") or {}).get("user_skill_name") for c in creates]
        if exp["skill"] not in skills:
            fails.append(f"expected skill={exp['skill']}, got {skills}")
    if exp.get("domain"):
        doms = [(c.get("args") or {}).get("domain") for c in creates]
        if exp["domain"] not in doms:
            fails.append(f"expected domain={exp['domain']}, got {doms}")
    if exp.get("redirect"):
        if creates:
            fails.append("redirect expected but a create happened")
        if "报告" not in reply:
            fails.append("redirect expected: reply should point to the 报告 entry")
    if exp.get("min_cards") is not None and len(cards) < exp["min_cards"]:
        fails.append(f"expected >= {exp['min_cards']} cards, got {len(cards)}")
    return fails


def main():
    args = sys.argv[1:]
    repeat = 1
    only = None
    if "--repeat" in args:
        repeat = int(args[args.index("--repeat") + 1])
    if "--only" in args:
        only = set(args[args.index("--only") + 1].split(","))
    scenarios = [s for s in SCENARIOS if not only or s["id"] in only]

    total = passed = 0
    failures = []
    for scn in scenarios:
        for rep in range(repeat):
            total += 1
            label = scn["id"] + (f"#{rep+1}" if repeat > 1 else "")
            try:
                if scn["surface"] == "flash":
                    calls, reply, cards = _run_flash(scn["text"])
                else:
                    calls, reply, cards = _run_chat(scn["text"])
                fails = _evaluate(scn, calls, reply, cards)
            except (urllib.error.URLError, TimeoutError) as e:
                fails = [f"request error: {str(e)[:80]}"]
            if fails:
                print(f"  FAIL {label}: " + "; ".join(fails))
                failures.append(label)
            else:
                print(f"  PASS {label}")
                passed += 1

    print(f"\n=== {passed}/{total} passed ===")
    if failures:
        print("failed: " + ", ".join(failures))
    sys.exit(0 if passed == total else 1)


if __name__ == "__main__":
    main()
