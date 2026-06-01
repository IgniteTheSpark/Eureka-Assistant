import { useState } from "react";
import { Check, Loader2, RotateCcw, Sparkles, Wand2, X } from "lucide-react";
import { useSWRConfig } from "swr";

import { useModalMount } from "@/context/ModalContext";
import { ApiError, apiFetch } from "@/lib/api";
import { buildCard } from "@/lib/render-spec";
import type { AccentColor, RenderSpec } from "@/lib/render-spec";
import { SkillCard } from "@/components/skill/SkillCard";

/**
 * AddSkillWizard — M5. "由 AI 帮你设计卡片".
 *
 * 4-step flow (Phase D §二.1): 描述 → 生成 → 预览 → 注册.
 *
 *   describe : user types a natural-language description of what they want to
 *              track ("我想记录跑步训练").
 *   generate : POST /api/skills { description } → the backend design_agent
 *              (Gemini, structured output) returns a draft skill —
 *              { name, display_name, payload_schema, render_spec, sample_payload }.
 *   preview  : render a LIVE SkillCard from draft.render_spec + sample_payload
 *              (same interpreter the rest of the app uses), show the captured
 *              fields, and let the user tweak display_name / icon / accent.
 *   register : POST /api/skills/confirm → creates the UserSkill, refresh the
 *              registry, close. 409 → "已存在同名技能".
 *
 * Same bottom-sheet shell as ContactForm / EventForm so it feels native to the
 * iPhone-frame app.
 */

interface SkillDraft {
  name: string;
  display_name: string;
  payload_schema: Record<string, unknown>;
  render_spec: RenderSpec;
  sample_payload: Record<string, unknown>;
}

/**
 * One step in the guided card flow. Backend's clarifier emits 1-3 of these
 * when the description is too vague to design a good skill from.
 */
interface ClarifyQuestion {
  key:         string;
  prompt:      string;
  type:        "choice" | "text";
  options?:    string[];
  placeholder?: string;
}

interface AddSkillWizardProps {
  onClose: () => void;
  onCreated?: (name: string) => void;
}

const ACCENT_SWATCH: Record<AccentColor, string> = {
  blue:    "#6f9eff",
  amber:   "#f0b86f",
  green:   "#6fe0a0",
  red:     "#ff8a8a",
  purple:  "#c4a8ff",
  gray:    "#9aa3b2",
  neutral: "#c8ced8",
};
const ACCENTS = Object.keys(ACCENT_SWATCH) as AccentColor[];

const EXAMPLES = ["跑步训练记录", "读书笔记", "每天喝水量", "面试复盘"];

export function AddSkillWizard(props: AddSkillWizardProps) {
  useModalMount();
  return <Body {...props} />;
}

function Body({ onClose, onCreated }: AddSkillWizardProps) {
  const { mutate } = useSWRConfig();

  const [step, setStep] = useState<"describe" | "clarify" | "preview">("describe");
  const [description, setDescription] = useState("");
  const [busy, setBusy] = useState(false); // generating (describe) / confirming (preview)
  const [error, setError] = useState<string | null>(null);

  const [draft, setDraft] = useState<SkillDraft | null>(null);
  // Guided card flow: when the description is vague, the backend returns
  // 1-3 questions instead of a draft. The wizard renders them, collects
  // answers, and POSTs back to /api/skills with `answers` to actually
  // generate the draft.
  const [questions, setQuestions] = useState<ClarifyQuestion[]>([]);
  const [answers, setAnswers] = useState<Record<string, string>>({});
  // Editable overrides applied on top of the AI draft in the preview step.
  const [displayName, setDisplayName] = useState("");
  const [accent, setAccent] = useState<AccentColor>("blue");
  const [icon, setIcon] = useState("");
  // Field-to-slot mapping: lets the user override the AI's choice of which
  // payload field is primary (= big card title = calendar bullet title),
  // secondary (= subtitle), or meta (= pills below). The big card and the
  // calendar bullet share a single primary so the UI never disagrees with
  // itself. See "## Unified display rule" banner in PreviewStep.
  const [slots, setSlots] = useState<SlotMap>({});

  function applyDraft(d: SkillDraft) {
    setDraft(d);
    setDisplayName(d.display_name ?? "");
    setAccent(d.render_spec?.accent_color ?? "blue");
    setIcon(d.render_spec?.icon ?? "•");
    setSlots(initialSlots(d));
    setStep("preview");
  }

  async function generate() {
    const desc = description.trim();
    if (!desc || busy) return;
    setBusy(true);
    setError(null);
    try {
      // Stage 1: ask the backend whether the description needs clarification.
      // It either returns a draft directly or a list of clarifying questions.
      const resp = await apiFetch<{
        ok: boolean;
        draft?: SkillDraft;
        questions?: ClarifyQuestion[];
        error?: string;
      }>(
        "/api/skills",
        { method: "POST", body: { description: desc }, timeoutMs: 60_000 },
      );
      if (!resp.ok) throw new Error(resp.error ?? "生成失败,请重试");
      if (resp.draft) {
        applyDraft(resp.draft);
        return;
      }
      const qs = resp.questions ?? [];
      if (qs.length > 0) {
        setQuestions(qs);
        // Pre-fill choice questions with the first option so the user just
        // confirms or changes — saves a click in the common case.
        const init: Record<string, string> = {};
        for (const q of qs) {
          if (q.type === "choice" && q.options?.length) init[q.key] = q.options[0];
        }
        setAnswers(init);
        setStep("clarify");
        return;
      }
      // No draft and no questions — unlikely, surface a clear error.
      throw new Error("生成失败,请重试");
    } catch (e) {
      setError(errMsg(e));
    } finally {
      setBusy(false);
    }
  }

  async function submitClarify() {
    if (busy) return;
    setBusy(true);
    setError(null);
    try {
      const payload = {
        description: description.trim(),
        answers: questions.map((q) => ({
          key:   q.key,
          value: (answers[q.key] ?? "").trim(),
        })),
      };
      const resp = await apiFetch<{ ok: boolean; draft?: SkillDraft; error?: string }>(
        "/api/skills",
        { method: "POST", body: payload, timeoutMs: 60_000 },
      );
      if (!resp.ok || !resp.draft) throw new Error(resp.error ?? "生成失败,请重试");
      applyDraft(resp.draft);
    } catch (e) {
      setError(errMsg(e));
    } finally {
      setBusy(false);
    }
  }

  async function confirm() {
    if (!draft || busy) return;
    setBusy(true);
    setError(null);
    try {
      const render_spec: RenderSpec = composeRenderSpec(draft.render_spec, {
        accent, icon, slots,
      });
      const resp = await apiFetch<{ ok: boolean; user_skill_id?: string; name?: string; error?: string }>(
        "/api/skills/confirm",
        {
          method: "POST",
          body: {
            name: draft.name,
            display_name: displayName.trim() || draft.display_name,
            payload_schema: draft.payload_schema,
            render_spec,
            queryable_fields: [],
          },
        },
      );
      if (!resp.ok) throw new Error(resp.error ?? "注册失败");
      await mutate((key) => typeof key === "string" && key.startsWith("/api/skills"));
      onCreated?.(draft.name);
      onClose();
    } catch (e) {
      if (e instanceof ApiError && e.status === 409) {
        setError("已存在同名技能 — 换个描述再生成。");
      } else {
        setError(errMsg(e));
      }
      setBusy(false);
    }
  }

  function backToDescribe() {
    setStep("describe");
    setQuestions([]);
    setAnswers({});
    setError(null);
  }

  // Live preview card: feed the (possibly tweaked) spec + the AI's sample
  // payload through the same interpreter the real cards use. composeRenderSpec
  // bakes in the user's slot mapping + label/unit overrides so the preview
  // updates the instant the user picks a different field as 主标题.
  const previewCard =
    draft &&
    buildCard({
      payload: draft.sample_payload ?? {},
      spec: composeRenderSpec(draft.render_spec, {
        accent, icon, slots,
      }),
      assetId: null,
      cardType: draft.name,
      displayName: displayName || draft.display_name,
    });

  return (
    <div
      className="fixed inset-0 z-50 bg-eu-bg/92 backdrop-blur-md eu-fade-in"
      onClick={busy ? undefined : onClose}
    >
      <aside
        onClick={(e) => e.stopPropagation()}
        className={[
          "fixed inset-x-0 bottom-0 max-h-[90vh] rounded-t-eu-xl",
          "eu-sheet-up",
          "bg-eu-surface-raised border-t border-eu-border",
          "shadow-eu-lg pt-eu-md pb-safe overflow-y-auto eu-noscroll",
          "flex flex-col gap-eu-md",
        ].join(" ")}
      >
        <div className="h-1 w-12 rounded-full bg-eu-rule mx-auto" />

        {/* Header */}
        <header className="flex items-start gap-eu-md px-eu-lg">
          <div
            className="shrink-0 h-10 w-10 rounded-eu-md flex items-center justify-center text-eu-lg"
            style={{
              background: "rgba(196,168,255,0.10)",
              border: "1px solid rgba(196,168,255,0.32)",
              color: "#c4a8ff",
              boxShadow: "0 0 12px rgba(196,168,255,0.30)",
            }}
          >
            <Sparkles size={18} strokeWidth={1.75} />
          </div>
          <div className="flex-1 min-w-0">
            <div className="text-eu-xs uppercase tracking-eu-caps text-eu-text-lo font-mono">
              新技能 · AI 设计
            </div>
            <div className="text-eu-lg text-eu-text-hi font-medium tracking-tight mt-0.5">
              {step === "describe" ? "想记录点什么?"
                : step === "clarify" ? "再帮 AI 想清楚一下"
                : "预览这张卡片"}
            </div>
          </div>
          <button
            type="button"
            aria-label="关闭"
            onClick={onClose}
            disabled={busy}
            className="shrink-0 p-1.5 rounded-eu-sm text-eu-text-mid hover:text-eu-text-hi hover:bg-eu-surface-hover disabled:opacity-40"
          >
            <X size={18} strokeWidth={1.75} />
          </button>
        </header>

        {step === "describe" && (
          <DescribeStep
            description={description}
            setDescription={setDescription}
            busy={busy}
            onGenerate={generate}
          />
        )}

        {step === "clarify" && (
          <ClarifyStep
            description={description}
            questions={questions}
            answers={answers}
            setAnswers={setAnswers}
            busy={busy}
            onBack={backToDescribe}
            onSubmit={submitClarify}
          />
        )}

        {step === "preview" && draft && previewCard && (
          <PreviewStep
            card={previewCard}
            draft={draft}
            displayName={displayName}
            setDisplayName={setDisplayName}
            accent={accent}
            setAccent={setAccent}
            icon={icon}
            setIcon={setIcon}
            slots={slots}
            setSlots={setSlots}
          />
        )}

        {error && (
          <div className="px-eu-lg">
            <div className="text-eu-sm text-eu-accent-red-fg bg-eu-accent-red-bg border border-eu-accent-red-edge rounded-eu-md px-eu-sm py-1.5 font-mono">
              {error}
            </div>
          </div>
        )}

        {/* Footer */}
        <footer className="mt-auto px-eu-lg pt-eu-md pb-eu-md border-t border-eu-rule flex items-center gap-eu-sm">
          {step === "describe" ? (
            <>
              <div className="ml-auto flex gap-eu-sm">
                <button
                  type="button"
                  onClick={onClose}
                  disabled={busy}
                  className="px-eu-md py-eu-sm text-eu-sm text-eu-text-mid hover:text-eu-text-hi disabled:opacity-40"
                >
                  取消
                </button>
                <button
                  type="button"
                  onClick={generate}
                  disabled={busy || !description.trim()}
                  className={[
                    "inline-flex items-center gap-1.5 px-eu-md py-eu-sm rounded-eu-md text-eu-sm font-medium",
                    "bg-eu-brand text-white hover:bg-eu-brand-hi",
                    "disabled:opacity-50 disabled:cursor-not-allowed",
                    "transition-colors duration-eu-fast",
                  ].join(" ")}
                >
                  {busy ? <Loader2 size={14} strokeWidth={2} className="animate-spin" /> : <Wand2 size={14} strokeWidth={2} />}
                  {busy ? "设计中…" : "AI 生成"}
                </button>
              </div>
            </>
          ) : (
            <>
              <button
                type="button"
                onClick={backToDescribe}
                disabled={busy}
                className="inline-flex items-center gap-1.5 px-eu-md py-eu-sm rounded-eu-md text-eu-sm text-eu-text-mid hover:text-eu-text-hi disabled:opacity-40"
              >
                <RotateCcw size={14} strokeWidth={1.75} />
                重新描述
              </button>
              <div className="ml-auto">
                <button
                  type="button"
                  onClick={confirm}
                  disabled={busy}
                  className={[
                    "inline-flex items-center gap-1.5 px-eu-md py-eu-sm rounded-eu-md text-eu-sm font-medium",
                    "bg-eu-brand text-white hover:bg-eu-brand-hi",
                    "disabled:opacity-50 disabled:cursor-not-allowed",
                    "transition-colors duration-eu-fast",
                  ].join(" ")}
                >
                  {busy ? <Loader2 size={14} strokeWidth={2} className="animate-spin" /> : <Check size={14} strokeWidth={2} />}
                  {busy ? "注册中…" : "添加这个技能"}
                </button>
              </div>
            </>
          )}
        </footer>
      </aside>
    </div>
  );
}

/* ── Step 1: describe ─────────────────────────────────────────────────────── */

function DescribeStep({
  description,
  setDescription,
  busy,
  onGenerate,
}: {
  description: string;
  setDescription: (v: string) => void;
  busy: boolean;
  onGenerate: () => void;
}) {
  if (busy) {
    return (
      <div className="px-eu-lg flex flex-col items-center gap-eu-md py-eu-2xl text-center">
        <div className="relative">
          <Sparkles size={28} strokeWidth={1.5} className="text-eu-accent-purple-fg" />
          <Loader2 size={48} strokeWidth={1.25} className="animate-spin text-eu-brand absolute -inset-2.5" />
        </div>
        <div className="text-eu-base text-eu-text-hi font-medium">AI 正在设计你的卡片…</div>
        <div className="text-eu-sm text-eu-text-lo font-mono">约 15-30 秒</div>
      </div>
    );
  }

  return (
    <div className="px-eu-lg flex flex-col gap-eu-md">
      <textarea
        autoFocus
        value={description}
        onChange={(e) => setDescription(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) onGenerate();
        }}
        rows={3}
        placeholder="用一句话描述你想记录的东西,例如「记录每次跑步的距离、配速和感受」…"
        className={[
          "w-full resize-none",
          "bg-eu-surface border border-eu-border rounded-eu-md",
          "p-eu-md text-eu-base text-eu-text-hi",
          "placeholder:text-eu-text-muted",
          "focus:outline-none focus:border-eu-brand",
          "transition-colors duration-eu-fast",
        ].join(" ")}
      />
      <div className="flex flex-wrap gap-1.5">
        {EXAMPLES.map((ex) => (
          <button
            key={ex}
            type="button"
            onClick={() => setDescription(ex)}
            className={[
              "px-eu-sm py-1 rounded-eu-full text-eu-xs",
              "bg-eu-surface border border-eu-border text-eu-text-mid",
              "hover:border-eu-brand-line hover:text-eu-text-hi active:scale-95",
              "transition-all duration-eu-fast",
            ].join(" ")}
          >
            {ex}
          </button>
        ))}
      </div>
      <div className="text-eu-xs text-eu-text-lo font-mono">
        AI 会自动设计字段、图标和卡片样式 · ⌘/Ctrl+Enter 生成
      </div>
    </div>
  );
}

/* ── Step 2: clarify (only when AI needs more info) ───────────────────────── */

/**
 * ClarifyStep — guided card flow. The backend's clarifier returns 1-3
 * questions when the user's description is too vague to draft a good
 * skill from. We render each as a card row: title + (choice chips OR
 * free-text input). User answers and we POST back to /api/skills with
 * the answers folded into the description.
 *
 * Why this step exists: a one-shot description like 「宝宝喂养记录」 leaves
 * the design agent guessing at the schema; the user ends up with fields
 * that don't match their real intent. Letting the agent narrow the scope
 * first produces skills users actually want.
 */
function ClarifyStep({
  description,
  questions,
  answers,
  setAnswers,
  busy,
  onBack,
  onSubmit,
}: {
  description: string;
  questions: ClarifyQuestion[];
  answers: Record<string, string>;
  setAnswers: (next: Record<string, string>) => void;
  busy: boolean;
  onBack: () => void;
  onSubmit: () => void;
}) {
  function setAnswer(key: string, value: string) {
    setAnswers({ ...answers, [key]: value });
  }

  // All questions must have a non-empty answer before submit. Choices are
  // pre-filled; only free-text questions can stay blank.
  const ready = questions.every((q) => (answers[q.key] ?? "").trim().length > 0);

  return (
    <div className="px-eu-lg flex flex-col gap-eu-md">
      {/* Recap the original description so the user sees what they're refining. */}
      <div
        className="rounded-eu-md px-eu-md py-eu-sm border border-eu-rule"
        style={{ background: "rgba(255,255,255,0.02)" }}
      >
        <div className="text-eu-xs uppercase tracking-eu-caps text-eu-text-lo font-mono mb-1">
          原始描述
        </div>
        <div className="text-eu-sm text-eu-text-hi">{description}</div>
      </div>

      {/* Each question is its own card row. */}
      <div className="flex flex-col gap-eu-md">
        {questions.map((q, i) => (
          <div key={q.key} className="flex flex-col gap-1.5">
            <div className="flex items-center gap-2">
              <span
                className="font-mono text-eu-xs"
                style={{ color: "rgba(196,168,255,0.75)" }}
              >
                {String(i + 1).padStart(2, "0")}
              </span>
              <span className="text-eu-sm text-eu-text-hi font-medium">{q.prompt}</span>
            </div>
            {q.type === "choice" && q.options ? (
              <div className="flex flex-wrap gap-1.5 pl-6">
                {q.options.map((opt) => {
                  const active = answers[q.key] === opt;
                  return (
                    <button
                      key={opt}
                      type="button"
                      onClick={() => setAnswer(q.key, opt)}
                      disabled={busy}
                      className={[
                        "px-eu-md py-eu-sm rounded-eu-full text-eu-sm transition-all",
                        "border active:scale-95",
                        active
                          ? "bg-eu-brand-faint text-eu-brand-hi border-eu-brand-line"
                          : "bg-eu-surface text-eu-text-mid border-eu-border hover:border-eu-border-strong",
                      ].join(" ")}
                    >
                      {opt}
                    </button>
                  );
                })}
              </div>
            ) : (
              <input
                type="text"
                value={answers[q.key] ?? ""}
                onChange={(e) => setAnswer(q.key, e.target.value)}
                placeholder={q.placeholder ?? ""}
                disabled={busy}
                className="ml-6 bg-eu-surface border border-eu-border rounded-eu-md px-eu-sm py-1.5 text-eu-base text-eu-text-hi focus:outline-none focus:border-eu-brand"
              />
            )}
          </div>
        ))}
      </div>

      <div className="flex gap-eu-sm pt-eu-sm">
        <button
          type="button"
          onClick={onBack}
          disabled={busy}
          className="px-eu-md py-eu-sm rounded-eu-md text-eu-text-mid hover:bg-eu-surface-hover text-eu-sm disabled:opacity-40"
        >
          ← 改描述
        </button>
        <div className="flex-1" />
        <button
          type="button"
          onClick={onSubmit}
          disabled={busy || !ready}
          className={[
            "inline-flex items-center gap-1.5 px-eu-md py-eu-sm rounded-eu-full",
            "bg-eu-brand-faint text-eu-brand-hi border border-eu-brand-line",
            "text-eu-sm font-medium hover:brightness-110 active:scale-95",
            "disabled:opacity-40 disabled:cursor-not-allowed",
          ].join(" ")}
        >
          {busy
            ? <Loader2 size={14} strokeWidth={1.75} className="animate-spin" />
            : <Wand2 size={14} strokeWidth={1.75} />}
          {busy ? "生成中…" : "生成卡片"}
        </button>
      </div>
    </div>
  );
}

/* ── Step 3: preview + tweak ──────────────────────────────────────────────── */

function PreviewStep({
  card, draft,
  displayName, setDisplayName,
  accent, setAccent,
  icon, setIcon,
  slots, setSlots,
}: {
  card: ReturnType<typeof buildCard>;
  draft: SkillDraft;
  displayName: string; setDisplayName: (v: string) => void;
  accent: AccentColor; setAccent: (v: AccentColor) => void;
  icon: string; setIcon: (v: string) => void;
  slots: SlotMap; setSlots: (v: SlotMap) => void;
}) {
  const fields = schemaFields(draft.payload_schema);
  const metaCount = Object.values(slots).filter((s) => s === "meta").length;

  function pick(field: string, kind: SlotKind) {
    setSlots(applySlotPick(slots, field, kind));
  }

  return (
    <div className="px-eu-lg flex flex-col gap-eu-md">
      {/* Live card preview — the big surface (library, chat, day-detail). */}
      <div>
        <div className="text-eu-xs uppercase tracking-eu-caps text-eu-text-lo font-mono mb-1.5">
          卡片预览
        </div>
        <div className="pointer-events-none">
          <SkillCard data={card} />
        </div>
      </div>

      {/* Calendar bullet preview — same decorated title as the big card; the
          rule is enforced in code (one source of truth, no per-surface drift). */}
      <div>
        <div className="text-eu-xs uppercase tracking-eu-caps text-eu-text-lo font-mono mb-1.5">
          日程行预览
        </div>
        <CalendarBulletPreview title={card.title} accent={card.accentColor} />
      </div>

      {/* ── 字段配置 ─────────────────────────────────────────────────────
          One row per payload field. Each row: name + type, slot picker,
          and (when not hidden) a small unit input. May audit user feedback:
          assignment and units live together per-field — no separate "主
          标题装饰" section, no label/前缀 (the card icon + display_name
          already provide context). */}
      {fields.length > 0 && (
        <div className="flex flex-col gap-1.5 border-t border-eu-rule pt-eu-md">
          <div className="flex items-baseline justify-between">
            <div className="text-eu-xs uppercase tracking-eu-caps text-eu-text-lo font-mono">
              字段配置
            </div>
            <div className="text-eu-xs text-eu-text-lo font-mono">
              主 1 · 副 1 · 信息≤3
            </div>
          </div>
          <div className="text-eu-xs text-eu-text-lo leading-relaxed">
            主标题同时出现在大卡片和日历行上。副标题和信息只出现在大卡片上。如果需要单位(克 / 毫升 / 公里),直接写在值里就好(如「150 毫升」)。
          </div>
          <div className="flex flex-col gap-1 mt-0.5">
            {fields.map((f) => (
              <FieldConfigRow
                key={f.name}
                field={f.name}
                type={f.type}
                slot={slots[f.name] ?? "hidden"}
                metaFull={metaCount >= 3 && slots[f.name] !== "meta"}
                onPickSlot={(k) => pick(f.name, k)}
              />
            ))}
          </div>
        </div>
      )}

      {/* Tweak: name + icon + accent */}
      <div className="flex flex-col gap-eu-md border-t border-eu-rule pt-eu-md">
        <div className="flex gap-eu-md">
          <div className="flex flex-col gap-1" style={{ width: 64 }}>
            <div className="text-eu-xs uppercase tracking-eu-caps text-eu-text-lo font-mono">图标</div>
            <input
              value={icon}
              onChange={(e) => setIcon(e.target.value.slice(0, 2))}
              maxLength={2}
              className="w-full text-center bg-eu-surface border border-eu-border rounded-eu-md px-eu-sm py-1.5 text-eu-lg focus:outline-none focus:border-eu-brand"
            />
          </div>
          <div className="flex-1 flex flex-col gap-1 min-w-0">
            <div className="text-eu-xs uppercase tracking-eu-caps text-eu-text-lo font-mono">名称</div>
            <input
              value={displayName}
              onChange={(e) => setDisplayName(e.target.value)}
              placeholder={draft.display_name}
              className="w-full bg-eu-surface border border-eu-border rounded-eu-md px-eu-sm py-1.5 text-eu-base text-eu-text-hi focus:outline-none focus:border-eu-brand"
            />
          </div>
        </div>

        <div className="flex flex-col gap-1.5">
          <div className="text-eu-xs uppercase tracking-eu-caps text-eu-text-lo font-mono">主题色</div>
          <div className="flex gap-2">
            {ACCENTS.map((a) => (
              <button
                key={a}
                type="button"
                aria-label={a}
                onClick={() => setAccent(a)}
                className="rounded-full active:scale-90 transition-transform"
                style={{
                  width: 26,
                  height: 26,
                  background: ACCENT_SWATCH[a],
                  boxShadow: accent === a ? `0 0 0 2px var(--eu-surface-raised), 0 0 0 4px ${ACCENT_SWATCH[a]}` : "none",
                  opacity: accent === a ? 1 : 0.55,
                }}
              />
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

/**
 * FieldConfigRow — one payload field per row: name + type chip + slot
 * picker (主/副/信息/隐藏). May audit Option B: units were dropped from
 * the spec entirely — users embed them in the value when needed. So this
 * row no longer has a per-field 单位 input.
 */
function FieldConfigRow({
  field, type, slot, metaFull, onPickSlot,
}: {
  field: string;
  type: string;
  slot: SlotKind;
  metaFull: boolean;
  onPickSlot: (s: SlotKind) => void;
}) {
  const slotOptions: Array<{ key: SlotKind; label: string; disabled?: boolean }> = [
    { key: "primary",   label: "主" },
    { key: "secondary", label: "副" },
    { key: "meta",      label: "信息", disabled: metaFull },
    { key: "hidden",    label: "隐藏" },
  ];
  return (
    <div className="flex items-center gap-eu-sm py-1">
      <div className="flex-1 min-w-0 flex items-baseline gap-1.5">
        <span className="text-eu-sm text-eu-text-hi truncate">{field}</span>
        {type && <span className="font-mono text-eu-xs text-eu-text-lo shrink-0">{type}</span>}
      </div>
      <div className="flex gap-0.5 shrink-0">
        {slotOptions.map((o) => {
          const active = slot === o.key;
          return (
            <button
              key={o.key}
              type="button"
              disabled={o.disabled && !active}
              onClick={() => onPickSlot(o.key)}
              className={[
                "px-2 py-0.5 rounded-eu-sm text-eu-xs border transition-all active:scale-95",
                active
                  ? "bg-eu-brand-faint text-eu-brand-hi border-eu-brand-line font-medium"
                  : "bg-transparent text-eu-text-lo border-eu-border hover:border-eu-border-strong",
                o.disabled && !active ? "opacity-30 cursor-not-allowed" : "",
              ].join(" ")}
            >
              {o.label}
            </button>
          );
        })}
      </div>
    </div>
  );
}

/**
 * CalendarBulletPreview — mimics the schedule timeline bullet row:
 *
 *   ┌─────────────────────────────────────────┐
 *   │  16:18   ●   距离 5 km                   │
 *   └─────────────────────────────────────────┘
 *
 * Time is fixed at a sample value (the actual asset.effective_at will
 * vary per record). Dot uses the skill's accent. Title is whatever the
 * SkillCard's title would be — keeps the rendering rule consistent.
 */
function CalendarBulletPreview({
  title, accent,
}: { title: string; accent: AccentColor }) {
  const dotColor = ACCENT_SWATCH[accent] ?? "rgba(255,255,255,0.55)";
  return (
    <div
      className="flex items-center gap-3"
      style={{
        padding: "10px 14px",
        background: "rgba(0,0,0,0.20)",
        border: "1px solid rgba(255,255,255,0.06)",
        borderRadius: 10,
      }}
    >
      <span
        className="font-mono"
        style={{ fontSize: 11, color: "rgba(255,255,255,0.55)", minWidth: 40 }}
      >
        16:18
      </span>
      <span
        style={{
          width: 6, height: 6, borderRadius: 999,
          background: dotColor,
          boxShadow: `0 0 6px ${dotColor}`,
        }}
      />
      <span style={{ fontSize: 13.5, color: "#f4f7fb", fontWeight: 500 }}>
        {title}
      </span>
    </div>
  );
}

/* ── helpers ──────────────────────────────────────────────────────────────── */

/**
 * Slot a payload field can occupy on the rendered card:
 *   primary   — 1, becomes the title (big card) AND the bullet on calendar
 *   secondary — 0..1, becomes the subtitle (big card only)
 *   meta      — 0..3, become the pills below subtitle (big card only)
 *   hidden    — not shown on cards; still in payload, visible in the
 *               AssetDetailDrawer / editor
 *
 * Unified rule (May audit): calendar bullet inherits primary, so the user
 * configures the big card and the bullet follows automatically — no per-
 * surface drift, no second config to keep in sync.
 */
export type SlotKind = "primary" | "secondary" | "meta" | "hidden";
export type SlotMap = Record<string, SlotKind>;

/**
 * Seed the slot map from a fresh AI draft. Whatever primary/secondary/meta
 * the AI picked becomes the starting point; remaining fields default to
 * "hidden". User can reassign from here.
 */
function initialSlots(draft: SkillDraft): SlotMap {
  const map: SlotMap = {};
  const rs = draft.render_spec ?? {} as RenderSpec;
  if (rs.primary_field)   map[rs.primary_field]   = "primary";
  if (rs.secondary_field) map[rs.secondary_field] = "secondary";
  for (const mf of rs.meta_fields ?? []) {
    if (mf.field && map[mf.field] !== "primary" && map[mf.field] !== "secondary") {
      map[mf.field] = "meta";
    }
  }
  for (const fname of Object.keys(draft.payload_schema ?? {})) {
    if (!(fname in map)) map[fname] = "hidden";
  }
  return map;
}

/**
 * Picking a slot enforces the cardinality rules:
 *   primary / secondary — at most one; previous holder gets demoted to hidden
 *   meta                — many allowed; cap (≤3) is enforced in the UI by
 *                         disabling the "信息" button when full
 *   hidden              — always allowed
 */
function applySlotPick(slots: SlotMap, field: string, kind: SlotKind): SlotMap {
  const next: SlotMap = { ...slots };
  if (kind === "primary" || kind === "secondary") {
    for (const [f, s] of Object.entries(next)) {
      if (s === kind && f !== field) next[f] = "hidden";
    }
  }
  next[field] = kind;
  return next;
}

interface ComposeOpts {
  accent: AccentColor;
  icon:   string;
  slots:  SlotMap;
}

/**
 * Compose a RenderSpec from the AI draft + the user's slot map. May
 * audit Option B: units / labels are gone from the schema, so the
 * compose call no longer threads field_units. Legacy decoration keys
 * (primary_label / primary_unit / secondary_label / secondary_unit /
 * field_units) are stripped so they don't shadow the clean rule
 * downstream.
 */
function composeRenderSpec(base: RenderSpec, opts: ComposeOpts): RenderSpec {
  const entries = Object.entries(opts.slots);
  const primary   = entries.find(([_, s]) => s === "primary")?.[0]   ?? base.primary_field;
  const secondary = entries.find(([_, s]) => s === "secondary")?.[0] ?? base.secondary_field;
  const metaFromSlots = entries.filter(([_, s]) => s === "meta").map(([f]) => f);
  const meta_fields = metaFromSlots.length > 0
    ? metaFromSlots.slice(0, 3).map((field) => {
        const baseMeta = (base.meta_fields ?? []).find((m) => m.field === field);
        return baseMeta ?? { field };
      })
    : base.meta_fields;

  return {
    ...base,
    accent_color:    opts.accent,
    icon:            opts.icon,
    primary_field:   primary,
    secondary_field: secondary,
    meta_fields,
    // Strip legacy decoration keys (Option B): values speak for
    // themselves; units belong in the value when needed.
    field_units:     undefined,
    primary_label:   undefined,
    primary_unit:    undefined,
    secondary_label: undefined,
    secondary_unit:  undefined,
  };
}

function schemaFields(schema: Record<string, unknown>): Array<{ name: string; type: string }> {
  if (!schema || typeof schema !== "object") return [];
  return Object.entries(schema).map(([name, v]) => {
    let type = "";
    if (typeof v === "string") type = v;
    else if (v && typeof v === "object" && "type" in (v as object)) {
      type = String((v as { type: unknown }).type ?? "");
    }
    return { name, type };
  });
}

function errMsg(e: unknown): string {
  if (e instanceof ApiError) {
    const body = e.body as { error?: string } | null;
    return body?.error ?? `请求失败 (${e.status})`;
  }
  return e instanceof Error ? e.message : String(e);
}
