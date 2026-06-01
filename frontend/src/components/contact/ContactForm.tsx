import { useState } from "react";
import { Loader2, Trash2, X } from "lucide-react";
import { useSWRConfig } from "swr";

import { useModalMount } from "@/context/ModalContext";
import { apiFetch } from "@/lib/api";
import type { Contact } from "@/lib/types";

/**
 * ContactForm — drawer-shape contact create / edit.
 *
 * Closes the last gap in the uniform edit lifecycle: events use EventForm,
 * assets use SkillCreateForm, and contacts (a first-class entity) had no
 * edit form — the drawer's 编辑 button was disabled for them. Same drawer
 * shell as EventForm: 👤 header + field rows + 删除 / 取消 / 保存. No inline
 * 「在 chat 里讨论」 — the global dock's Agent button is the entry (it picks
 * up the contact's AgentTarget registered by AssetDetailDrawer).
 *
 * Backend: POST /api/contacts (create) / PUT /api/contacts/:id (update,
 * partial) / DELETE /api/contacts/:id.
 */

interface ContactFormProps {
  existing?: Contact;
  onClose:   () => void;
  onSaved?:  (contactId: string) => void;
}

export function ContactForm(props: ContactFormProps) {
  useModalMount();
  return <ContactFormBody {...props} />;
}

function ContactFormBody({ existing, onClose, onSaved }: ContactFormProps) {
  const isEdit = !!existing;
  const { mutate } = useSWRConfig();

  const [name,    setName]    = useState(existing?.name    ?? "");
  const [phone,   setPhone]   = useState(existing?.phone   ?? "");
  const [company, setCompany] = useState(existing?.company ?? "");
  const [title,   setTitle]   = useState(existing?.title   ?? "");
  const [email,   setEmail]   = useState(existing?.email   ?? "");
  const [busy,    setBusy]    = useState(false);
  const [error,   setError]   = useState<string | null>(null);
  const [confirmDel,     setConfirmDel]     = useState(false);

  async function handleSave() {
    if (!name.trim()) { setError("请输入姓名"); return; }
    setBusy(true); setError(null);
    try {
      const body = {
        name:    name.trim(),
        phone:   phone.trim()   || null,
        company: company.trim() || null,
        title:   title.trim()   || null,
        email:   email.trim()   || null,
      };
      let id: string;
      if (isEdit && existing) {
        const resp = await apiFetch<{ ok: boolean; error?: string }>(
          `/api/contacts/${existing.id}`,
          { method: "PUT", body },
        );
        if (!resp.ok) throw new Error(resp.error ?? "保存失败");
        id = existing.id;
      } else {
        const resp = await apiFetch<{ ok: boolean; contact_id?: string; error?: string }>(
          "/api/contacts",
          { method: "POST", body },
        );
        if (!resp.ok || !resp.contact_id) throw new Error(resp.error ?? "创建失败");
        id = resp.contact_id;
      }
      await mutate((key) => typeof key === "string" && key.startsWith("/api/contacts"));
      onSaved?.(id);
      onClose();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
      setBusy(false);
    }
  }

  async function handleDelete() {
    if (!existing) return;
    setBusy(true);
    try {
      const resp = await apiFetch<{ ok: boolean; error?: string }>(
        `/api/contacts/${existing.id}`,
        { method: "DELETE" },
      );
      if (!resp.ok) throw new Error(resp.error ?? "删除失败");
      await mutate((key) => typeof key === "string" && key.startsWith("/api/contacts"));
      onClose();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
      setBusy(false);
    }
  }

  return (
    <div
      className="fixed inset-0 z-50 bg-eu-bg/92 backdrop-blur-md eu-fade-in"
      onClick={onClose}
    >
      <aside
        onClick={(e) => e.stopPropagation()}
        className={[
          "fixed inset-x-0 bottom-0 max-h-[88vh] rounded-t-eu-xl",
          "eu-sheet-up",
          "bg-eu-surface-raised border-t border-eu-border",
          "shadow-eu-lg pt-eu-md pb-safe overflow-y-auto eu-noscroll",
          "flex flex-col gap-eu-md",
        ].join(" ")}
      >
        <div className="md:hidden h-1 w-12 rounded-full bg-eu-rule mx-auto" />

        {/* Header: 👤 + CONTACT caps + name input + close */}
        <header className="flex items-start gap-eu-md px-eu-lg">
          <div className="shrink-0 h-10 w-10 rounded-eu-md border border-eu-accent-neutral-edge bg-eu-accent-neutral-bg text-eu-accent-neutral-fg flex items-center justify-center text-eu-lg">
            👤
          </div>
          <div className="flex-1 min-w-0">
            <div className="text-eu-xs uppercase tracking-eu-caps text-eu-text-lo font-mono">
              contact
            </div>
            <input
              autoFocus={!isEdit}
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="姓名…"
              className="w-full mt-0.5 bg-transparent border-none outline-none text-eu-lg text-eu-text-hi font-medium tracking-tight"
            />
          </div>
          <button
            type="button"
            aria-label="关闭"
            onClick={onClose}
            className="shrink-0 p-1.5 rounded-eu-sm text-eu-text-mid hover:text-eu-text-hi hover:bg-eu-surface-hover"
          >
            <X size={18} strokeWidth={1.75} />
          </button>
        </header>

        {/* No inline 「在 chat 里讨论」 — dock Agent is the global entry. */}

        {/* Field rows */}
        <div className="px-eu-lg flex flex-col gap-eu-md pt-eu-md">
          <Field label="电话"><Input value={phone}   onChange={setPhone}   placeholder="(可选)" type="tel" /></Field>
          <Field label="公司"><Input value={company} onChange={setCompany} placeholder="(可选)" /></Field>
          <Field label="职位"><Input value={title}   onChange={setTitle}   placeholder="(可选)" /></Field>
          <Field label="邮箱"><Input value={email}   onChange={setEmail}   placeholder="(可选)" type="email" /></Field>

          {error && (
            <div className="text-eu-sm text-eu-accent-red-fg bg-eu-accent-red-bg border border-eu-accent-red-edge rounded-eu-md px-eu-sm py-1.5 font-mono">
              {error}
            </div>
          )}
        </div>

        {/* Footer: 删除 / 取消 / 保存 */}
        <footer className="mt-auto px-eu-lg pt-eu-md pb-eu-md border-t border-eu-rule flex items-center gap-eu-sm">
          {isEdit && (
            <button
              type="button"
              onClick={() => (confirmDel ? handleDelete() : setConfirmDel(true))}
              disabled={busy}
              className={[
                "inline-flex items-center gap-1.5 px-eu-md py-eu-sm rounded-eu-md text-eu-sm",
                confirmDel
                  ? "bg-eu-accent-red-bg text-eu-accent-red-fg border border-eu-accent-red-edge"
                  : "text-eu-accent-red-fg hover:bg-eu-accent-red-bg",
              ].join(" ")}
            >
              <Trash2 size={14} strokeWidth={1.75} />
              {confirmDel ? "确认删除" : "删除"}
            </button>
          )}
          <div className="ml-auto flex gap-eu-sm">
            <button
              type="button"
              onClick={onClose}
              className="px-eu-md py-eu-sm text-eu-sm text-eu-text-mid hover:text-eu-text-hi"
            >
              取消
            </button>
            <button
              type="button"
              onClick={handleSave}
              disabled={busy || !name.trim()}
              className={[
                "inline-flex items-center gap-1.5 px-eu-md py-eu-sm rounded-eu-md text-eu-sm font-medium",
                "bg-eu-brand text-white hover:bg-eu-brand-hi",
                "disabled:opacity-50 disabled:cursor-not-allowed",
                "transition-colors duration-eu-fast",
              ].join(" ")}
            >
              {busy && <Loader2 size={14} strokeWidth={2} className="animate-spin" />}
              {isEdit ? "保存" : "创建"}
            </button>
          </div>
        </footer>
      </aside>
    </div>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-1">
      <div className="text-eu-xs uppercase tracking-eu-caps text-eu-text-lo font-mono">{label}</div>
      {children}
    </div>
  );
}

function Input({
  value, onChange, placeholder, type = "text",
}: { value: string; onChange: (v: string) => void; placeholder?: string; type?: string }) {
  return (
    <input
      type={type}
      value={value}
      onChange={(e) => onChange(e.target.value)}
      placeholder={placeholder}
      className="w-full bg-eu-surface border border-eu-border rounded-eu-md px-eu-sm py-1.5 text-eu-base text-eu-text-hi focus:outline-none focus:border-eu-brand"
    />
  );
}
