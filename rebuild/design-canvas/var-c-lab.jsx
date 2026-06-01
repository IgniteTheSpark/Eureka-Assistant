// var-c-lab.jsx — Variation C · Lab
// Editorial dark. Manrope display + IBM Plex Mono numerals + Noto Sans SC.
// Generous whitespace, strong structural rules, caps-tracking labels.
// Less rounded (2/4/8/12), accent tint kept very subtle with crisp markers.

const C = {
  name: 'C · Lab',
  subtitle: 'Editorial-grade dark interface',
  bg: '#0a0c10',
  surface: '#11141a',
  surface2: '#161a22',
  surface3: '#1d2230',
  border: '#23283340',
  borderSolid: '#22272f',
  borderStrong: '#3a4150',
  rule: '#1e2330',
  textHi: '#eef1f6',
  text:   '#c8cfd9',
  textMid:'#8a93a1',
  textLo: '#5a626e',
  textMuted: '#3b4250',
  brand: '#7396d4',
  brandHi: '#a0b8e0',
  brandFaint: 'rgba(115,150,212,0.08)',
  brandLine: 'rgba(115,150,212,0.28)',
  accent: {
    blue:    { fg: '#88aae0', bg: 'rgba(136,170,224,0.06)', edge: 'rgba(136,170,224,0.22)', marker: '#88aae0' },
    amber:   { fg: '#d4b366', bg: 'rgba(212,179,102,0.06)', edge: 'rgba(212,179,102,0.22)', marker: '#d4b366' },
    green:   { fg: '#8cc09a', bg: 'rgba(140,192,154,0.06)', edge: 'rgba(140,192,154,0.22)', marker: '#8cc09a' },
    red:     { fg: '#e08a98', bg: 'rgba(224,138,152,0.06)', edge: 'rgba(224,138,152,0.22)', marker: '#e08a98' },
    purple:  { fg: '#b09cd8', bg: 'rgba(176,156,216,0.06)', edge: 'rgba(176,156,216,0.22)', marker: '#b09cd8' },
    gray:    { fg: '#8a93a1', bg: 'rgba(138,147,161,0.06)', edge: 'rgba(138,147,161,0.20)', marker: '#8a93a1' },
    neutral: { fg: '#c8cfd9', bg: 'rgba(200,207,217,0.04)', edge: 'rgba(200,207,217,0.16)', marker: '#c8cfd9' },
  },
  font: '"Manrope","Noto Sans SC", system-ui, sans-serif',
  fontBody: '"IBM Plex Sans","Noto Sans SC", system-ui, sans-serif',
  mono: '"IBM Plex Mono", ui-monospace, monospace',
  radius: { sm: 2, md: 4, lg: 8, xl: 12 },
};

// ──────────────────────────────────────────────────────────────────────
// SkillCard for Lab
// ──────────────────────────────────────────────────────────────────────

function LabCard({ asset, hover, selected, layout, idx }) {
  const ac = C.accent[asset.accent];
  const lay = layout || asset.layout;

  if (lay === 'inline') {
    return (
      <div style={{
        display: 'grid', gridTemplateColumns: '32px 1fr auto', alignItems: 'center', gap: 12,
        padding: '10px 0', borderBottom: `1px solid ${C.rule}`,
        fontSize: 13, color: C.text, fontFamily: C.fontBody,
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <span style={{ width: 2, height: 14, background: ac.marker, flex: '0 0 2px' }}></span>
          <span style={{ color: ac.fg, fontFamily: C.mono, fontSize: 11, fontWeight: 600, letterSpacing: '0.06em', textTransform: 'uppercase' }}>{asset.skill.slice(0, 3)}</span>
        </div>
        <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
          {asset.payload.content || asset.payload.title || asset.payload.name || asset.payload.description}
        </span>
        <span style={{ color: C.textLo, fontFamily: C.mono, fontSize: 11 }}>{asset.time}</span>
      </div>
    );
  }

  if (lay === 'compact') {
    return (
      <div style={{
        display: 'flex', alignItems: 'center', gap: 6,
        padding: '3px 6px',
        background: ac.bg,
        borderLeft: `2px solid ${ac.marker}`,
        fontSize: 10.5, color: ac.fg, fontWeight: 500,
        overflow: 'hidden', whiteSpace: 'nowrap', textOverflow: 'ellipsis',
        fontFamily: C.fontBody,
      }}>
        {asset.payload.start_at && <span style={{ fontFamily: C.mono, fontSize: 9.5, opacity: 0.85 }}>{asset.payload.start_at.split(' ')[1] || ''}</span>}
        <span style={{ overflow: 'hidden', textOverflow: 'ellipsis' }}>{asset.payload.title || asset.payload.content}</span>
      </div>
    );
  }

  if (lay === 'stacked') {
    const p = asset.payload;
    return (
      <div style={{
        position: 'relative',
        display: 'flex', flexDirection: 'column', gap: 8,
        padding: '16px 18px', borderRadius: C.radius.md,
        background: ac.bg, border: `1px solid ${ac.edge}`,
        fontFamily: C.fontBody,
      }}>
        <div style={{ position: 'absolute', left: 0, top: 14, bottom: 14, width: 2, background: ac.marker }}></div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <span style={{ color: ac.fg, fontFamily: C.mono, fontSize: 10.5, fontWeight: 700, letterSpacing: '0.14em', textTransform: 'uppercase' }}>{asset.skill}</span>
          <span style={{ flex: 1, height: 1, background: C.rule }}></span>
          <span style={{ fontSize: 10.5, color: C.textLo, fontFamily: C.mono }}>{asset.time}</span>
        </div>
        <div style={{ fontSize: 15, fontWeight: 600, color: C.textHi, letterSpacing: '-0.01em', fontFamily: C.font }}>{p.title}</div>
        <div style={{ fontSize: 13, color: C.text, lineHeight: 1.6 }}>{p.content}</div>
      </div>
    );
  }

  // horizontal
  const p = asset.payload;
  const primary = p.content || p.title || p.name || '';
  const secondary = p.due_date || p.start_at || p.description || p.company || '';
  const meta = [];
  if (p.duration) meta.push(p.duration);
  if (p.location) meta.push(p.location);
  if (p.category) meta.push(p.category);
  if (p.title && p.name) meta.push(p.title);
  if (p.phone) meta.push(p.phone);

  // expense uses amount as the visual hero
  const isExpense = asset.skill === 'expense';

  return (
    <div style={{
      position: 'relative',
      display: 'grid', gridTemplateColumns: idx !== undefined ? '28px 1fr auto' : '1fr auto',
      alignItems: 'center', gap: 16,
      padding: '14px 18px 14px 16px',
      background: ac.bg, border: `1px solid ${selected ? ac.marker : ac.edge}`,
      borderRadius: C.radius.md,
      fontFamily: C.fontBody,
    }}>
      <div style={{ position: 'absolute', left: 0, top: 14, bottom: 14, width: 2, background: ac.marker }}></div>
      {idx !== undefined && (
        <div style={{ fontFamily: C.mono, fontSize: 11, color: C.textLo, letterSpacing: '0.02em', paddingLeft: 4 }}>{String(idx).padStart(2, '0')}</div>
      )}
      <div style={{ minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 4 }}>
          <span style={{ fontFamily: C.mono, fontSize: 10, color: ac.fg, fontWeight: 700, letterSpacing: '0.16em', textTransform: 'uppercase' }}>{asset.skill}</span>
          {asset.payload.status === 'overdue' && <span style={{ fontFamily: C.mono, fontSize: 10, color: C.accent.red.fg, letterSpacing: '0.08em' }}>· OVERDUE</span>}
        </div>
        {isExpense ? (
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
            <span style={{ fontFamily: C.mono, fontSize: 18, fontWeight: 600, color: C.textHi, letterSpacing: '-0.01em' }}>{p.amount}</span>
            <span style={{ fontSize: 13, color: C.text }}>{p.description}</span>
          </div>
        ) : (
          <div style={{
            fontSize: 14, fontWeight: 500,
            color: p.status === 'overdue' ? C.accent.red.fg : C.textHi,
            letterSpacing: '-0.005em', lineHeight: 1.4,
            fontFamily: C.font,
          }}>{primary}</div>
        )}
        {(secondary || meta.length > 0) && (
          <div style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: 10, marginTop: 4 }}>
            {secondary && !isExpense && <span style={{ fontSize: 12, color: C.textMid, fontFamily: (asset.skill === 'event' || asset.skill === 'todo') ? C.mono : C.fontBody }}>{secondary}</span>}
            {meta.map((m, i) => (
              <span key={i} style={{ fontSize: 11, color: C.textLo, fontFamily: C.mono }}>· {m}</span>
            ))}
          </div>
        )}
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 4, opacity: 0.7 }}>
        <span style={{ fontSize: 10.5, color: C.textLo, fontFamily: C.mono }}>{asset.time}</span>
        {asset.skill === 'todo' && <button style={iconBtnC}>✓</button>}
      </div>
    </div>
  );
}

const iconBtnC = {
  width: 24, height: 24, padding: 0, border: `1px solid ${C.borderStrong}`, background: 'transparent',
  color: C.textMid, fontSize: 11, cursor: 'pointer', borderRadius: 2,
  display: 'flex', alignItems: 'center', justifyContent: 'center',
  fontFamily: C.mono, marginLeft: 6,
};

// ──────────────────────────────────────────────────────────────────────
// 00 · Foundations
// ──────────────────────────────────────────────────────────────────────

function LabFoundations() {
  return (
    <div style={{
      width: '100%', height: '100%', background: C.bg, color: C.text,
      fontFamily: C.fontBody, padding: 44, boxSizing: 'border-box',
      display: 'flex', flexDirection: 'column', gap: 36,
      overflow: 'hidden',
      backgroundImage: `radial-gradient(circle at 1px 1px, rgba(255,255,255,0.018) 1px, transparent 0)`,
      backgroundSize: '4px 4px',
    }}>
      {/* Header — editorial masthead */}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr auto', alignItems: 'end', gap: 32, borderBottom: `1px solid ${C.borderStrong}`, paddingBottom: 28 }}>
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 14, marginBottom: 18 }}>
            <span style={{ width: 28, height: 1, background: C.brand }}></span>
            <span style={{ fontFamily: C.mono, fontSize: 10.5, letterSpacing: '0.32em', color: C.brand, textTransform: 'uppercase' }}>EUREKA / VOL.C</span>
          </div>
          <div style={{ fontSize: 64, fontWeight: 600, letterSpacing: '-0.04em', color: C.textHi, lineHeight: 0.95, fontFamily: C.font }}>Lab</div>
          <div style={{ fontSize: 14, color: C.textMid, marginTop: 14, maxWidth: 560, lineHeight: 1.6 }}>编辑感 + 实验室。把 AI 工作流当作严肃的研究记录来呈现。强栏线、克制色彩、数字优先。</div>
        </div>
        <div style={{ borderLeft: `1px solid ${C.borderStrong}`, paddingLeft: 24, display: 'flex', flexDirection: 'column', gap: 10, fontFamily: C.mono, fontSize: 10.5, color: C.textLo }}>
          <ColRow k="TYPE"    v="MANROPE / PLEX MONO" />
          <ColRow k="RADIUS"  v="2 / 4 / 8 / 12" />
          <ColRow k="DENSITY" v="MEDIUM · STRUCTURED" />
          <ColRow k="ACCENT"  v="MARKER + 6% TINT" />
        </div>
      </div>

      {/* Body */}
      <div style={{ display: 'grid', gridTemplateColumns: '1.1fr 1.1fr 1fr', gap: 40, flex: 1, minHeight: 0 }}>
        {/* Neutrals */}
        <EuArtboardSection label="Neutrals" num="01" fontMono={C.mono}>
          <div style={{ display: 'flex', borderRadius: 2, overflow: 'hidden', border: `1px solid ${C.borderSolid}` }}>
            {[
              { c: C.bg,        l: 'bg', m: '#0A0C10' },
              { c: C.surface,   l: 'surface', m: '#11141A' },
              { c: C.surface2,  l: 'raised', m: '#161A22' },
              { c: C.surface3,  l: 'hover', m: '#1D2230' },
            ].map((s, i) => (
              <div key={i} style={{ flex: 1, height: 72, background: s.c, padding: 10, display: 'flex', flexDirection: 'column', justifyContent: 'space-between', borderRight: i < 3 ? `1px solid ${C.borderSolid}` : 'none' }}>
                <div style={{ fontFamily: C.mono, fontSize: 9.5, color: C.textLo, letterSpacing: '0.1em', textTransform: 'uppercase' }}>{s.l}</div>
                <div style={{ fontFamily: C.mono, fontSize: 9.5, color: C.textMid }}>{s.m}</div>
              </div>
            ))}
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 0, marginTop: 8, borderTop: `1px solid ${C.borderSolid}` }}>
            {[
              { l: 'text.hi',  h: '#EEF1F6', c: C.textHi,    s: '标题 — Aa Bb 阿' },
              { l: 'text',     h: '#C8CFD9', c: C.text,      s: '正文 — 关于硬件断流的策略' },
              { l: 'text.mid', h: '#8A93A1', c: C.textMid,   s: '副本 — 5月26日 · 10:00' },
              { l: 'text.lo',  h: '#5A626E', c: C.textLo,    s: '辅助 — created 14:32' },
              { l: 'text.mut', h: '#3B4250', c: C.textMuted, s: '占位 — placeholder' },
            ].map((r, i) => (
              <div key={i} style={{ display: 'grid', gridTemplateColumns: '70px 1fr 60px', gap: 10, padding: '8px 0', borderBottom: i < 4 ? `1px solid ${C.rule}` : 'none', alignItems: 'baseline' }}>
                <div style={{ fontSize: 10, color: C.textLo, fontFamily: C.mono, letterSpacing: '0.04em' }}>{r.l}</div>
                <div style={{ fontSize: 14, color: r.c, lineHeight: 1.4 }}>{r.s}</div>
                <div style={{ fontSize: 9.5, color: C.textLo, fontFamily: C.mono, textAlign: 'right' }}>{r.h}</div>
              </div>
            ))}
          </div>
        </EuArtboardSection>

        {/* Brand + Accents */}
        <EuArtboardSection label="Brand + Accents" num="02" fontMono={C.mono}>
          <div style={{ borderLeft: `2px solid ${C.brand}`, padding: '6px 0 6px 18px' }}>
            <div style={{ fontFamily: C.mono, fontSize: 10.5, letterSpacing: '0.18em', color: C.brand }}>BRAND</div>
            <div style={{ fontSize: 22, fontWeight: 600, color: C.textHi, marginTop: 6, fontFamily: C.font, letterSpacing: '-0.01em' }}>Slate Blue — #7396D4</div>
            <div style={{ fontSize: 11.5, color: C.textMid, marginTop: 4, lineHeight: 1.55, maxWidth: 280 }}>克制的冷蓝。只用在品牌字、首要操作和强调线上。永远不做大面积填充。</div>
          </div>

          <div style={{ marginTop: 4, display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 0, border: `1px solid ${C.borderSolid}` }}>
            {ACCENT_ROLES.map((r, i) => {
              const ac = C.accent[r.key];
              return (
                <div key={r.key} style={{
                  display: 'flex', alignItems: 'center', gap: 10,
                  padding: '10px 12px',
                  borderRight: (i % 2 === 0) ? `1px solid ${C.borderSolid}` : 'none',
                  borderBottom: i < 5 ? `1px solid ${C.borderSolid}` : 'none',
                  background: ac.bg,
                  position: 'relative',
                }}>
                  <div style={{ position: 'absolute', left: 0, top: 8, bottom: 8, width: 2, background: ac.marker }}></div>
                  <div style={{ paddingLeft: 4, flex: 1 }}>
                    <div style={{ fontSize: 11, color: ac.fg, fontWeight: 700, fontFamily: C.mono, letterSpacing: '0.14em', textTransform: 'uppercase' }}>{r.key}</div>
                    <div style={{ fontSize: 10, color: C.textMid, marginTop: 1 }}>{r.role}</div>
                  </div>
                </div>
              );
            })}
          </div>
        </EuArtboardSection>

        {/* Type + Geometry */}
        <EuArtboardSection label="Type · Space · Motion" num="03" fontMono={C.mono}>
          <div style={{ padding: '14px 16px', borderTop: `1px solid ${C.borderStrong}`, borderBottom: `1px solid ${C.borderStrong}` }}>
            <div style={{ fontSize: 38, fontWeight: 700, color: C.textHi, fontFamily: C.font, letterSpacing: '-0.035em', lineHeight: 1 }}>
              Aa<span style={{ color: C.textLo }}> 阿</span>
            </div>
            <div style={{ fontSize: 10.5, color: C.textLo, fontFamily: C.mono, marginTop: 8, letterSpacing: '0.1em' }}>MANROPE · DISPLAY</div>
          </div>
          <div style={{ padding: '14px 16px', borderBottom: `1px solid ${C.borderStrong}` }}>
            <div style={{ fontSize: 24, fontWeight: 500, color: C.textHi, fontFamily: C.mono, lineHeight: 1, letterSpacing: '0.01em' }}>¥68.00 · 24:00</div>
            <div style={{ fontSize: 10.5, color: C.textLo, fontFamily: C.mono, marginTop: 8, letterSpacing: '0.1em' }}>IBM PLEX MONO · NUMERALS</div>
          </div>

          <div style={{ marginTop: 6, display: 'flex', alignItems: 'flex-end', gap: 6 }}>
            {[4, 8, 12, 16, 24, 32, 48].map(n => (
              <div key={n} style={{ flexBasis: 0, flexGrow: n }}>
                <div style={{ height: 10, background: C.brand, opacity: 0.5 }}></div>
                <div style={{ fontSize: 9, color: C.textLo, fontFamily: C.mono, marginTop: 6, textAlign: 'center', letterSpacing: '0.05em' }}>{n}</div>
              </div>
            ))}
          </div>

          <div style={{ marginTop: 6, padding: '14px 0', borderTop: `1px solid ${C.borderStrong}` }}>
            <div style={{ fontSize: 10.5, color: C.textLo, fontFamily: C.mono, letterSpacing: '0.16em', marginBottom: 10 }}>MOTION TOKENS</div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 6, fontFamily: C.mono, fontSize: 11, color: C.textMid }}>
              <div style={{ display: 'flex', justifyContent: 'space-between' }}><span>duration.fast</span><span style={{ color: C.text }}>120ms</span></div>
              <div style={{ display: 'flex', justifyContent: 'space-between' }}><span>duration.normal</span><span style={{ color: C.text }}>240ms</span></div>
              <div style={{ display: 'flex', justifyContent: 'space-between' }}><span>duration.slow</span><span style={{ color: C.text }}>400ms</span></div>
              <div style={{ display: 'flex', justifyContent: 'space-between' }}><span>stagger.card</span><span style={{ color: C.text }}>50ms</span></div>
            </div>
          </div>
        </EuArtboardSection>
      </div>
    </div>
  );
}

function ColRow({ k, v }) {
  return (
    <div style={{ display: 'flex', alignItems: 'baseline', gap: 14 }}>
      <span style={{ width: 64, letterSpacing: '0.16em' }}>{k}</span>
      <span style={{ color: C.text }}>{v}</span>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// 01 · AI Chat
// ──────────────────────────────────────────────────────────────────────

function LabChat() {
  return (
    <div style={{
      width: '100%', height: '100%', background: C.bg, color: C.text,
      fontFamily: C.fontBody, display: 'grid', gridTemplateColumns: '230px 1fr',
      overflow: 'hidden',
    }}>
      <LabSidebar active="chat" />
      <div style={{ display: 'grid', gridTemplateRows: '60px 1fr 92px', minHeight: 0, borderLeft: `1px solid ${C.borderSolid}` }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 28px', borderBottom: `1px solid ${C.borderSolid}` }}>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 14 }}>
            <span style={{ fontSize: 11, fontFamily: C.mono, letterSpacing: '0.22em', color: C.brand }}>SESSION</span>
            <span style={{ fontSize: 15, color: C.textHi, fontWeight: 600, fontFamily: C.font }}>统一助手</span>
            <span style={{ fontSize: 11, color: C.textLo, fontFamily: C.mono }}>/ 7f3a · 5月24日</span>
          </div>
          <div style={{ display: 'flex', gap: 6 }}>
            <button style={iconBtnC}>⌕</button>
            <button style={iconBtnC}>⋯</button>
          </div>
        </div>

        <div className="eu-noscroll" style={{ padding: '28px 36px', overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 22 }}>
          {DEMO_CHAT.map((m, i) => <LabMessage key={i} msg={m} idx={i + 1} />)}
        </div>

        <div style={{ borderTop: `1px solid ${C.borderSolid}`, padding: '18px 36px' }}>
          <div style={{
            display: 'flex', alignItems: 'center', gap: 12,
            padding: '12px 16px',
            background: C.surface, border: `1px solid ${C.borderSolid}`,
            borderRadius: C.radius.md,
          }}>
            <span style={{ color: C.brand, fontFamily: C.mono, fontSize: 12, letterSpacing: '0.1em' }}>›</span>
            <span style={{ flex: 1, color: C.textMuted, fontSize: 13.5 }}>问点什么，或者记录想法…</span>
            <button style={{ width: 32, height: 32, borderRadius: C.radius.sm, background: 'transparent', border: `1px solid ${C.borderStrong}`, color: C.textMid, fontSize: 12, cursor: 'pointer' }}>🎙</button>
            <button style={{ padding: '7px 14px', borderRadius: C.radius.sm, background: C.brand, border: 'none', color: '#fff', fontSize: 12, fontFamily: C.mono, letterSpacing: '0.1em', cursor: 'pointer', fontWeight: 600 }}>SEND</button>
          </div>
        </div>
      </div>
    </div>
  );
}

function LabSidebar({ active }) {
  const items = [
    { key: 'chat', label: '对话', n: '01' },
    { key: 'timeline', label: '时间流', n: '02' },
    { key: 'calendar', label: '日历', n: '03' },
    { key: 'library', label: '资产库', n: '04' },
  ];
  return (
    <div style={{ background: C.bg, padding: '24px 20px', display: 'flex', flexDirection: 'column', gap: 4 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '4px 4px 22px', borderBottom: `1px solid ${C.borderSolid}`, marginBottom: 18 }}>
        <div style={{ width: 26, height: 26, border: `1px solid ${C.brand}`, display: 'flex', alignItems: 'center', justifyContent: 'center', color: C.brand, fontFamily: C.font, fontWeight: 700, fontSize: 13 }}>E</div>
        <div style={{ fontSize: 16, color: C.textHi, fontWeight: 700, letterSpacing: '-0.01em', fontFamily: C.font }}>Eureka</div>
      </div>
      {items.map(it => {
        const isActive = it.key === active;
        return (
          <div key={it.key} style={{
            display: 'grid', gridTemplateColumns: '24px 1fr', gap: 10, padding: '7px 4px',
            color: isActive ? C.textHi : C.textMid,
            fontSize: 13, cursor: 'pointer',
            borderLeft: `2px solid ${isActive ? C.brand : 'transparent'}`,
            paddingLeft: 10,
            fontFamily: C.fontBody,
          }}>
            <span style={{ fontFamily: C.mono, fontSize: 10.5, color: isActive ? C.brand : C.textLo, letterSpacing: '0.1em' }}>{it.n}</span>
            <span>{it.label}</span>
          </div>
        );
      })}
      <div style={{ flex: 1 }}></div>
      <div style={{ padding: '14px 4px 4px', borderTop: `1px solid ${C.borderSolid}`, marginTop: 12 }}>
        <div style={{ fontSize: 10, color: C.textLo, fontFamily: C.mono, letterSpacing: '0.18em', marginBottom: 8 }}>PRESENTATION</div>
        <div style={{ display: 'flex', gap: 0, border: `1px solid ${C.borderSolid}` }}>
          <button style={{ flex: 1, padding: '6px 8px', fontSize: 11, background: C.surface2, color: C.textHi, border: 'none', fontFamily: C.mono, letterSpacing: '0.08em', cursor: 'pointer' }}>ASSETS</button>
          <button style={{ flex: 1, padding: '6px 8px', fontSize: 11, background: 'transparent', color: C.textLo, border: 'none', borderLeft: `1px solid ${C.borderSolid}`, fontFamily: C.mono, letterSpacing: '0.08em', cursor: 'pointer' }}>CAL</button>
        </div>
      </div>
    </div>
  );
}

function LabMessage({ msg, idx }) {
  if (msg.role === 'user') {
    return (
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 4 }}>
        <div style={{ fontSize: 10, color: C.textLo, fontFamily: C.mono, letterSpacing: '0.14em' }}>YOU · {String(idx).padStart(2, '0')}</div>
        <div style={{
          maxWidth: '70%', padding: '12px 18px',
          background: C.brandFaint, color: C.textHi,
          border: `1px solid ${C.brandLine}`,
          borderRadius: C.radius.md,
          fontSize: 14, lineHeight: 1.55,
        }}>{msg.text}</div>
      </div>
    );
  }
  const referenced = msg.card ? DEMO_ASSETS.find(a => a.id === msg.card.ref) : null;
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 10, maxWidth: '85%' }}>
      <div style={{ fontSize: 10, color: C.textLo, fontFamily: C.mono, letterSpacing: '0.14em' }}>AGENT · {String(idx).padStart(2, '0')}</div>
      {msg.toolCall && (
        <div style={{
          alignSelf: 'flex-start',
          display: 'inline-flex', alignItems: 'center', gap: 10,
          padding: '4px 0',
          fontSize: 11, fontFamily: C.mono, color: C.textMid, letterSpacing: '0.06em',
          borderBottom: `1px solid ${C.rule}`,
        }}>
          <span style={{ width: 5, height: 5, background: C.accent.green.marker }}></span>
          <span>TOOL_CALL · {msg.toolCall.name}({msg.toolCall.skill})</span>
          <span style={{ color: C.accent.green.fg }}>· ok</span>
        </div>
      )}
      <div style={{ fontSize: 14, lineHeight: 1.7, color: C.text, fontFamily: C.fontBody }}>
        {msg.text}
        {msg.streaming && <span style={{ display: 'inline-block', width: 7, height: 14, background: C.brand, marginLeft: 3, verticalAlign: 'middle', animation: 'eu-blink 1s infinite' }}></span>}
      </div>
      {referenced && (
        <div style={{ maxWidth: 400, marginTop: 4 }}>
          <LabCard asset={referenced} />
        </div>
      )}
      {msg.precipitate && (
        <button style={{
          alignSelf: 'flex-start', marginTop: 6,
          display: 'inline-flex', alignItems: 'center', gap: 10,
          padding: '6px 12px 6px 14px',
          background: 'transparent', color: C.accent.amber.fg,
          border: `1px solid ${C.accent.amber.edge}`,
          borderLeft: `2px solid ${C.accent.amber.marker}`,
          borderRadius: C.radius.sm,
          fontSize: 11, cursor: 'pointer',
          fontFamily: C.mono, letterSpacing: '0.12em', textTransform: 'uppercase',
        }}>
          ＋ Precipitate as idea
        </button>
      )}
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// 02 · Timeline
// ──────────────────────────────────────────────────────────────────────

function LabTimeline() {
  return (
    <div style={{ width: '100%', height: '100%', background: C.bg, color: C.text, fontFamily: C.fontBody, display: 'grid', gridTemplateRows: '64px 48px 1fr', overflow: 'hidden' }}>
      <div style={{ display: 'grid', gridTemplateColumns: 'auto 1fr auto', alignItems: 'center', gap: 18, padding: '0 32px', borderBottom: `1px solid ${C.borderStrong}` }}>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 14 }}>
          <span style={{ width: 28, height: 1, background: C.brand }}></span>
          <span style={{ fontFamily: C.mono, fontSize: 10.5, letterSpacing: '0.22em', color: C.brand }}>FEED · 02</span>
        </div>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 14 }}>
          <span style={{ fontSize: 20, color: C.textHi, fontWeight: 700, letterSpacing: '-0.015em', fontFamily: C.font }}>时间流</span>
          <span style={{ fontSize: 11.5, color: C.textLo, fontFamily: C.mono }}>52 items · last 7d</span>
        </div>
        <button style={{ padding: '6px 14px', background: 'transparent', border: `1px solid ${C.borderStrong}`, color: C.textMid, fontSize: 11, fontFamily: C.mono, letterSpacing: '0.1em', cursor: 'pointer', borderRadius: C.radius.sm }}>JUMP TO DATE</button>
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 0, padding: '0 32px', borderBottom: `1px solid ${C.borderSolid}` }}>
        {[
          { k: 'ALL', n: 52, active: true },
          { k: 'TODO', n: 14 }, { k: 'EVENT', n: 8 }, { k: 'IDEA', n: 22 }, { k: 'EXPENSE', n: 6 }, { k: 'CONTACT', n: 2 },
        ].map((t, i) => (
          <button key={i} style={{
            padding: '14px 16px',
            background: 'transparent',
            color: t.active ? C.textHi : C.textMid,
            border: 'none',
            borderBottom: `2px solid ${t.active ? C.brand : 'transparent'}`,
            fontSize: 11, cursor: 'pointer', fontFamily: C.mono, letterSpacing: '0.14em',
            display: 'inline-flex', alignItems: 'center', gap: 6,
            marginBottom: -1,
          }}>
            {t.k}
            <span style={{ fontSize: 10, opacity: 0.6 }}>{t.n}</span>
          </button>
        ))}
      </div>
      <div className="eu-noscroll" style={{ overflowY: 'auto', padding: '0 32px 32px' }}>
        {TIMELINE.map((group, gi) => (
          <div key={group.label}>
            <div style={{
              position: 'sticky', top: 0, background: C.bg, padding: '24px 0 14px', zIndex: 1,
              display: 'grid', gridTemplateColumns: 'auto auto 1fr auto', alignItems: 'baseline', gap: 14,
            }}>
              <span style={{ fontFamily: C.mono, fontSize: 11, color: C.brand, letterSpacing: '0.16em' }}>{String(gi + 1).padStart(2, '0')}</span>
              <span style={{ fontSize: 18, color: C.textHi, fontWeight: 700, letterSpacing: '-0.01em', fontFamily: C.font }}>{group.label}</span>
              <span style={{ fontSize: 11.5, color: C.textMid, fontFamily: C.mono, paddingLeft: 4 }}>{group.sub}</span>
              <span style={{ fontSize: 10.5, color: C.textLo, fontFamily: C.mono, letterSpacing: '0.1em' }}>{group.items.length} ITEMS</span>
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              {group.items.map((id, i) => {
                const a = DEMO_ASSETS.find(x => x.id === id);
                if (!a) return null;
                return <LabCard key={id} asset={a} idx={i + 1} />;
              })}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// 03 · Calendar
// ──────────────────────────────────────────────────────────────────────

function LabCalendar() {
  return (
    <div style={{ width: '100%', height: '100%', background: C.bg, color: C.text, fontFamily: C.fontBody, display: 'grid', gridTemplateRows: '68px 36px 1fr', overflow: 'hidden' }}>
      <div style={{ display: 'grid', gridTemplateColumns: 'auto 1fr auto', alignItems: 'center', gap: 18, padding: '0 32px', borderBottom: `1px solid ${C.borderStrong}` }}>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 14 }}>
          <span style={{ width: 28, height: 1, background: C.brand }}></span>
          <span style={{ fontFamily: C.mono, fontSize: 10.5, letterSpacing: '0.22em', color: C.brand }}>CALENDAR · 03</span>
        </div>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 18 }}>
          <span style={{ fontSize: 24, color: C.textHi, fontWeight: 700, letterSpacing: '-0.018em', fontFamily: C.font }}>{CAL.monthLabel}</span>
          <div style={{ display: 'flex', gap: 6 }}>
            <button style={{ ...iconBtnC, width: 30, height: 30 }}>‹</button>
            <button style={{ ...iconBtnC, width: 30, height: 30 }}>›</button>
            <button style={{ marginLeft: 6, padding: '6px 12px', background: C.brandFaint, border: `1px solid ${C.brandLine}`, color: C.brandHi, fontSize: 10.5, fontFamily: C.mono, letterSpacing: '0.1em', cursor: 'pointer', borderRadius: C.radius.sm }}>TODAY</button>
          </div>
        </div>
        <div style={{ display: 'flex', border: `1px solid ${C.borderStrong}`, borderRadius: C.radius.sm }}>
          {['M', 'W', 'D'].map((v, i) => (
            <button key={i} style={{
              padding: '6px 14px', fontSize: 11, cursor: 'pointer',
              background: i === 0 ? C.surface2 : 'transparent',
              color: i === 0 ? C.textHi : C.textLo,
              border: 'none',
              borderRight: i < 2 ? `1px solid ${C.borderStrong}` : 'none',
              fontFamily: C.mono, letterSpacing: '0.1em',
            }}>{v}</button>
          ))}
        </div>
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', borderBottom: `1px solid ${C.borderSolid}` }}>
        {CAL.weekdays.map((d, i) => (
          <div key={d} style={{
            padding: '9px 14px', fontSize: 10, color: C.textMid, fontFamily: C.mono, letterSpacing: '0.16em', textTransform: 'uppercase',
            borderRight: i < 6 ? `1px solid ${C.borderSolid}` : 'none',
          }}>{['MON','TUE','WED','THU','FRI','SAT','SUN'][i]}</div>
        ))}
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gridAutoRows: '1fr', minHeight: 0 }}>
        {CAL.cells.map((c, i) => (
          <div key={i} style={{
            borderRight: (i % 7 !== 6) ? `1px solid ${C.borderSolid}` : 'none',
            borderBottom: i < CAL.cells.length - 7 ? `1px solid ${C.borderSolid}` : 'none',
            padding: '8px 10px', minHeight: 0,
            display: 'flex', flexDirection: 'column', gap: 4,
            background: c.today ? C.surface : 'transparent',
            opacity: c.out ? 0.32 : 1,
            position: 'relative',
          }}>
            {c.today && <div style={{ position: 'absolute', left: 0, top: 0, width: 3, height: '100%', background: C.brand }}></div>}
            <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginBottom: 2 }}>
              <span style={{
                fontSize: 14, fontFamily: C.mono,
                color: c.today ? C.brandHi : (c.out ? C.textLo : C.text),
                fontWeight: c.today ? 700 : 500,
                letterSpacing: '0.01em',
              }}>{String(c.d).padStart(2, '0')}</span>
              {c.today && <span style={{ fontSize: 9, color: C.brand, fontFamily: C.mono, letterSpacing: '0.16em' }}>TODAY</span>}
            </div>
            {c.events && c.events.slice(0, 3).map((e, j) => {
              const ac = C.accent[e.accent];
              return (
                <div key={j} style={{
                  display: 'flex', alignItems: 'center', gap: 5,
                  padding: '3px 6px 3px 8px',
                  background: ac.bg,
                  borderLeft: `2px solid ${ac.marker}`,
                  fontSize: 10.5, color: ac.fg, fontWeight: 500,
                  overflow: 'hidden', whiteSpace: 'nowrap', textOverflow: 'ellipsis',
                  textDecoration: e.todo ? 'line-through' : 'none',
                  textDecorationColor: 'rgba(136,170,224,0.35)',
                }}>
                  {e.time && <span style={{ fontFamily: C.mono, fontSize: 9.5, opacity: 0.85, letterSpacing: '0.02em' }}>{e.time}</span>}
                  <span style={{ overflow: 'hidden', textOverflow: 'ellipsis' }}>{e.t}</span>
                </div>
              );
            })}
            {c.events && c.events.length > 3 && (
              <div style={{ fontSize: 10, color: C.textLo, fontFamily: C.mono, paddingLeft: 8, letterSpacing: '0.04em' }}>+{c.events.length - 3} more</div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// 04 · SkillCard System
// ──────────────────────────────────────────────────────────────────────

function LabCards() {
  const todo = DEMO_ASSETS.find(a => a.id === 'a1');
  const todoOverdue = DEMO_ASSETS.find(a => a.id === 'a7');
  const event = DEMO_ASSETS.find(a => a.id === 'a2');
  const idea = DEMO_ASSETS.find(a => a.id === 'a3');
  const expense = DEMO_ASSETS.find(a => a.id === 'a4');
  const contact = DEMO_ASSETS.find(a => a.id === 'a5');

  return (
    <div style={{ width: '100%', height: '100%', background: C.bg, color: C.text, fontFamily: C.fontBody, padding: 40, boxSizing: 'border-box', overflow: 'hidden', display: 'flex', flexDirection: 'column', gap: 24 }}>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr auto', alignItems: 'baseline', borderBottom: `1px solid ${C.borderStrong}`, paddingBottom: 18 }}>
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 8 }}>
            <span style={{ width: 24, height: 1, background: C.brand }}></span>
            <span style={{ fontFamily: C.mono, fontSize: 10.5, letterSpacing: '0.22em', color: C.brand }}>SKILLCARD · 04</span>
          </div>
          <div style={{ fontSize: 30, fontWeight: 700, color: C.textHi, letterSpacing: '-0.02em', fontFamily: C.font }}>统一资产卡片 · 4 种 layout</div>
          <div style={{ fontSize: 12.5, color: C.textMid, marginTop: 6, lineHeight: 1.55, maxWidth: 720 }}>每张卡是一条「实验记录」——左侧 accent 标线、caps mono 标识 skill 名，accent.bg 用作 6% 微 tint。</div>
        </div>
        <div style={{ fontFamily: C.mono, fontSize: 10.5, color: C.textLo, letterSpacing: '0.18em', textAlign: 'right' }}>HORIZONTAL · STACKED<br />INLINE · COMPACT</div>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 28, flex: 1, minHeight: 0 }}>
        <CGroup label="HORIZONTAL" desc="主标题 + 副文本同行排布，索引编号在左">
          <LabCard asset={todo} idx={1} />
          <LabCard asset={event} idx={2} />
          <LabCard asset={expense} idx={3} />
          <LabCard asset={contact} idx={4} />
        </CGroup>

        <CGroup label="STACKED" desc="标题在上 + 多行内容在下，适合 idea / note">
          <LabCard asset={idea} />
          <LabCard asset={DEMO_ASSETS.find(a => a.id === 'a8')} />
        </CGroup>

        <CGroup label="INLINE" desc="极致紧凑，单行 + 底部细规则线分隔">
          <div style={{ display: 'flex', flexDirection: 'column', gap: 0, borderTop: `1px solid ${C.rule}` }}>
            <LabCard asset={todo} layout="inline" />
            <LabCard asset={event} layout="inline" />
            <LabCard asset={expense} layout="inline" />
            <LabCard asset={contact} layout="inline" />
          </div>
        </CGroup>

        <CGroup label="COMPACT + STATES" desc="日历格子内 chip / 状态变体">
          <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
            <LabCard asset={event} layout="compact" />
            <LabCard asset={{ ...event, payload: { title: 'demo 演练', start_at: '5月27日 15:00' }, accent: 'purple' }} layout="compact" />
            <LabCard asset={{ ...todo, payload: { title: '回 Linus 邮件' }, accent: 'blue' }} layout="compact" />
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginTop: 6 }}>
            <CStateLabel label="SELECTED" />
            <LabCard asset={event} selected />
            <CStateLabel label="OVERDUE" />
            <LabCard asset={todoOverdue} />
          </div>
        </CGroup>
      </div>
    </div>
  );
}

function CGroup({ label, desc, children }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 12, minHeight: 0 }}>
      <div style={{ borderBottom: `1px solid ${C.borderSolid}`, paddingBottom: 8, display: 'flex', alignItems: 'baseline', justifyContent: 'space-between' }}>
        <span style={{ fontSize: 11, color: C.brand, fontFamily: C.mono, letterSpacing: '0.18em', fontWeight: 600 }}>{label}</span>
      </div>
      <div style={{ fontSize: 11.5, color: C.textMid, lineHeight: 1.55 }}>{desc}</div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>{children}</div>
    </div>
  );
}

function CStateLabel({ label }) {
  return (
    <div style={{ fontFamily: C.mono, fontSize: 10, color: C.textLo, letterSpacing: '0.2em', borderBottom: `1px solid ${C.rule}`, paddingBottom: 4, marginTop: 4 }}>{label}</div>
  );
}

Object.assign(window, {
  LabFoundations, LabChat, LabTimeline, LabCalendar, LabCards,
});
