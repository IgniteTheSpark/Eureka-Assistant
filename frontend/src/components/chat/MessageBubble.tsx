import { Wrench, AlertCircle, Bookmark, FileText, ChevronRight, ChevronDown, Loader2 } from "lucide-react";
import { useState } from "react";

import { AssetCardInChat } from "./AssetCardInChat";
import { ReportSheet } from "./ReportSheet";
import { AssetDetailDrawer } from "@/components/asset/AssetDetailDrawer";
import type { ChatMessage, ChatPart } from "@/hooks/useChat";
import type { CardData } from "@/lib/render-spec";

/** A rendered HTML report carried by a tool_render_report tool_result. */
interface ReportData { title: string; html: string }

/**
 * MessageBubble — renders one user or agent message.
 *
 * User bubble: right-aligned, brand-tinted, single line of text.
 * Agent bubble: left-aligned, plain background, contains a sequence of parts
 *               (text / tool_call / tool_result / cards / error) so the
 *               streaming order is preserved.
 *
 * Cards inside agent messages are rendered with the inline SkillCard layout
 * and click-open an AssetDetailDrawer (M1 read-only style).
 */

interface MessageBubbleProps {
  message: ChatMessage;
  /** If user clicks "save as asset" button — wires PrecipitateButton */
  onPrecipitate?: (text: string) => void;
}

export function MessageBubble({ message, onPrecipitate }: MessageBubbleProps) {
  if (message.role === "user") {
    return <UserBubble text={message.text ?? ""} />;
  }
  return <AgentBubble parts={message.parts ?? []} streaming={message.streaming} onPrecipitate={onPrecipitate} />;
}

function UserBubble({ text }: { text: string }) {
  return (
    <div className="flex justify-end">
      <div
        className={[
          "max-w-[85%] md:max-w-[70%]",
          "bg-eu-brand-faint text-eu-text-hi",
          "border border-eu-brand-line",
          "rounded-eu-lg rounded-tr-eu-sm",
          "px-eu-md py-eu-sm",
          "text-eu-base whitespace-pre-wrap break-words",
        ].join(" ")}
      >
        {text}
      </div>
    </div>
  );
}

function AgentBubble({
  parts, streaming, onPrecipitate,
}: { parts: ChatPart[]; streaming?: boolean; onPrecipitate?: (text: string) => void }) {
  const [drawerCard, setDrawerCard] = useState<{ card: CardData; payload: Record<string, unknown>; sourceSessionId: string | null } | null>(null);
  const [openReport, setOpenReport] = useState<ReportData | null>(null);

  // Concatenate all text parts into one string for the "save as asset" action
  const fullText = parts.filter((p): p is Extract<ChatPart, { type: "text" }> => p.type === "text")
                        .map((p) => p.text).join("");

  return (
    <div className="flex justify-start">
      <div className="max-w-[88%] md:max-w-[78%] flex flex-col gap-eu-sm">
        {parts.map((part, idx) => (
          <PartRenderer
            key={idx}
            part={part}
            streaming={streaming}
            isLast={idx === parts.length - 1}
            onOpenCard={(card, payload, sourceSessionId) => setDrawerCard({ card, payload, sourceSessionId: sourceSessionId ?? null })}
            onOpenReport={setOpenReport}
          />
        ))}

        {streaming && parts.length === 0 && (
          <div className="flex items-center gap-1.5 text-eu-sm text-eu-text-lo italic">
            <Loader2 size={12} strokeWidth={1.75} className="animate-spin" />
            分析中…
          </div>
        )}

        {/* Precipitate button only on completed agent messages with text */}
        {!streaming && fullText.length > 8 && onPrecipitate && (
          <button
            type="button"
            onClick={() => onPrecipitate(fullText)}
            className={[
              "self-start mt-1 flex items-center gap-1.5",
              "px-2 py-1 rounded-eu-sm text-eu-xs",
              "text-eu-text-lo hover:text-eu-text-hi hover:bg-eu-surface-hover",
              "border border-dashed border-eu-border hover:border-eu-border-strong",
              "transition-colors duration-eu-fast",
            ].join(" ")}
          >
            <Bookmark size={12} strokeWidth={1.75} />
            沉淀为资产
          </button>
        )}
      </div>

      {drawerCard && (
        <AssetDetailDrawer
          card={drawerCard.card}
          payload={drawerCard.payload}
          sourceSessionId={drawerCard.sourceSessionId}
          onClose={() => setDrawerCard(null)}
        />
      )}

      {openReport && (
        <ReportSheet
          title={openReport.title}
          html={openReport.html}
          onClose={() => setOpenReport(null)}
        />
      )}
    </div>
  );
}

/* ── Per-part renderers ─────────────────────────────────────────────────── */

function PartRenderer({
  part, streaming, isLast, onOpenCard, onOpenReport,
}: {
  part: ChatPart;
  streaming: boolean;
  isLast: boolean;
  onOpenCard: (card: CardData, payload: Record<string, unknown>, sourceSessionId?: string | null) => void;
  onOpenReport: (report: ReportData) => void;
}) {
  if (part.type === "text") {
    // Salvage: deepseek sometimes emits a report's HTML as a raw text message
    // (```html fence / bare <style> doc) instead of calling tool_render_report.
    // The HTML is fine — render it as a proper report card rather than dumping
    // code at the user. While it's still streaming in, show a placeholder.
    if (isHtmlReportText(part.text)) {
      if (streaming && isLast) {
        return (
          <div className="inline-flex items-center gap-1.5 self-start px-2 py-1 rounded-eu-sm text-eu-xs text-eu-accent-amber-fg bg-eu-accent-amber-bg border border-eu-accent-amber-edge">
            <Loader2 size={11} strokeWidth={1.75} className="animate-spin" />
            整理报告中…
          </div>
        );
      }
      const salvaged = extractHtmlReportFromText(part.text);
      if (salvaged) {
        return <ReportReceiptCard report={salvaged} onOpen={() => onOpenReport(salvaged)} />;
      }
    }
    return (
      <div className="text-eu-base text-eu-text whitespace-pre-wrap leading-relaxed">
        {part.text}
        <Cursor />
      </div>
    );
  }
  if (part.type === "tool_call") {
    // Only the in-flight call (last part while streaming) shows a chip — and as
    // an ongoing action ("查询资产中…" + spinner). Once the tool_result lands it
    // follows as its own part and carries the outcome, so a settled tool_call
    // would just be a redundant duplicate chip — render nothing for it.
    if (!(streaming && isLast)) return null;
    return (
      <div
        className={[
          "inline-flex items-center gap-1.5 self-start",
          "px-2 py-1 rounded-eu-sm",
          "text-eu-xs text-eu-accent-amber-fg",
          "bg-eu-accent-amber-bg border border-eu-accent-amber-edge",
        ].join(" ")}
      >
        <Loader2 size={11} strokeWidth={1.75} className="animate-spin" />
        {humanToolLabel(part.name)}中…
      </div>
    );
  }
  if (part.type === "tool_result") {
    // html-summary: a report result renders a compact receipt card (NOT the
    // raw HTML — that opens full-screen in ReportSheet on tap).
    const report = extractReportFromToolResult(part.response);
    if (report) {
      return <ReportReceiptCard report={report} onOpen={() => onOpenReport(report)} />;
    }

    // Extract every card-shaped item the result carries — single asset, single
    // event, OR a list (query_*). Falls back to a tiny "↩ ok" chip only when
    // nothing renderable was returned. Plural results render as a stack.
    const cards = extractCardsFromToolResult(part.response);

    // Query tools return a LIST that's often intermediate (esp. feeding a
    // SUMMARY report). Dumping every card clutters the thread, so collapse to
    // "↩ 查询资产 · 找到 N 项 ▸" and let the user expand to inspect. Create /
    // update / etc. keep showing their (single) card — that IS the answer.
    if (QUERY_TOOLS.has(part.name)) {
      return (
        <CollapsibleQueryResult
          label={humanToolLabel(part.name)}
          cards={cards}
          onOpenCard={onOpenCard}
        />
      );
    }

    if (cards.length === 0) {
      return (
        <div className="text-eu-xs text-eu-text-lo italic">
          ↩ {humanToolLabel(part.name)} 完成
        </div>
      );
    }
    return (
      <div className="flex flex-col gap-eu-sm">
        {cards.map((c, i) => (
          <AssetCardInChat key={i} data={c} onOpen={onOpenCard} />
        ))}
      </div>
    );
  }
  if (part.type === "cards") {
    return (
      <div className="flex flex-col gap-eu-sm">
        {part.cards.map((c, i) => (
          <AssetCardInChat key={i} data={c} onOpen={onOpenCard} />
        ))}
      </div>
    );
  }
  if (part.type === "error") {
    return (
      <div
        className={[
          "inline-flex items-center gap-1.5 self-start",
          "px-2 py-1 rounded-eu-sm",
          "text-eu-xs text-eu-accent-red-fg",
          "bg-eu-accent-red-bg border border-eu-accent-red-edge",
        ].join(" ")}
      >
        <AlertCircle size={11} strokeWidth={1.75} />
        {part.message}
      </div>
    );
  }
  return null;
}

function Cursor() {
  // Subtle blinking caret to suggest streaming. Tailwind animate-pulse.
  return (
    <span className="inline-block w-0.5 h-3 -mb-0.5 ml-0.5 bg-eu-brand animate-pulse opacity-60" />
  );
}

/**
 * Unwrap FastMCP-style nested response shapes into a list of card-shaped
 * dicts. Backend tools return one of:
 *
 *   1. Single asset/event/contact/task    → 1-card list
 *   2. Plural list `{assets|contacts|events|tasks|input_turns: [...]}`
 *      (query_* tools)                    → N-card list
 *   3. FastMCP `{content: [{text: '<JSON>'}], structuredContent: {...}}`
 *      wrap around either of the above
 *
 * Each card dict is tagged with `card_type` (event/contact/task) when the
 * id field implies one, so AssetCardInChat → synthesizeSpec picks the right
 * render. Asset responses carry user_skill_name from the backend already.
 *
 * Returns [] when the response shape has no renderable cards (e.g. delete_*
 * returns just `{ok, asset_id}` — we render the small "↩ 完成" chip instead).
 */
function extractCardsFromToolResult(response: Record<string, unknown>): Record<string, unknown>[] {
  if (!response) return [];

  // Walk all shapes that might contain the actual payload.
  const candidates: Record<string, unknown>[] = [response];
  const sc = response.structuredContent;
  if (sc && typeof sc === "object" && !Array.isArray(sc)) {
    candidates.push(sc as Record<string, unknown>);
  }
  const content = response.content;
  if (Array.isArray(content) && content[0] && typeof content[0] === "object") {
    const text = (content[0] as Record<string, unknown>).text;
    if (typeof text === "string") {
      try {
        const parsed = JSON.parse(text);
        if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
          candidates.push(parsed as Record<string, unknown>);
        }
      } catch { /* ignore */ }
    }
  }

  for (const c of candidates) {
    // Plural query result — assets / events / contacts / tasks / input_turns
    for (const k of ["assets", "events", "contacts", "tasks", "input_turns"] as const) {
      const arr = c[k];
      if (Array.isArray(arr) && arr.length > 0) {
        return arr
          .map((item) => (item && typeof item === "object"
            ? tagByIdField(item as Record<string, unknown>)
            : null))
          .filter((x): x is Record<string, unknown> => x !== null);
      }
    }
    // Single result
    const single = tagByIdField(c);
    if (single) return [single];
  }
  return [];
}

/**
 * Detect a tool_render_report result and pull out {title, html}. Same
 * FastMCP-envelope walk as extractCardsFromToolResult — the payload may sit
 * at the top level, in structuredContent, or JSON-encoded in content[0].text.
 * Returns null for any non-report tool_result.
 */
/** Strip a leading ```html fence + a leading "<!-- … -->" comment so we can
 *  sniff the first real tag. */
function stripReportPreamble(text: string): string {
  return text
    .trim()
    .replace(/^```[a-zA-Z]*\s*/, "")    // ```html / ```
    .replace(/^<!--[\s\S]*?-->\s*/, "") // <!-- language: html -->
    .trim();
}

/** Does this text message look like a (possibly still-streaming) HTML report
 *  the model emitted inline instead of via tool_render_report? Anchored at the
 *  start so a normal prose answer that merely mentions a tag won't match. */
function isHtmlReportText(text: string): boolean {
  if (!text || (!text.includes("<style") && !text.toLowerCase().includes("<!doctype") && !text.toLowerCase().includes("<html"))) {
    return false;
  }
  return /^(<!doctype|<html|<style)/i.test(stripReportPreamble(text));
}

/** Extract {title, html} from an inline-HTML report text once it's complete. */
function extractHtmlReportFromText(text: string): ReportData | null {
  let html = stripReportPreamble(text).replace(/```\s*$/, "").trim();
  if (html.length < 120) return null;          // too short to be a real report
  if (!/^(<!doctype|<html|<style)/i.test(html.toLowerCase())) return null;
  const h1 = html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i);
  const title = h1 ? h1[1].replace(/<[^>]+>/g, "").trim().slice(0, 60) : "总结报告";
  return { title: title || "总结报告", html };
}

function extractReportFromToolResult(response: Record<string, unknown>): ReportData | null {
  if (!response) return null;

  const candidates: Record<string, unknown>[] = [response];
  const sc = response.structuredContent;
  if (sc && typeof sc === "object" && !Array.isArray(sc)) {
    candidates.push(sc as Record<string, unknown>);
  }
  const content = response.content;
  if (Array.isArray(content) && content[0] && typeof content[0] === "object") {
    const text = (content[0] as Record<string, unknown>).text;
    if (typeof text === "string") {
      try {
        const parsed = JSON.parse(text);
        if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
          candidates.push(parsed as Record<string, unknown>);
        }
      } catch { /* ignore */ }
    }
  }

  for (const c of candidates) {
    if (c.kind === "report" && typeof c.html === "string" && c.html.length > 0) {
      return {
        title: typeof c.title === "string" && c.title ? c.title : "报告",
        html:  c.html,
      };
    }
  }
  return null;
}

/**
 * ReportReceiptCard — the compact in-chat stand-in for a generated report.
 * The chat never shows the raw HTML (too cramped); this card is the handle
 * that opens the full-screen ReportSheet on tap.
 */
function ReportReceiptCard({ report, onOpen }: { report: ReportData; onOpen: () => void }) {
  return (
    <button
      type="button"
      onClick={onOpen}
      className={[
        "self-start w-full max-w-[280px] flex items-center gap-eu-md",
        "px-eu-md py-eu-sm rounded-eu-md text-left",
        "bg-eu-brand-faint border border-eu-brand-line",
        "hover:brightness-110 active:scale-[0.99]",
        "transition-all duration-eu-fast",
      ].join(" ")}
    >
      <span
        className="shrink-0 h-9 w-9 rounded-eu-md flex items-center justify-center"
        style={{
          background: "rgba(196,168,255,0.14)",
          border: "1px solid rgba(196,168,255,0.34)",
          color: "#c4a8ff",
        }}
      >
        <FileText size={17} strokeWidth={1.75} />
      </span>
      <div className="flex-1 min-w-0">
        <div className="text-eu-base text-eu-text-hi font-medium truncate">{report.title}</div>
        <div className="text-eu-xs text-eu-text-lo">点击查看完整报告</div>
      </div>
      <ChevronRight size={16} strokeWidth={1.75} className="shrink-0 text-eu-text-lo" />
    </button>
  );
}

/** Stamp the response with the right card_type so AssetCardInChat can pick
 *  the matching render_spec (synthesizeSpec(card_type) keys off this). */
function tagByIdField(d: Record<string, unknown>): Record<string, unknown> | null {
  // task_id BEFORE asset_id: a create_task result carries BOTH (asset_id = the
  // placeholder external_ref asset). If asset_id won, the card got no card_type
  // and rendered as a generic「资产」. Tagging it "task" routes it through the
  // lifecycle card (⏳ → MCP icon + status badge).
  if (d.task_id)       return { ...d, card_type: "task" };
  if (d.asset_id)      return d;                      // user_skill_name carried
  if (d.event_id)      return { ...d, card_type: "event" };
  if (d.contact_id)    return { ...d, card_type: "contact" };
  if (d.input_turn_id) return { ...d, card_type: "input_turn" };
  return null;
}

/** Translate machine tool names to Chinese labels for the chips. */
const TOOL_LABEL: Record<string, string> = {
  tool_create_asset:      "创建资产",
  tool_update_asset:      "更新资产",
  tool_query_asset:       "查询资产",
  tool_query_digest:      "汇总数据",
  tool_delete_asset:      "删除资产",
  tool_create_event:      "创建事件",
  tool_update_event:      "更新事件",
  tool_query_event:       "查询事件",
  tool_get_event:         "读取事件",
  tool_delete_event:      "删除事件",
  tool_add_event_attendee:"添加事件参与者",
  tool_link_event_file:   "关联事件文件",
  tool_create_contact:    "创建联系人",
  tool_update_contact:    "更新联系人",
  tool_query_contact:     "查询联系人",
  tool_delete_contact:    "删除联系人",
  tool_query_input_turn:  "查找语音/输入",
  tool_get_input_turn:    "取出原文",
  tool_create_task:       "触发外部任务",
  tool_render_report:     "生成报告",
};
function humanToolLabel(name: string): string {
  return TOOL_LABEL[name] ?? name;
}

/** Tools whose result is a (possibly large) LIST — collapsed in chat. */
const QUERY_TOOLS = new Set([
  "tool_query_asset",
  "tool_query_event",
  "tool_query_contact",
  "tool_query_input_turn",
]);

/**
 * CollapsibleQueryResult — a query's matched cards, collapsed to a one-line
 * "↩ 查询资产 · 找到 N 项" chip you can expand. Keeps intermediate query data
 * (especially when it's feeding a SUMMARY report) from flooding the thread,
 * while staying inspectable on demand.
 */
function CollapsibleQueryResult({
  label, cards, onOpenCard,
}: {
  label: string;
  cards: Record<string, unknown>[];
  onOpenCard: (card: CardData, payload: Record<string, unknown>, sourceSessionId?: string | null) => void;
}) {
  const [open, setOpen] = useState(false);
  if (cards.length === 0) {
    return <div className="text-eu-xs text-eu-text-lo italic">↩ {label} · 没有结果</div>;
  }
  return (
    <div className="flex flex-col gap-eu-sm self-start">
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        className="inline-flex items-center gap-1 self-start text-eu-xs text-eu-text-lo hover:text-eu-text-mid transition-colors"
      >
        {open
          ? <ChevronDown size={12} strokeWidth={2} />
          : <ChevronRight size={12} strokeWidth={2} />}
        ↩ {label} · 找到 {cards.length} 项
      </button>
      {open && (
        <div className="flex flex-col gap-eu-sm">
          {cards.map((c, i) => (
            <AssetCardInChat key={i} data={c} onOpen={onOpenCard} />
          ))}
        </div>
      )}
    </div>
  );
}
