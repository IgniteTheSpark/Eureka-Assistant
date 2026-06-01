import { useState } from "react";
import { useSWRConfig } from "swr";
import { Loader2, Save, X } from "lucide-react";

import { apiFetch } from "@/lib/api";
import type { Asset, Skill } from "@/lib/types";
import { useModalMount } from "@/context/ModalContext";

/**
 * SkillCreateForm — schema-driven create form for a single UserSkill.
 *
 * Reads `skill.payload_schema` (the same JSON schema backend uses to validate
 * incoming asset payloads) and renders matching inputs:
 *
 *   type: "string"                → <input> or <textarea> (long content)
 *   type: "string" + enum         → <select>
 *   type: "datetime"              → <input type="datetime-local">
 *   type: "date"                  → <input type="date">
 *   type: "number"                → <input type="number">
 *   type: "array", items: "string" → comma-separated input (parsed on submit)
 *   type: "uuid"                  → skipped (not user-fillable — system fields)
 *
 * Required fields enforced client-side. Submit POSTs to /api/assets and
 * mutates the SWR cache so the parent list refreshes.
 *
 * Adding a new skill = adding payload_schema in seed.py + UserSkill row →
 * the same form auto-appears. Zero changes here.
 */

interface SkillCreateFormProps {
  skill: Skill;
  onClose: () => void;
  /** Called after a successful create/update with the asset's id. */
  onCreated?: (assetId: string) => void;
  /** RV4: when provided, the form opens in edit mode — prefills from the
   *  asset's payload and submits PUT /api/assets/:id instead of POST. */
  existing?: Asset;
}

interface FieldSpec {
  name: string;
  type: string;
  required: boolean;
  enumValues?: string[];
  defaultValue?: unknown;
  items?: string; // for arrays
}

const SKIP_TYPES = new Set(["uuid"]); // not user-input

const LONG_TEXT_FIELDS = new Set([
  "content", "description", "summary", "notes", "markdown", "body",
]);

export function SkillCreateForm({ skill, onClose, onCreated, existing }: SkillCreateFormProps) {
  useModalMount();
  const { mutate } = useSWRConfig();
  const isEdit = !!existing;
  const [values, setValues] = useState<Record<string, unknown>>(() =>
    isEdit ? prefillFromAsset(skill, existing!) : initialValues(skill),
  );
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fields = parseSchema(skill.payload_schema);

  function setField(name: string, value: unknown) {
    setValues((prev) => ({ ...prev, [name]: value }));
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);

    // Validate required
    for (const f of fields) {
      if (f.required && (values[f.name] == null || values[f.name] === "")) {
        setError(`「${f.name}」是必填的`);
        return;
      }
    }

    // Convert datetime-local string → ISO8601 with local TZ for datetime fields
    const payload: Record<string, unknown> = {};
    for (const f of fields) {
      const v = values[f.name];
      if (v == null || v === "") continue;
      if (f.type === "datetime" && typeof v === "string") {
        // datetime-local gives "YYYY-MM-DDTHH:MM" — append local offset
        payload[f.name] = toIsoWithOffset(v);
      } else if (f.type === "array" && typeof v === "string") {
        payload[f.name] = v.split(",").map((s) => s.trim()).filter(Boolean);
      } else if (f.type === "number" && typeof v === "string") {
        payload[f.name] = Number(v);
      } else {
        payload[f.name] = v;
      }
    }

    setSubmitting(true);
    try {
      // RV4: edit mode → PUT /api/assets/:id (always assets — contact edit
      // doesn't have a wrapper-asset to PATCH; that would be a follow-up).
      if (isEdit && existing) {
        // Backend's PUT /api/assets/:id takes payload_patch (merged into
        // existing payload), not payload — mismatch 422s.
        const resp = await apiFetch<{ ok: boolean; error?: string }>(
          `/api/assets/${existing.id}`,
          { method: "PUT", body: { payload_patch: payload } },
        );
        if (!resp.ok) throw new Error(resp.error ?? "保存失败");
        await mutate((key) => typeof key === "string" && key.startsWith("/api/assets"));
        onCreated?.(existing.id);
        onClose();
        return;
      }

      // Create path. Per Phase B v1.4: first-class entities live in their
      // own tables. The contact-skill asset shape is a TIMELINE REFERENCE
      // wrapping a contact_id from the contacts table. Manual create here
      // should go straight to contacts; agents (flash/chat) that create
      // via voice can still produce the reference asset via
      // tool_create_contact.
      const route = skill.name === "contact" ? "/api/contacts" : "/api/assets";
      const body  = skill.name === "contact"
        ? payload
        : { user_skill_name: skill.name, payload };

      const resp = await apiFetch<{
        ok: boolean; asset_id?: string; contact_id?: string; error?: string;
      }>(route, { method: "POST", body });

      if (!resp.ok) throw new Error(resp.error ?? "创建失败");

      // Invalidate every relevant cache so lists refresh
      await mutate((key) => typeof key === "string" && (
        key.startsWith("/api/assets") ||
        key.startsWith("/api/contacts")
      ));
      onCreated?.(resp.asset_id ?? resp.contact_id ?? "");
      onClose();
    } catch (e: unknown) {
      setError((e as Error).message ?? (isEdit ? "保存失败" : "创建失败"));
      setSubmitting(false);
    }
  }

  return (
    <div
      className="fixed inset-0 z-50 bg-eu-bg/92 backdrop-blur-md flex items-end md:items-center justify-center eu-fade-in"
      onClick={onClose}
    >
      <form
        onSubmit={submit}
        onClick={(e) => e.stopPropagation()}
        className={[
          "w-full",
          "bg-eu-surface-raised border-t border-eu-border md:border md:rounded-eu-xl",
          "rounded-t-eu-xl shadow-eu-lg pt-eu-md pb-safe",
          "eu-sheet-up",
          "flex flex-col gap-eu-md max-h-[88vh] overflow-y-auto eu-noscroll",
        ].join(" ")}
      >
        <div className="md:hidden h-1 w-12 rounded-full bg-eu-rule mx-auto" />
        <header className="flex items-center justify-between px-eu-lg">
          <div className="flex items-center gap-eu-sm">
            <span className="text-eu-xl font-mono">{skill.render_spec?.icon ?? "•"}</span>
            <h2 className="font-display text-eu-lg text-eu-text-hi tracking-tight">
              {isEdit ? "编辑" : "新建"} {skill.display_name}
            </h2>
          </div>
          <button
            type="button"
            aria-label="关闭"
            onClick={onClose}
            className="p-1.5 rounded-eu-sm text-eu-text-mid hover:text-eu-text-hi hover:bg-eu-surface-hover"
          >
            <X size={18} strokeWidth={1.75} />
          </button>
        </header>

        <div className="px-eu-lg flex flex-col gap-eu-md">
          {fields.length === 0 && (
            <p className="text-eu-sm text-eu-text-mid">
              这个 skill 没有可编辑字段(系统能力,非资产)。
            </p>
          )}
          {fields.map((f) => (
            <FieldInput
              key={f.name}
              field={f}
              value={values[f.name]}
              onChange={(v) => setField(f.name, v)}
            />
          ))}

          {error && (
            <div className="text-eu-sm text-eu-accent-red-fg bg-eu-accent-red-bg border border-eu-accent-red-edge rounded-eu-md px-eu-md py-eu-sm">
              {error}
            </div>
          )}
        </div>

        <footer className="px-eu-lg flex justify-end gap-eu-sm border-t border-eu-rule pt-eu-md">
          <button
            type="button"
            onClick={onClose}
            disabled={submitting}
            className="px-eu-md py-eu-sm text-eu-sm text-eu-text-mid hover:text-eu-text-hi disabled:opacity-50"
          >
            取消
          </button>
          <button
            type="submit"
            disabled={submitting || fields.length === 0}
            className={[
              "px-eu-md py-eu-sm rounded-eu-md text-eu-sm font-medium",
              "bg-eu-brand text-white hover:bg-eu-brand-hi",
              "disabled:opacity-50 disabled:cursor-not-allowed",
              "transition-colors duration-eu-fast flex items-center gap-1.5",
            ].join(" ")}
          >
            {submitting
              ? <Loader2 size={14} strokeWidth={2} className="animate-spin" />
              : <Save size={14} strokeWidth={2} />}
            {submitting ? "保存中…" : "保存"}
          </button>
        </footer>
      </form>
    </div>
  );
}

/* ── Field input renderer ────────────────────────────────────────────────── */

function FieldInput({
  field, value, onChange,
}: { field: FieldSpec; value: unknown; onChange: (v: unknown) => void }) {
  const baseLabel = (
    <label className="text-eu-xs uppercase tracking-eu-caps text-eu-text-lo font-mono">
      {field.name}{field.required && <span className="ml-1 text-eu-accent-red-fg">*</span>}
    </label>
  );

  const inputClass = [
    "w-full bg-eu-surface border border-eu-border rounded-eu-md",
    "px-eu-md py-eu-sm text-eu-base text-eu-text",
    "placeholder:text-eu-text-muted",
    "focus:outline-none focus:border-eu-brand",
    "transition-colors duration-eu-fast",
  ].join(" ");

  // Enum → select
  if (field.enumValues) {
    return (
      <div className="flex flex-col gap-1">
        {baseLabel}
        <select
          value={String(value ?? "")}
          onChange={(e) => onChange(e.target.value)}
          className={inputClass}
        >
          {!field.required && <option value="">(留空)</option>}
          {field.enumValues.map((v) => (
            <option key={v} value={v}>{v}</option>
          ))}
        </select>
      </div>
    );
  }

  // Long-form text fields → textarea
  if (field.type === "string" && LONG_TEXT_FIELDS.has(field.name)) {
    return (
      <div className="flex flex-col gap-1">
        {baseLabel}
        <textarea
          value={String(value ?? "")}
          onChange={(e) => onChange(e.target.value)}
          rows={4}
          placeholder={`输入${field.name}…`}
          className={`${inputClass} resize-none`}
        />
      </div>
    );
  }

  // Datetime
  if (field.type === "datetime") {
    return (
      <div className="flex flex-col gap-1">
        {baseLabel}
        <input
          type="datetime-local"
          value={String(value ?? "")}
          onChange={(e) => onChange(e.target.value)}
          className={inputClass}
        />
      </div>
    );
  }

  // Date
  if (field.type === "date") {
    return (
      <div className="flex flex-col gap-1">
        {baseLabel}
        <input
          type="date"
          value={String(value ?? "")}
          onChange={(e) => onChange(e.target.value)}
          className={inputClass}
        />
      </div>
    );
  }

  // Number
  if (field.type === "number") {
    return (
      <div className="flex flex-col gap-1">
        {baseLabel}
        <input
          type="number"
          step="any"
          value={value == null ? "" : String(value)}
          onChange={(e) => onChange(e.target.value)}
          placeholder="0"
          className={inputClass}
        />
      </div>
    );
  }

  // Array of strings → comma-separated
  if (field.type === "array") {
    return (
      <div className="flex flex-col gap-1">
        {baseLabel}
        <input
          type="text"
          value={
            Array.isArray(value) ? value.join(", ") : String(value ?? "")
          }
          onChange={(e) => onChange(e.target.value)}
          placeholder="逗号分隔,例:标签1, 标签2"
          className={inputClass}
        />
      </div>
    );
  }

  // Default → text input
  return (
    <div className="flex flex-col gap-1">
      {baseLabel}
      <input
        type="text"
        value={String(value ?? "")}
        onChange={(e) => onChange(e.target.value)}
        placeholder={`输入${field.name}…`}
        className={inputClass}
      />
    </div>
  );
}

/* ── Schema parsing ──────────────────────────────────────────────────────── */

function parseSchema(schema: Record<string, unknown> | null): FieldSpec[] {
  if (!schema) return [];
  const out: FieldSpec[] = [];
  for (const [name, defRaw] of Object.entries(schema)) {
    if (typeof defRaw !== "object" || defRaw == null) continue;
    const def = defRaw as Record<string, unknown>;
    const type = String(def.type ?? "string");
    if (SKIP_TYPES.has(type)) continue;
    out.push({
      name,
      type,
      required: Boolean(def.required),
      enumValues: Array.isArray(def.enum) ? (def.enum as string[]) : undefined,
      defaultValue: def.default,
      items: typeof def.items === "string" ? def.items : undefined,
    });
  }
  // Stable order: required first, then alphabetical
  out.sort((a, b) => {
    if (a.required !== b.required) return a.required ? -1 : 1;
    return a.name.localeCompare(b.name);
  });
  return out;
}

function initialValues(skill: Skill): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  if (!skill.payload_schema) return out;
  for (const [name, defRaw] of Object.entries(skill.payload_schema)) {
    if (typeof defRaw !== "object" || defRaw == null) continue;
    const def = defRaw as Record<string, unknown>;
    if (def.default !== undefined) out[name] = def.default;
  }
  return out;
}

/**
 * RV4: prefill form values from an existing Asset's payload. Datetime
 * fields need conversion ISO8601 → "YYYY-MM-DDTHH:MM" since that's what
 * the <input type="datetime-local"> control expects (local time, no TZ).
 */
function prefillFromAsset(skill: Skill, asset: Asset): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  if (!skill.payload_schema) return { ...asset.payload };
  for (const [name, defRaw] of Object.entries(skill.payload_schema)) {
    if (typeof defRaw !== "object" || defRaw == null) continue;
    const def = defRaw as Record<string, unknown>;
    const type = String(def.type ?? "string");
    const v = (asset.payload as Record<string, unknown>)[name];
    if (v == null) continue;
    if (type === "datetime" && typeof v === "string") {
      out[name] = isoToDatetimeLocal(v);
    } else if (type === "date" && typeof v === "string") {
      // ISO date or full ISO datetime — keep only YYYY-MM-DD
      out[name] = v.slice(0, 10);
    } else {
      out[name] = v;
    }
  }
  return out;
}

/** ISO8601 ("…T10:00:00+08:00") → "YYYY-MM-DDTHH:MM" in local TZ. */
function isoToDatetimeLocal(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

/** Convert datetime-local "YYYY-MM-DDTHH:MM" to ISO8601 with local TZ offset. */
function toIsoWithOffset(local: string): string {
  // new Date(local) treats the string as local time
  const d = new Date(local);
  if (Number.isNaN(d.getTime())) return local;
  // Build "YYYY-MM-DDTHH:MM:SS+HH:MM"
  const off = -d.getTimezoneOffset();
  const sign = off >= 0 ? "+" : "-";
  const oh = String(Math.floor(Math.abs(off) / 60)).padStart(2, "0");
  const om = String(Math.abs(off) % 60).padStart(2, "0");
  const pad = (n: number) => String(n).padStart(2, "0");
  const y = d.getFullYear();
  const mo = pad(d.getMonth() + 1);
  const da = pad(d.getDate());
  const hh = pad(d.getHours());
  const mm = pad(d.getMinutes());
  return `${y}-${mo}-${da}T${hh}:${mm}:00${sign}${oh}:${om}`;
}
