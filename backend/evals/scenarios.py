"""
Agent eval scenarios (§ codex review — agent regression net).

Each scenario runs a real Chinese utterance through a live pipeline (chat or
flash) against the running backend and asserts on OBSERVABLE behavior: which
tool fired, the skill/domain it routed to, create-vs-query-vs-redirect-vs-answer.
These encode the behaviors hand-tuned across the 2026-06 sessions — the net that
must stay green before/after the AgentRunner + IntentRouter refactor.

Assertion keys (all optional; a scenario asserts only what it lists):
  create:    bool  — at least one tool_create_* was called
  no_create: bool  — NO tool_create_* was called
  no_tool:   bool  — NO tool call at all (pure CHAT / CHAT-ANSWER)
  tool:      str   — substring SOME called tool name must contain ("create_todo", "query_asset", "create_task"…)
  skill:     str   — user_skill_name on a create_asset call
  domain:    str   — domain arg on a create call (§8)
  query:     bool  — a tool_query_* was called
  event:     bool  — a tool_create_event was called
  redirect:  bool  — no create + reply points to the 报告 entry
  min_cards: int   — (flash) at least N derived cards

Stability note: deepseek is non-deterministic. Structural assertions
(create/no_create/no_tool/query/event/tool/skill/redirect/min_cards) are stable;
`domain` on custom skills (no prior, content-tagged) is ~85% — a lone FAIL is a
signal to inspect, not always a regression. Re-run flaky ids with --repeat 3.
The test user (c737604…) has: todo / contact / expense / notes(随记) / qa /
external_ref + custom book_note / daily_water / running / work_log.
"""

SCENARIOS = [
    # ═══ A. skill routing — structured skills land on the right machine_name ═══
    {"id": "route-water-1", "surface": "chat", "text": "我刚喝了100ml水",
     "expect": {"create": True, "skill": "daily_water"}},
    {"id": "route-water-2", "surface": "chat", "text": "今天又喝了一大杯水，差不多300毫升",
     "expect": {"create": True, "skill": "daily_water"}},
    {"id": "route-run-1", "surface": "chat", "text": "今天跑了5公里",
     "expect": {"create": True, "skill": "running"}},
    {"id": "route-run-2", "surface": "chat", "text": "晚上沿着江边夜跑了40分钟",
     "expect": {"create": True, "skill": "running"}},
    {"id": "route-expense-1", "surface": "chat", "text": "记一笔 打车 30 块",
     "expect": {"create": True, "skill": "expense", "domain": "生活"}},
    {"id": "route-expense-2", "surface": "chat", "text": "午饭花了 45",
     "expect": {"create": True, "skill": "expense"}},
    {"id": "route-book-1", "surface": "chat", "text": "今天读了《人类简史》大概50页",
     "expect": {"create": True, "skill": "book_note"}},
    # casual "finished a book + feeling" — must RECORD it (not skip as opinion);
    # book_note vs 随记 is a defensible toss-up for this phrasing, so assert only create.
    {"id": "route-book-2", "surface": "chat", "text": "看完了《活着》，很压抑但很好",
     "expect": {"create": True}},
    {"id": "route-worklog-1", "surface": "chat", "text": "工作日志：今天梳理了 domain 系统的实现方案",
     "expect": {"create": True, "skill": "work_log"}},

    # ═══ B. domain by content (§8) — same kind of record, different life-domain ═══
    {"id": "dom-todo-work", "surface": "chat", "text": "帮我记个待办：把季度报告发给客户",
     "expect": {"create": True, "tool": "create_todo", "domain": "工作"}},
    {"id": "dom-todo-life", "surface": "chat", "text": "提醒我下班顺路买菜",
     "expect": {"create": True, "tool": "create_todo", "domain": "生活"}},
    {"id": "dom-todo-social", "surface": "chat", "text": "记个待办：周末约老王喝咖啡",
     "expect": {"create": True, "tool": "create_todo"}},
    {"id": "dom-todo-health", "surface": "chat", "text": "提醒我周四去医院复查",
     "expect": {"create": True, "tool": "create_todo"}},
    {"id": "dom-expense-ent", "surface": "chat", "text": "记一笔电影票 80",
     "expect": {"create": True, "skill": "expense"}},
    {"id": "dom-note-idea", "surface": "chat", "text": "帮我记成随记：突然想到 eureka 可以做个成长小岛",
     "expect": {"create": True, "tool": "create_note", "domain": "灵感"}},

    # ═══ C. chat ≠ 闪念 — opinions / pleasantries must NOT auto-create ═══
    {"id": "noc-opinion-1", "surface": "chat", "text": "我觉得水浒传不太好看",
     "expect": {"no_create": True}},
    {"id": "noc-opinion-2", "surface": "chat", "text": "我感觉这部电影有点过誉了",
     "expect": {"no_create": True}},
    {"id": "noc-greet", "surface": "chat", "text": "你好呀，今天天气不错",
     "expect": {"no_create": True}},
    {"id": "noc-tired", "surface": "chat", "text": "唉，今天有点累",
     "expect": {"no_create": True}},
    {"id": "noc-thanks", "surface": "chat", "text": "谢谢你，刚才帮了大忙",
     "expect": {"no_tool": True}},

    # ═══ D. explicit capture — overrides the conversational default ═══
    {"id": "exp-note", "surface": "chat", "text": "帮我记成随记：水浒传不太好看",
     "expect": {"create": True, "tool": "create_note"}},
    {"id": "exp-todo", "surface": "chat", "text": "帮我记一下，明天要交房租",
     "expect": {"create": True, "tool": "create_todo"}},
    {"id": "exp-expense", "surface": "chat", "text": "帮我记一笔，超市买东西 128",
     "expect": {"create": True, "skill": "expense"}},
    {"id": "exp-record-water", "surface": "chat", "text": "帮我记一下今天喝了2000ml水",
     "expect": {"create": True, "skill": "daily_water"}},

    # ═══ E. query, not create ═══
    {"id": "q-list-todo", "surface": "chat", "text": "我有哪些待办",
     "expect": {"query": True, "no_create": True}},
    {"id": "q-month-expense", "surface": "chat", "text": "我这个月一共花了多少钱",
     "expect": {"query": True, "no_create": True}},
    {"id": "q-recent-books", "surface": "chat", "text": "我最近读了哪些书",
     "expect": {"query": True, "no_create": True}},
    {"id": "q-domain-ent", "surface": "chat", "text": "我这个月娱乐方面花了多少",
     "expect": {"query": True, "no_create": True}},
    {"id": "q-water-today", "surface": "chat", "text": "我今天喝了多少水",
     "expect": {"query": True, "no_create": True}},
    {"id": "q-what-notes", "surface": "chat", "text": "我都记过哪些随记",
     "expect": {"query": True, "no_create": True}},
    {"id": "q-running-week", "surface": "chat", "text": "我这周跑步跑了几次",
     "expect": {"query": True, "no_create": True}},

    # ═══ F. report = independent entry — chat only redirects, never generates ═══
    {"id": "rep-expense", "surface": "chat", "text": "帮我出一份这个月的消费复盘报告",
     "expect": {"no_create": True, "redirect": True}},
    {"id": "rep-reading", "surface": "chat", "text": "把我最近的读书记录做成一份复盘文档",
     "expect": {"no_create": True, "redirect": True}},
    {"id": "rep-summary", "surface": "chat", "text": "帮我把这个月的生活做成一份图文总结",
     "expect": {"no_create": True, "redirect": True}},

    # ═══ G. event vs todo 铁律 — single time = todo, full range / all-day = event ═══
    {"id": "evt-single-todo", "surface": "chat", "text": "提醒我明天下午3点给张总打电话",
     "expect": {"create": True, "tool": "create_todo"}},
    {"id": "evt-range-event", "surface": "chat", "text": "明天下午3点到5点和产品团队开会",
     "expect": {"create": True, "event": True}},
    {"id": "evt-allday-event", "surface": "chat", "text": "下周一全天公司团建",
     "expect": {"create": True, "event": True}},
    {"id": "evt-single-todo-2", "surface": "chat", "text": "记一下后天上午9点交方案",
     "expect": {"create": True, "tool": "create_todo"}},

    # ═══ H. contact (first-class entity) ═══
    {"id": "contact-1", "surface": "chat", "text": "记个名片：张三，电话 13800001111，在阿里做产品",
     "expect": {"create": True, "tool": "create_contact"}},
    {"id": "contact-2", "surface": "chat", "text": "今天认识了李四，他在字节做后端，微信 lisi2026",
     "expect": {"create": True, "tool": "create_contact"}},

    # ═══ I. CHAT-ANSWER — external knowledge, NOT the user's data → no tool ═══
    {"id": "ans-explain", "surface": "chat", "text": "简单解释一下什么是区块链",
     "expect": {"no_tool": True}},
    {"id": "ans-research", "surface": "chat", "text": "帮我分析一下国内新能源车行业的格局",
     "expect": {"no_tool": True}},
    {"id": "ans-howto", "surface": "chat", "text": "煮溏心蛋大概要几分钟",
     "expect": {"no_tool": True}},

    # ═══ J. external sync → task (chat calls tool_create_task; routing only) ═══
    {"id": "task-dingtalk", "surface": "chat", "text": "把刚才那段分析同步到钉钉文档",
     "expect": {"tool": "create_task"}},
    {"id": "task-gcal", "surface": "chat", "text": "把明天的会加到我的 Google 日历",
     "expect": {"tool": "create_task"}},
    {"id": "task-notion", "surface": "chat", "text": "把这个想法存到 Notion",
     "expect": {"tool": "create_task"}},

    # ═══ K. flash multi-record (don't drop the quieter record) ═══
    {"id": "flash-2", "surface": "flash", "text": "今天跑了5公里，还喝了500ml水",
     "expect": {"min_cards": 2}},
    {"id": "flash-3", "surface": "flash", "text": "早上喝了杯水，中午吃饭花了35，下午读了20页书",
     "expect": {"min_cards": 3}},
    {"id": "flash-expense-todo", "surface": "flash", "text": "打车花了40，记得明天还要交报告",
     "expect": {"min_cards": 2}},
    {"id": "flash-single", "surface": "flash", "text": "今天跑了三公里",
     "expect": {"min_cards": 1}},
]
