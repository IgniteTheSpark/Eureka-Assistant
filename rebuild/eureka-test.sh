# Eureka demo 测试 helper
# ─────────────────────────────────────────────────────────────────────
# 用法:
#   source /Users/admin/workwork/eureka-staff/bizcard/docs/rebuild/eureka-test.sh
#
# 然后用 eu_xxx 系列命令测试。「当前 session_id」保存在 /tmp/eureka_session,
# 跨终端 / 跨命令复用,你不用记 UUID。
#
# 一眼看现状:    eu_status
# 新建 chat:     eu_chat "帮我创建一个明天下午6点的饭局待办"
# 接着改:        eu_more "把刚才那个改成 4 点"   ← 用同一个 session
# 闪念多意图:    eu_flash "今晚6点跟客户开会会议室B,会前准备PPT,午餐花了85"
# 事件锚定 chat: eu_event_chat "<event_id>" "这会需要准备什么?"
# 设计 skill:    eu_design "我想记录每天跑步"
# 列出 sessions: eu_sessions
# 列出 events:   eu_events
# 列出 assets:   eu_assets
# 任意 SQL:      eu_db "SELECT ..."
# 清库重建:      eu_reset       ← 删一切,重 migrate + seed(!)
# ─────────────────────────────────────────────────────────────────────

EUREKA_API="${EUREKA_API:-http://localhost:8000}"
EUREKA_ROOT="/Users/admin/workwork/eureka-staff/bizcard/Eureka-BrandNew"
EUREKA_SESSION_FILE="/tmp/eureka_session"


# 颜色(可选)
_eu_bold()  { printf "\033[1m%s\033[0m\n" "$*"; }
_eu_dim()   { printf "\033[2m%s\033[0m\n" "$*"; }
_eu_red()   { printf "\033[31m%s\033[0m\n" "$*"; }
_eu_green() { printf "\033[32m%s\033[0m\n" "$*"; }


# ─── 基础 ────────────────────────────────────────────────────────────

eu_health() {
    curl -sf "$EUREKA_API/health" | python3 -m json.tool 2>/dev/null \
        || _eu_red "backend 不在线 ($EUREKA_API)"
}

# 显示当前缓存的 session_id(从 /tmp/eureka_session 读)
eu_session() {
    if [ -f "$EUREKA_SESSION_FILE" ]; then
        cat "$EUREKA_SESSION_FILE"
    else
        echo ""
    fi
}

# 整体状态:health + 当前 session + 各表计数
eu_status() {
    _eu_bold "=== backend ==="
    eu_health
    echo ""
    _eu_bold "=== 当前 chat session(缓存在 $EUREKA_SESSION_FILE)==="
    local sid="$(eu_session)"
    if [ -n "$sid" ]; then
        _eu_green "$sid"
    else
        _eu_dim "(无,下次 eu_chat 会自动新建)"
    fi
    echo ""
    _eu_bold "=== DB 各表计数 ==="
    eu_db "SELECT 'sessions' AS t, COUNT(*) FROM sessions
        UNION ALL SELECT 'input_turns', COUNT(*) FROM input_turns
        UNION ALL SELECT 'messages', COUNT(*) FROM messages
        UNION ALL SELECT 'assets', COUNT(*) FROM assets
        UNION ALL SELECT 'events', COUNT(*) FROM events
        UNION ALL SELECT 'contacts', COUNT(*) FROM contacts;"
}

# 清当前 session 缓存(下次 eu_chat 会新建)
eu_session_clear() {
    rm -f "$EUREKA_SESSION_FILE"
    _eu_dim "session cache cleared"
}


# ─── chat(自动记 session_id)────────────────────────────────────────

# 新建 chat 或继续当前缓存里的 chat
eu_chat() {
    local text="$*"
    if [ -z "$text" ]; then _eu_red "用法: eu_chat \"<你的话>\""; return 1; fi
    local sid="$(eu_session)"
    local body
    if [ -n "$sid" ]; then
        body=$(python3 -c "import json; print(json.dumps({'session_id': '$sid', 'user_text': '''$text'''}))")
        _eu_dim "→ 继续 session $sid"
    else
        body=$(python3 -c "import json; print(json.dumps({'user_text': '''$text'''}))")
        _eu_dim "→ 新建 chat session"
    fi
    _eu_run_chat "$body"
}

# 强制新建 chat session(不管缓存)
eu_chat_new() {
    eu_session_clear
    eu_chat "$@"
}

# 接着说(语义糖,跟 eu_chat 一样,前提是缓存里已有 session)
eu_more() {
    if [ ! -f "$EUREKA_SESSION_FILE" ]; then
        _eu_red "没有当前 session;先 eu_chat \"...\""; return 1
    fi
    eu_chat "$@"
}

# 内部:发送 chat 请求,流式打印 + 抓 session_id 缓存
_eu_run_chat() {
    local body="$1"
    local resp
    resp=$(curl -sN -X POST "$EUREKA_API/api/chat" \
        -H "Content-Type: application/json" -d "$body" 2>&1)
    echo "$resp" | _eu_format_sse
    # 抓 session_id 缓存起来
    local sid
    sid=$(echo "$resp" | grep -m1 '"session_id"' | python3 -c "
import sys, re
m = re.search(r'\"session_id\":\s*\"([0-9a-f-]+)\"', sys.stdin.read())
if m: print(m.group(1))
" 2>/dev/null)
    if [ -n "$sid" ]; then echo "$sid" > "$EUREKA_SESSION_FILE"; fi
}


# ─── flash(语音多意图)───────────────────────────────────────────

eu_flash() {
    local text="$*"
    if [ -z "$text" ]; then _eu_red "用法: eu_flash \"<你说的话>\""; return 1; fi
    local body
    body=$(python3 -c "import json; print(json.dumps({'text': '''$text''', 'source': 'voice'}))")
    local resp
    resp=$(curl -s -X POST "$EUREKA_API/api/flash" \
        -H "Content-Type: application/json" -d "$body")
    echo "$resp" | python3 -m json.tool
    # 缓存 session_id,让 eu_more 能续聊(v1.3 混合模态:同 session 内 typed 走 Assistant)
    local sid
    sid=$(echo "$resp" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('session_id', ''))
except Exception:
    pass
")
    if [ -n "$sid" ]; then
        echo "$sid" > "$EUREKA_SESSION_FILE"
        _eu_dim "→ session $sid 已缓存(eu_more 可续聊)"
    fi
}


# ─── event-anchored chat(v1.4)─────────────────────────────────────

eu_event_chat() {
    local eid="$1"; shift
    local text="$*"
    if [ -z "$eid" ] || [ -z "$text" ]; then
        _eu_red "用法: eu_event_chat <event_id> \"<问什么>\""
        _eu_dim "可以先 eu_events 看哪个 event_id"
        return 1
    fi
    eu_session_clear   # event-anchored 一律新会话
    local body
    body=$(python3 -c "import json; print(json.dumps({'event_id': '$eid', 'user_text': '''$text'''}))")
    _eu_run_chat "$body"
}

# 找最新一个 event_id 然后挂 chat
eu_event_chat_latest() {
    local text="$*"
    if [ -z "$text" ]; then _eu_red "用法: eu_event_chat_latest \"<问什么>\""; return 1; fi
    local eid
    eid=$(curl -s "$EUREKA_API/api/events?limit=1" \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['events'][0]['event_id']) if d.get('events') else print('')")
    if [ -z "$eid" ]; then _eu_red "没有 event 可用"; return 1; fi
    _eu_dim "→ 锚定到 latest event $eid"
    eu_event_chat "$eid" "$text"
}


# ─── design agent(加 skill)─────────────────────────────────────────

eu_design() {
    local desc="$*"
    if [ -z "$desc" ]; then _eu_red "用法: eu_design \"<想记录什么>\""; return 1; fi
    local body
    body=$(python3 -c "import json; print(json.dumps({'description': '''$desc'''}))")
    curl -s -X POST "$EUREKA_API/api/skills" \
        -H "Content-Type: application/json" -d "$body" | python3 -m json.tool
}


# ─── 列表查询 ─────────────────────────────────────────────────────

eu_sessions() {
    curl -s "$EUREKA_API/api/sessions?limit=15" | python3 -m json.tool
}

eu_events() {
    curl -s "$EUREKA_API/api/events?limit=15" | python3 -m json.tool
}

eu_assets() {
    curl -s "$EUREKA_API/api/assets?limit=15" | python3 -m json.tool
}

eu_skills() {
    curl -s "$EUREKA_API/api/skills" | python3 -m json.tool
}

# 时间线(Schedule 「全部」tab 的数据源)
eu_timeline() {
    local args=""
    [ -n "$1" ] && args="?$1"
    curl -s "$EUREKA_API/api/timeline$args" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f'ok={d[\"ok\"]} count={d[\"count\"]}')
print(f'{\"kind\":12s} {\"effective_at\":28s} {\"title\":40s} extras')
print('-'*120)
for it in d['items'][:30]:
    extras = ''
    if it['kind'] == 'asset': extras = f'skill={it.get(\"skill_name\")}'
    elif it['kind'] == 'event': extras = f'loc={it.get(\"location\",\"-\")}'
    elif it['kind'] == 'input_turn': extras = f'src={it.get(\"source\")}'
    title = (it['title'] or '').replace(chr(10),' ')[:38]
    print(f'{it[\"kind\"]:12s} {it[\"effective_at\"]:28s} {title:40s} {extras}')
"
}

eu_contacts() {
    curl -s "$EUREKA_API/api/contacts" | python3 -m json.tool
}

# session 详情(默认当前缓存的 session;可传别的 id)
eu_session_detail() {
    local sid="${1:-$(eu_session)}"
    if [ -z "$sid" ]; then _eu_red "没指定 session_id 也没缓存"; return 1; fi
    curl -s "$EUREKA_API/api/sessions/$sid" | python3 -m json.tool
}

# 看当前 session 的 message 历史(你跟 agent 都说了什么)
eu_messages() {
    local sid="${1:-$(eu_session)}"
    if [ -z "$sid" ]; then _eu_red "没指定 session_id 也没缓存"; return 1; fi
    curl -s "$EUREKA_API/api/sessions/$sid/messages" | python3 -m json.tool
}


# ─── DB 直查 ──────────────────────────────────────────────────────

eu_db() {
    local q="$*"
    if [ -z "$q" ]; then _eu_red "用法: eu_db \"<SQL>\""; return 1; fi
    docker compose -f "$EUREKA_ROOT/docker-compose.yml" exec db \
        psql -U eureka -d eureka -c "$q"
}

# 看最近 10 条 input_turn
eu_turns() {
    eu_db "SELECT id, session_id, source, LEFT(text, 60) AS text FROM input_turns ORDER BY created_at DESC LIMIT 10;"
}


# ─── 危险操作 ─────────────────────────────────────────────────────

# 清库,完全重来
eu_reset() {
    _eu_red "!! 这会删除所有数据 + 重 migrate + 重 seed !!"
    printf "确认?[y/N] "; read confirm
    if [ "$confirm" != "y" ]; then echo "取消"; return; fi
    cd "$EUREKA_ROOT" || return 1
    docker compose down -v
    docker compose up -d db
    sleep 8
    docker compose run --rm backend alembic upgrade head
    docker compose run --rm backend python -m db.seed
    docker compose up -d backend
    sleep 5
    eu_session_clear
    _eu_green "✅ 清库完成,backend 重启,session 缓存清空"
}

# 重启 backend(不动数据)
eu_restart() {
    cd "$EUREKA_ROOT" || return 1
    docker compose restart backend
    sleep 4
    eu_health
}

# 看 backend 实时日志
eu_logs() {
    cd "$EUREKA_ROOT" || return 1
    docker compose logs -f --tail=40 backend
}


# ─── SSE 流格式化(给 chat 用)──────────────────────────────────

_eu_format_sse() {
    # 把 SSE 流读进来,event/data 配对,JSON pretty-print
    python3 -c "
import sys, json, re
buf, cur_event = '', None
for line in sys.stdin:
    line = line.rstrip()
    if line.startswith('event:'):
        cur_event = line.split(':', 1)[1].strip()
    elif line.startswith('data:'):
        data_str = line.split(':', 1)[1].strip()
        try:
            data = json.loads(data_str)
            print(f'\033[36m▸ {cur_event}\033[0m  {json.dumps(data, ensure_ascii=False)[:250]}')
        except Exception:
            print(f'  {cur_event}  (parse err)  {data_str[:150]}')
    elif not line:
        cur_event = None
"
}


# ─── 异步任务(task-skill → 第三方 MCP) ─────────────────────────

eu_tasks() {
    # 列最近 20 条任务,显示状态 / 目标 MCP / 外部链接
    curl -s "$EUREKA_API/api/tasks?limit=20" | python3 -c "
import sys, json
r = json.load(sys.stdin)
if not r.get('tasks'):
    print('(no tasks)'); sys.exit(0)
for t in r['tasks']:
    icon = {'pending':'⏳','running':'⏳','done':'✅','failed':'❌'}.get(t['status'],'?')
    line = f\"  {icon} {t['id'][:8]}  {t['status']:8} {(t.get('mcp_target') or '-'):20} {(t.get('user_text','') or '')[:50]}\"
    print(line)
    if t.get('error_message'): print(f'           error: {t[\"error_message\"][:100]}')
    payload = t.get('result_asset_payload') or {}
    if payload.get('external_url'):
        print(f'           {payload[\"external_url\"]}')
"
}

eu_task() {
    # 看单个 task 的详细状态(传 task_id 前 8 位即可)
    local tid=${1:?usage: eu_task <task_id_prefix>}
    local full=$(curl -s "$EUREKA_API/api/tasks?limit=50" | python3 -c "
import sys, json
r = json.load(sys.stdin)
for t in r.get('tasks', []):
    if t['id'].startswith('$tid'):
        print(t['id']); break")
    if [ -z "$full" ]; then echo "task $tid not found"; return 1; fi
    curl -s "$EUREKA_API/api/tasks/$full" | python3 -m json.tool
}

eu_task_wait() {
    # 阻塞等一个 task 跑完,然后显示结果(传 task_id 前 8 位即可)
    local tid=${1:?usage: eu_task_wait <task_id_prefix>}
    local full=$(curl -s "$EUREKA_API/api/tasks?limit=50" | python3 -c "
import sys, json
r = json.load(sys.stdin)
for t in r.get('tasks', []):
    if t['id'].startswith('$tid'):
        print(t['id']); break")
    if [ -z "$full" ]; then echo "task $tid not found"; return 1; fi
    printf "waiting for task %s ..." "${full:0:8}"
    until curl -s "$EUREKA_API/api/tasks/$full" | python3 -c "
import sys, json
exit(0 if json.load(sys.stdin)['task']['status'] in ('done','failed') else 1)" 2>/dev/null; do
        printf "."; sleep 3
    done
    echo " done"
    eu_task "${full:0:8}"
}

eu_mcp() {
    # 列当前启用的第三方 MCP(从 backend 容器里读 mcp_config)
    docker compose exec -T backend python3 -c "
from agents.mcp_config import MCP_SERVERS
print('enabled MCPs:')
for name, cfg in MCP_SERVERS.items():
    print(f'  {name}  ({cfg.get(\"transport\",\"stdio\")})')"
}


# ─── 帮助 ─────────────────────────────────────────────────────────

eu_help() {
    cat <<'HELP'
eureka 测试 helper 命令:

  健康 / 状态
    eu_health              backend 是否在线
    eu_status              backend + 当前 session + 各表计数

  chat(自动管 session_id)
    eu_chat "..."          新建或继续(看缓存)
    eu_chat_new "..."      强制新建
    eu_more "..."          接着说(必须有缓存的 session)
    eu_session             看当前缓存的 session_id
    eu_session_clear       清缓存

  闪念多意图(走 Flash Pipeline)
    eu_flash "..."

  event-anchored chat(v1.4)
    eu_events                              列所有事件
    eu_event_chat <event_id> "..."         锚定指定 event 发问
    eu_event_chat_latest "..."             锚定最新 event 发问

  设计 agent
    eu_design "我想记录每天跑步"

  列表查询(API 路径)
    eu_sessions       eu_events       eu_assets
    eu_skills         eu_contacts
    eu_session_detail [sid]   eu_messages [sid]
    eu_turns                      最近 10 条 input_turn

  异步任务(第三方 MCP)
    eu_tasks                        列最近 20 个 task(状态 + 外链)
    eu_task <id-prefix>            一个 task 的完整状态
    eu_task_wait <id-prefix>       阻塞等到 task 跑完
    eu_mcp                         列当前启用的 MCP

  DB 直查
    eu_db "SELECT ..."

  运维
    eu_restart        重启 backend(不动数据)
    eu_reset          清库重建(危险!)
    eu_logs           backend 实时日志
HELP
}


_eu_green "eureka helper loaded — 输入 eu_help 看命令"
