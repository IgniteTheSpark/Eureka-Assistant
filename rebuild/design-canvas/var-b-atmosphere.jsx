// var-b-atmosphere.jsx — Variation B · Atmosphere
// "Cool tech with a heartbeat." Manrope + JetBrains Mono. Soft rounded surfaces,
// subtle glows on accents, depth gradient on canvas. AI 在场感更强。

const B = {
  name: 'B · Atmosphere',
  subtitle: 'Quiet tech with depth and pulse',
  // Surfaces — slight blue undertone, gradient on bg
  bg: '#0b1220',
  bgGradient: 'radial-gradient(1200px 700px at 20% -10%, rgba(82,128,200,0.10), transparent 60%), radial-gradient(900px 600px at 110% 110%, rgba(110,90,200,0.08), transparent 60%), #0b1220',
  surface: 'rgba(255,255,255,0.025)',
  surface2: 'rgba(255,255,255,0.045)',
  surface3: 'rgba(255,255,255,0.07)',
  border: 'rgba(255,255,255,0.07)',
  borderStrong: 'rgba(255,255,255,0.14)',
  // Text
  textHi: '#f4f7fb',
  text:   '#d4dbe6',
  textMid:'#9aa6b8',
  textLo: '#6c7689',
  textMuted: '#4a5364',
  // Brand — luminous ocean
  brand: '#6f9eff',
  brandHi: '#a4c2ff',
  brandGlow: '0 0 24px rgba(111,158,255,0.35)',
  brandFaint: 'rgba(111,158,255,0.12)',
  brandLine: 'rgba(111,158,255,0.32)',
  // Accents — slightly more saturation than Slate; tinted cards
  accent: {
    blue:    { fg: '#8ab4ff', bg: 'rgba(138,180,255,0.10)', edge: 'rgba(138,180,255,0.26)', solid: '#6f9eff', glow: 'rgba(111,158,255,0.35)' },
    amber:   { fg: '#f5c977', bg: 'rgba(245,201,119,0.10)', edge: 'rgba(245,201,119,0.26)', solid: '#e5b35a', glow: 'rgba(245,201,119,0.30)' },
    green:   { fg: '#86e0a5', bg: 'rgba(134,224,165,0.10)', edge: 'rgba(134,224,165,0.26)', solid: '#5fc685', glow: 'rgba(134,224,165,0.30)' },
    red:     { fg: '#ff8da1', bg: 'rgba(255,141,161,0.10)', edge: 'rgba(255,141,161,0.26)', solid: '#ec6a83', glow: 'rgba(255,141,161,0.30)' },
    purple:  { fg: '#c4a8ff', bg: 'rgba(196,168,255,0.10)', edge: 'rgba(196,168,255,0.26)', solid: '#9c80f0', glow: 'rgba(196,168,255,0.30)' },
    gray:    { fg: '#9aa6b8', bg: 'rgba(154,166,184,0.08)', edge: 'rgba(154,166,184,0.20)', solid: '#7c8898', glow: 'rgba(154,166,184,0.20)' },
    neutral: { fg: '#d4dbe6', bg: 'rgba(212,219,230,0.05)', edge: 'rgba(212,219,230,0.16)', solid: '#9aa6b8', glow: 'rgba(212,219,230,0.18)' },
  },
  font: '"Manrope","Noto Sans SC", system-ui, sans-serif',
  mono: '"JetBrains Mono", ui-monospace, monospace',
  radius: { sm: 8, md: 12, lg: 16, xl: 24 },
};

// ──────────────────────────────────────────────────────────────────────
// SkillCard for Atmosphere
// ──────────────────────────────────────────────────────────────────────

function AtmoCard({ asset, hover, selected, layout }) {
  const ac = B.accent[asset.accent];
  const lay = layout || asset.layout;

  const iconEl = (
    <div style={{
      width: 32, height: 32, borderRadius: 10, flex: '0 0 32px',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      background: `linear-gradient(140deg, ${ac.bg}, rgba(255,255,255,0.02))`,
      color: ac.fg, fontFamily: B.mono, fontSize: 14, fontWeight: 600,
      border: `1px solid ${ac.edge}`,
      boxShadow: `inset 0 0 12px ${ac.glow.replace(/[\d.]+\)$/, '0.15)')}`,
    }}>{asset.icon}</div>
  );

  if (lay === 'inline') {
    return (
      <div style={{
        display: 'flex', alignItems: 'center', gap: 12,
        padding: '10px 14px', borderRadius: B.radius.md,
        background: ac.bg, border: `1px solid ${ac.edge}`,
        fontSize: 13, color: B.text,
      }}>
        <span style={{ color: ac.fg, fontFamily: B.mono, fontSize: 12 }}>{asset.icon}</span>
        <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
          {asset.payload.content || asset.payload.title || asset.payload.name || asset.payload.description}
        </span>
        <span style={{ color: B.textLo, fontFamily: B.mono, fontSize: 11 }}>{asset.time}</span>
      </div>
    );
  }

  if (lay === 'compact') {
    return (
      <div style={{
        display: 'flex', alignItems: 'center', gap: 6,
        padding: '4px 8px', borderRadius: 6,
        background: ac.bg, color: ac.fg,
        fontSize: 11, fontWeight: 500,
        border: `1px solid ${ac.edge}`,
        boxShadow: hover ? `0 0 16px ${ac.glow}` : 'none',
      }}>
        <span style={{ width: 5, height: 5, borderRadius: 999, background: ac.solid, boxShadow: `0 0 6px ${ac.glow}` }}></span>
        <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{asset.payload.title || asset.payload.content}</span>
      </div>
    );
  }

  if (lay === 'stacked') {
    const p = asset.payload;
    return (
      <div style={{
        display: 'flex', flexDirection: 'column', gap: 10,
        padding: 18, borderRadius: B.radius.lg,
        background: ac.bg, border: `1px solid ${ac.edge}`,
        boxShadow: hover ? `0 8px 32px ${ac.glow.replace(/[\d.]+\)$/, '0.20)')}` : 'none',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          {iconEl}
          <div style={{ fontSize: 14, fontWeight: 600, color: B.textHi, letterSpacing: '-0.005em' }}>{p.title}</div>
          <div style={{ marginLeft: 'auto', fontSize: 11, color: B.textLo, fontFamily: B.mono }}>{asset.time}</div>
        </div>
        <div style={{ fontSize: 13, color: B.text, lineHeight: 1.6 }}>{p.content}</div>
      </div>
    );
  }

  // horizontal
  const p = asset.payload;
  const primary = p.content || p.title || p.amount || p.name || '';
  const secondary = p.due_date || p.start_at || p.description || p.company || '';
  const meta = [];
  if (p.duration) meta.push(p.duration);
  if (p.location) meta.push(p.location);
  if (p.category) meta.push(p.category);
  if (p.title && p.name) meta.push(p.title);
  if (p.phone) meta.push(p.phone);

  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 14,
      padding: '14px 16px', borderRadius: B.radius.md,
      background: ac.bg, border: `1px solid ${selected ? ac.solid : ac.edge}`,
      boxShadow: hover || selected ? `0 6px 24px ${ac.glow.replace(/[\d.]+\)$/, '0.18)')}` : 'none',
      transition: 'all 240ms cubic-bezier(.2,.7,.3,1)',
    }}>
      {iconEl}
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{
          fontSize: 14, fontWeight: 500,
          color: asset.payload.status === 'overdue' ? ac.fg : B.textHi,
          letterSpacing: '-0.005em', lineHeight: 1.4,
        }}>{primary}</div>
        {(secondary || meta.length > 0) && (
          <div style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: 8, marginTop: 4 }}>
            {secondary && <span style={{ fontSize: 12, color: B.textMid }}>{secondary}</span>}
            {meta.map((m, i) => (
              <span key={i} style={{ fontSize: 11, color: B.textLo, fontFamily: B.mono }}>· {m}</span>
            ))}
          </div>
        )}
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 4, opacity: 0.6 }}>
        {asset.skill === 'todo' && <button style={iconBtnB}>✓</button>}
        <button style={iconBtnB}>⋯</button>
      </div>
    </div>
  );
}

const iconBtnB = {
  width: 28, height: 28, padding: 0, border: 'none', background: 'transparent',
  color: B.textMid, fontSize: 13, cursor: 'pointer', borderRadius: 8,
  display: 'flex', alignItems: 'center', justifyContent: 'center',
};

// ──────────────────────────────────────────────────────────────────────
// 00 · Foundations
// ──────────────────────────────────────────────────────────────────────

function AtmoFoundations() {
  return (
    <div style={{
      width: '100%', height: '100%', background: B.bgGradient, color: B.text,
      fontFamily: B.font, padding: 40, boxSizing: 'border-box',
      display: 'flex', flexDirection: 'column', gap: 32,
      overflow: 'hidden',
    }}>
      <div style={{ display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between', borderBottom: `1px solid ${B.border}`, paddingBottom: 24 }}>
        <div>
          <div style={{ fontFamily: B.mono, fontSize: 10.5, letterSpacing: '0.22em', color: B.textLo, textTransform: 'uppercase', marginBottom: 12 }}>EUREKA / VARIATION B</div>
          <div style={{ fontSize: 52, fontWeight: 700, letterSpacing: '-0.035em', color: B.textHi, lineHeight: 1 }}>
            Atmosphere
            <span style={{ display: 'inline-block', width: 10, height: 10, borderRadius: 999, background: B.brand, marginLeft: 12, boxShadow: B.brandGlow, verticalAlign: 'middle' }}></span>
          </div>
          <div style={{ fontSize: 14, color: B.textMid, marginTop: 10, maxWidth: 540, lineHeight: 1.55 }}>暗色，但有大气层。微弱辉光、柔和圆角、深度感。Arc / Things 的精神，AI 像在房间里。</div>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 6, fontFamily: B.mono, fontSize: 10.5, color: B.textLo, textAlign: 'right' }}>
          <div>MANROPE / JETBRAINS MONO</div>
          <div>8 / 12 / 16 / 24 RADIUS</div>
          <div>DENSITY · AIRY</div>
        </div>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1.1fr 1.1fr 1fr', gap: 36, flex: 1, minHeight: 0 }}>
        {/* Neutrals */}
        <EuArtboardSection label="Neutrals" num="01" fontMono={B.mono}>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
            <EuSwatch color="#0b1220"           label="bg"          sub="canvas"  mono="#0B1220" txt={B.text} border={B.border} fontMono={B.mono} />
            <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
              <div style={{ height: 56, borderRadius: 10, background: B.surface, border: `1px solid ${B.border}`, display: 'flex', alignItems: 'flex-end', padding: 8, color: B.text, fontFamily: B.mono, fontSize: 10, backdropFilter: 'blur(8px)' }}>α 2.5%</div>
              <div style={{ fontSize: 11, fontWeight: 600 }}>surface</div>
              <div style={{ fontSize: 10, color: B.textLo }}>card · glass</div>
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
              <div style={{ height: 56, borderRadius: 10, background: B.surface2, border: `1px solid ${B.border}`, display: 'flex', alignItems: 'flex-end', padding: 8, color: B.text, fontFamily: B.mono, fontSize: 10 }}>α 4.5%</div>
              <div style={{ fontSize: 11, fontWeight: 600 }}>surface.raised</div>
              <div style={{ fontSize: 10, color: B.textLo }}>elevated</div>
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
              <div style={{ height: 56, borderRadius: 10, background: B.surface3, border: `1px solid ${B.border}`, display: 'flex', alignItems: 'flex-end', padding: 8, color: B.text, fontFamily: B.mono, fontSize: 10 }}>α 7%</div>
              <div style={{ fontSize: 11, fontWeight: 600 }}>surface.hover</div>
              <div style={{ fontSize: 10, color: B.textLo }}>hover</div>
            </div>
            <EuSwatch color="rgba(255,255,255,0.07)" label="border" sub="default" mono="α 7%" txt={B.text} border={B.border} fontMono={B.mono} />
            <EuSwatch color={B.textHi}              label="text.hi" sub="title"   mono="#F4F7FB" txt="#111" border="transparent" fontMono={B.mono} />
          </div>
          <div style={{ marginTop: 10, display: 'flex', flexDirection: 'column', gap: 8 }}>
            <BTextRow label="text.hi"  hex="#F4F7FB" color={B.textHi}  sample="标题 · A quiet companion" />
            <BTextRow label="text"     hex="#D4DBE6" color={B.text}    sample="正文 · 关于硬件断网的策略" />
            <BTextRow label="text.mid" hex="#9AA6B8" color={B.textMid} sample="副文本 · 5月26日 · 10:00" />
            <BTextRow label="text.lo"  hex="#6C7689" color={B.textLo}  sample="辅助 · created 14:32" />
          </div>
        </EuArtboardSection>

        {/* Brand + Accents */}
        <EuArtboardSection label="Brand + Accents" num="02" fontMono={B.mono}>
          <div style={{
            position: 'relative', borderRadius: 14, padding: 18,
            background: `linear-gradient(135deg, rgba(111,158,255,0.18), rgba(156,128,240,0.10))`,
            border: `1px solid ${B.brandLine}`,
            boxShadow: B.brandGlow,
            overflow: 'hidden',
          }}>
            <div style={{ position: 'absolute', top: -30, right: -30, width: 140, height: 140, borderRadius: 999, background: 'radial-gradient(circle, rgba(111,158,255,0.35), transparent 70%)' }}></div>
            <div style={{ position: 'relative' }}>
              <div style={{ fontFamily: B.mono, fontSize: 10.5, letterSpacing: '0.18em', color: B.brandHi, opacity: 0.85 }}>BRAND · OCEAN</div>
              <div style={{ fontSize: 26, fontWeight: 700, color: B.textHi, marginTop: 6, letterSpacing: '-0.02em' }}>#6F9EFF</div>
              <div style={{ fontSize: 11.5, color: B.textMid, marginTop: 4 }}>带辉光的深海蓝。强调时配合 box-shadow 形成"光"。</div>
            </div>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8, marginTop: 6 }}>
            {ACCENT_ROLES.map(r => {
              const ac = B.accent[r.key];
              return (
                <div key={r.key} style={{
                  display: 'flex', alignItems: 'center', gap: 10,
                  padding: '10px 12px', borderRadius: 10,
                  background: ac.bg, border: `1px solid ${ac.edge}`,
                }}>
                  <span style={{ width: 8, height: 8, borderRadius: 999, background: ac.solid, boxShadow: `0 0 10px ${ac.glow}`, flex: '0 0 8px' }}></span>
                  <div style={{ flex: 1 }}>
                    <div style={{ fontSize: 11.5, color: ac.fg, fontWeight: 700, letterSpacing: '0.02em', fontFamily: B.mono }}>{r.key.toUpperCase()}</div>
                    <div style={{ fontSize: 10, color: B.textMid }}>{r.role}</div>
                  </div>
                </div>
              );
            })}
          </div>
        </EuArtboardSection>

        {/* Type + Geometry */}
        <EuArtboardSection label="Type · Space · Motion" num="03" fontMono={B.mono}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 4, padding: 14, borderRadius: 12, background: B.surface, border: `1px solid ${B.border}` }}>
            <div style={{ fontSize: 34, fontWeight: 700, color: B.textHi, letterSpacing: '-0.03em', lineHeight: 1 }}>Aa 阿</div>
            <div style={{ fontSize: 10.5, color: B.textLo, fontFamily: B.mono, marginTop: 4 }}>MANROPE · NOTO SANS SC</div>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 4, padding: 14, borderRadius: 12, background: B.surface, border: `1px solid ${B.border}` }}>
            <div style={{ fontSize: 22, fontWeight: 500, color: B.textHi, fontFamily: B.mono, lineHeight: 1 }}>0123 ¥68</div>
            <div style={{ fontSize: 10.5, color: B.textLo, fontFamily: B.mono, marginTop: 4 }}>JETBRAINS MONO · 数字 / 时间</div>
          </div>

          <div style={{ marginTop: 4, display: 'flex', alignItems: 'center', gap: 10 }}>
            <RadiusDot s={8} />
            <RadiusDot s={12} />
            <RadiusDot s={16} />
            <RadiusDot s={24} />
            <RadiusDot s={36} round />
            <span style={{ fontSize: 10.5, color: B.textLo, fontFamily: B.mono, marginLeft: 'auto' }}>sm md lg xl full</span>
          </div>

          <div style={{ padding: 12, borderRadius: 10, background: B.surface, border: `1px solid ${B.border}` }}>
            <div style={{ fontSize: 10.5, color: B.textLo, fontFamily: B.mono, letterSpacing: '0.12em', marginBottom: 8 }}>MOTION · GLOW</div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
              <div style={{ position: 'relative' }}>
                <div style={{ width: 14, height: 14, borderRadius: 999, background: B.brand, boxShadow: B.brandGlow }}></div>
                <div style={{ position: 'absolute', inset: -4, borderRadius: 999, border: `1px solid ${B.brand}`, opacity: 0.4, animation: 'eu-pulse 2s ease-out infinite' }}></div>
              </div>
              <div style={{ fontSize: 11.5, color: B.text, lineHeight: 1.55 }}>
                AI 工作中 · stagger 60ms / 资产卡片<br />
                <span style={{ color: B.textLo, fontFamily: B.mono, fontSize: 10.5 }}>fast 150 · normal 280 · slow 420</span>
              </div>
            </div>
          </div>
        </EuArtboardSection>
      </div>
    </div>
  );
}

function RadiusDot({ s, round }) {
  return (
    <div style={{
      width: 32, height: 32, borderRadius: round ? 999 : s,
      background: B.surface2, border: `1px solid ${B.borderStrong}`,
    }}></div>
  );
}

function BTextRow({ label, hex, color, sample }) {
  return (
    <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
      <div style={{ width: 70, fontSize: 10.5, color: B.textLo, fontFamily: B.mono }}>{label}</div>
      <div style={{ flex: 1, fontSize: 14, color, lineHeight: 1.45 }}>{sample}</div>
      <div style={{ fontSize: 10, color: B.textLo, fontFamily: B.mono }}>{hex}</div>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// 01 · AI Chat
// ──────────────────────────────────────────────────────────────────────

function AtmoChat() {
  return (
    <div style={{
      width: '100%', height: '100%', background: B.bgGradient, color: B.text,
      fontFamily: B.font, display: 'grid', gridTemplateColumns: '240px 1fr',
      overflow: 'hidden',
    }}>
      <AtmoSidebar active="chat" />
      <div style={{ display: 'grid', gridTemplateRows: '56px 1fr 96px', minHeight: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 24px', borderBottom: `1px solid ${B.border}` }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <span style={{ width: 6, height: 6, borderRadius: 999, background: B.accent.green.solid, boxShadow: `0 0 10px ${B.accent.green.glow}` }}></span>
            <span style={{ fontSize: 14, color: B.textHi, fontWeight: 600 }}>统一助手</span>
            <span style={{ fontSize: 11, color: B.textLo, fontFamily: B.mono }}>session · 7f3a · 在线</span>
          </div>
          <div style={{ display: 'flex', gap: 8 }}>
            <button style={iconBtnB}>⌕</button>
            <button style={iconBtnB}>⋯</button>
          </div>
        </div>

        <div className="eu-noscroll" style={{ padding: '32px 40px', overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 24 }}>
          {DEMO_CHAT.map((m, i) => <AtmoMessage key={i} msg={m} />)}
        </div>

        <div style={{ borderTop: `1px solid ${B.border}`, padding: '20px 40px' }}>
          <div style={{
            display: 'flex', alignItems: 'center', gap: 12,
            padding: '12px 16px', borderRadius: 14,
            background: B.surface, border: `1px solid ${B.borderStrong}`,
            boxShadow: `0 4px 24px rgba(0,0,0,0.20), inset 0 1px 0 rgba(255,255,255,0.04)`,
          }}>
            <span style={{ flex: 1, color: B.textMuted, fontSize: 13.5 }}>问点什么，或者记录想法…</span>
            <button style={{ width: 34, height: 34, borderRadius: 10, background: B.surface2, border: `1px solid ${B.border}`, color: B.textMid, fontSize: 14, cursor: 'pointer' }}>🎙</button>
            <button style={{ width: 34, height: 34, borderRadius: 10, background: B.brand, border: 'none', color: '#fff', fontSize: 14, cursor: 'pointer', boxShadow: B.brandGlow }}>↑</button>
          </div>
        </div>
      </div>
    </div>
  );
}

function AtmoSidebar({ active }) {
  const items = [
    { key: 'chat', label: '对话', glyph: '◊' },
    { key: 'timeline', label: '时间流', glyph: '≡' },
    { key: 'calendar', label: '日历', glyph: '▦' },
    { key: 'library', label: '资产库', glyph: '⌗' },
  ];
  return (
    <div style={{
      padding: '24px 16px', display: 'flex', flexDirection: 'column', gap: 4,
      background: 'rgba(0,0,0,0.20)', borderRight: `1px solid ${B.border}`,
      backdropFilter: 'blur(12px)',
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '4px 8px 20px' }}>
        <div style={{ width: 26, height: 26, borderRadius: 8, background: `linear-gradient(135deg, ${B.brand}, #9c80f0)`, boxShadow: B.brandGlow, display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff', fontFamily: B.font, fontWeight: 700, fontSize: 13 }}>E</div>
        <div style={{ fontSize: 14, color: B.textHi, fontWeight: 700, letterSpacing: '-0.01em' }}>Eureka</div>
      </div>
      {items.map(it => {
        const isActive = it.key === active;
        return (
          <div key={it.key} style={{
            display: 'flex', alignItems: 'center', gap: 12, padding: '8px 12px', borderRadius: 10,
            background: isActive ? B.brandFaint : 'transparent',
            color: isActive ? B.brandHi : B.textMid,
            fontSize: 13.5, cursor: 'pointer',
            border: `1px solid ${isActive ? B.brandLine : 'transparent'}`,
          }}>
            <span style={{ fontFamily: B.mono, fontSize: 12, opacity: 0.85 }}>{it.glyph}</span>
            <span>{it.label}</span>
          </div>
        );
      })}
      <div style={{ flex: 1 }}></div>
      <div style={{ padding: '12px 8px', borderTop: `1px solid ${B.border}`, marginTop: 12 }}>
        <div style={{ fontSize: 10, color: B.textLo, fontFamily: B.mono, letterSpacing: '0.14em', marginBottom: 8 }}>MODE</div>
        <div style={{ display: 'flex', background: B.surface, borderRadius: 10, padding: 3, border: `1px solid ${B.border}` }}>
          <button style={{ flex: 1, padding: '5px 8px', fontSize: 11, background: B.brandFaint, color: B.brandHi, border: 'none', borderRadius: 7, fontFamily: B.font, cursor: 'pointer', fontWeight: 600 }}>资产</button>
          <button style={{ flex: 1, padding: '5px 8px', fontSize: 11, background: 'transparent', color: B.textLo, border: 'none', fontFamily: B.font, cursor: 'pointer' }}>日历</button>
        </div>
      </div>
    </div>
  );
}

function AtmoMessage({ msg }) {
  if (msg.role === 'user') {
    // Voice / flash-capture variant
    if (msg.voice) {
      const v = msg.voice;
      return (
        <div style={{ display: 'flex', justifyContent: 'flex-end' }}>
          <div style={{
            maxWidth: '78%', display: 'flex', flexDirection: 'column', gap: 8,
            padding: '12px 14px', borderRadius: 18, borderTopRightRadius: 6,
            background: `linear-gradient(140deg, rgba(111,158,255,0.20), rgba(156,128,240,0.14))`,
            border: `1px solid ${B.brandLine}`,
            boxShadow: `0 4px 18px rgba(111,158,255,0.18)`,
          }}>
            {/* Player row */}
            <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
              <button style={{
                width: 32, height: 32, borderRadius: 999,
                background: `linear-gradient(135deg, ${B.brandHi}, ${B.brand})`,
                boxShadow: B.brandGlow, border: 'none',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                color: '#fff', fontSize: 12, cursor: 'pointer', flex: '0 0 32px',
                paddingLeft: 3,
              }}>▶</button>
              <div style={{ display: 'flex', alignItems: 'center', gap: 1.5, height: 22, flex: 1, minWidth: 0 }}>
                {v.wave.map((h, i) => (
                  <div key={i} style={{
                    flex: 1, height: `${h * 100}%`,
                    background: i < v.wave.length * 0.0 ? '#ffffff' : 'rgba(255,255,255,0.55)',
                    borderRadius: 1,
                  }}></div>
                ))}
              </div>
              <span style={{ fontSize: 11, color: 'rgba(255,255,255,0.75)', fontFamily: B.mono, letterSpacing: '0.04em', flex: '0 0 auto' }}>{v.duration}</span>
            </div>
            {/* File hint */}
            <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 10, fontFamily: B.mono, color: 'rgba(255,255,255,0.55)', letterSpacing: '0.04em' }}>
              <span>♪</span>
              <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', flex: 1 }}>{v.filename}</span>
              <span>{v.time}</span>
            </div>
            {/* Transcript */}
            <div style={{
              marginTop: 2, padding: '8px 10px', borderRadius: 8,
              background: 'rgba(0,0,0,0.20)',
              fontSize: 13.5, lineHeight: 1.55, color: '#f4f7fb',
              fontStyle: 'italic',
            }}>"{v.transcript}"</div>
          </div>
        </div>
      );
    }
    // Plain text user bubble
    return (
      <div style={{ display: 'flex', justifyContent: 'flex-end' }}>
        <div style={{
          maxWidth: '70%', padding: '12px 18px', borderRadius: 18, borderTopRightRadius: 6,
          background: `linear-gradient(135deg, ${B.brand}, #5b85e0)`, color: '#fff',
          fontSize: 14, lineHeight: 1.5,
          boxShadow: `0 4px 20px ${B.accent.blue.glow}`,
        }}>{msg.text}</div>
      </div>
    );
  }
  const referenced = msg.card ? DEMO_ASSETS.find(a => a.id === msg.card.ref) : null;
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 12, maxWidth: '85%' }}>
      {msg.toolCall && (
        <div style={{
          alignSelf: 'flex-start',
          display: 'inline-flex', alignItems: 'center', gap: 8, padding: '4px 10px',
          fontSize: 11, fontFamily: B.mono, color: B.textMid,
          background: B.surface, border: `1px solid ${B.border}`, borderRadius: 999,
        }}>
          <span style={{ width: 5, height: 5, borderRadius: 999, background: B.accent.green.solid, boxShadow: `0 0 6px ${B.accent.green.glow}` }}></span>
          {msg.toolCall.name} · {msg.toolCall.skill}
        </div>
      )}
      <div style={{ fontSize: 14, lineHeight: 1.65, color: B.text }}>
        {msg.text}
        {msg.streaming && <span style={{ display: 'inline-block', width: 7, height: 14, background: B.brand, marginLeft: 3, verticalAlign: 'middle', borderRadius: 2, boxShadow: B.brandGlow, animation: 'eu-blink 1s infinite' }}></span>}
      </div>
      {referenced && (
        <div style={{ maxWidth: 380 }}>
          <AtmoCard asset={referenced} />
        </div>
      )}
      {msg.precipitate && (
        <button style={{
          alignSelf: 'flex-start', marginTop: 4,
          display: 'inline-flex', alignItems: 'center', gap: 8,
          padding: '8px 14px', borderRadius: 999,
          background: B.accent.amber.bg, color: B.accent.amber.fg,
          border: `1px solid ${B.accent.amber.edge}`,
          fontSize: 12, cursor: 'pointer', fontWeight: 500,
        }}>
          <span>＋ 沉淀为想法</span>
        </button>
      )}
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// 02 · Timeline
// ──────────────────────────────────────────────────────────────────────

function AtmoTimeline() {
  return (
    <div style={{ width: '100%', height: '100%', background: B.bgGradient, color: B.text, fontFamily: B.font, display: 'grid', gridTemplateRows: '60px 44px 1fr', overflow: 'hidden' }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 28px', borderBottom: `1px solid ${B.border}` }}>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 12 }}>
          <span style={{ fontSize: 18, color: B.textHi, fontWeight: 700, letterSpacing: '-0.01em' }}>时间流</span>
          <span style={{ fontSize: 11, color: B.textLo, fontFamily: B.mono }}>52 items · 7d</span>
        </div>
        <button style={{ padding: '6px 12px', borderRadius: 999, background: B.surface, border: `1px solid ${B.borderStrong}`, color: B.textMid, fontSize: 12, cursor: 'pointer' }}>📅 跳到日历</button>
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '0 28px', borderBottom: `1px solid ${B.border}` }}>
        {[
          { k: '全部', n: 52, active: true },
          { k: '待办', n: 14 }, { k: '事件', n: 8 }, { k: '想法', n: 22 }, { k: '记账', n: 6 }, { k: '名片', n: 2 },
        ].map((t, i) => (
          <button key={i} style={{
            padding: '5px 12px', borderRadius: 999,
            background: t.active ? B.brandFaint : 'transparent',
            color: t.active ? B.brandHi : B.textMid,
            border: `1px solid ${t.active ? B.brandLine : 'transparent'}`,
            fontSize: 12, cursor: 'pointer', fontWeight: 500,
            display: 'inline-flex', alignItems: 'center', gap: 6,
          }}>
            {t.k}
            <span style={{ fontFamily: B.mono, fontSize: 10, opacity: 0.7 }}>{t.n}</span>
          </button>
        ))}
      </div>
      <div className="eu-noscroll" style={{ overflowY: 'auto', padding: '8px 28px 28px' }}>
        {TIMELINE.map(group => (
          <div key={group.label}>
            <div style={{
              position: 'sticky', top: 0, padding: '20px 0 10px', zIndex: 1,
              display: 'flex', alignItems: 'baseline', gap: 12,
              background: 'linear-gradient(to bottom, #0b1220 70%, transparent)',
            }}>
              <span style={{ fontSize: 15, color: B.textHi, fontWeight: 700, letterSpacing: '-0.005em' }}>{group.label}</span>
              <span style={{ fontSize: 11.5, color: B.textLo, fontFamily: B.mono }}>{group.sub}</span>
              <span style={{ flex: 1, height: 1, background: B.border }}></span>
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
              {group.items.map(id => {
                const a = DEMO_ASSETS.find(x => x.id === id);
                if (!a) return null;
                return <AtmoCard key={id} asset={a} />;
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

function AtmoCalendar() {
  return (
    <div style={{ width: '100%', height: '100%', background: B.bgGradient, color: B.text, fontFamily: B.font, display: 'grid', gridTemplateRows: '60px 34px 1fr', overflow: 'hidden' }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 28px', borderBottom: `1px solid ${B.border}` }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
          <span style={{ fontSize: 18, color: B.textHi, fontWeight: 700, letterSpacing: '-0.01em' }}>{CAL.monthLabel}</span>
          <div style={{ display: 'flex', gap: 4 }}>
            <button style={{ ...iconBtnB, width: 30, height: 30, background: B.surface, border: `1px solid ${B.border}` }}>‹</button>
            <button style={{ ...iconBtnB, width: 30, height: 30, background: B.surface, border: `1px solid ${B.border}` }}>›</button>
            <button style={{ marginLeft: 8, padding: '5px 12px', borderRadius: 999, background: B.brandFaint, border: `1px solid ${B.brandLine}`, color: B.brandHi, fontSize: 11.5, cursor: 'pointer' }}>今天</button>
          </div>
        </div>
        <div style={{ display: 'flex', background: B.surface, borderRadius: 999, padding: 3, border: `1px solid ${B.border}` }}>
          {['月', '周', '日'].map((v, i) => (
            <button key={i} style={{
              padding: '4px 14px', borderRadius: 999, fontSize: 11.5, cursor: 'pointer',
              background: i === 0 ? B.surface3 : 'transparent',
              color: i === 0 ? B.textHi : B.textLo,
              border: 'none', fontWeight: i === 0 ? 600 : 400,
            }}>{v}</button>
          ))}
        </div>
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', borderBottom: `1px solid ${B.border}` }}>
        {CAL.weekdays.map(d => (
          <div key={d} style={{ padding: '8px 14px', fontSize: 11, color: B.textLo, fontFamily: B.mono, letterSpacing: '0.1em' }}>{d}</div>
        ))}
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gridAutoRows: '1fr', minHeight: 0 }}>
        {CAL.cells.map((c, i) => (
          <div key={i} style={{
            borderRight: (i % 7 !== 6) ? `1px solid ${B.border}` : 'none',
            borderBottom: i < CAL.cells.length - 7 ? `1px solid ${B.border}` : 'none',
            padding: '8px 10px', minHeight: 0,
            display: 'flex', flexDirection: 'column', gap: 5,
            background: c.today ? `radial-gradient(circle at top right, ${B.brandFaint}, transparent 70%)` : 'transparent',
            opacity: c.out ? 0.3 : 1,
            position: 'relative',
          }}>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
              <span style={{
                fontSize: 13, fontFamily: B.mono,
                color: c.today ? B.brandHi : (c.out ? B.textLo : B.text),
                fontWeight: c.today ? 700 : 500,
                textShadow: c.today ? `0 0 12px ${B.brandFaint}` : 'none',
              }}>{c.d}</span>
              {c.today && <span style={{ width: 6, height: 6, borderRadius: 999, background: B.brand, boxShadow: B.brandGlow }}></span>}
            </div>
            {c.events && c.events.slice(0, 3).map((e, j) => {
              const ac = B.accent[e.accent];
              return (
                <div key={j} style={{
                  display: 'flex', alignItems: 'center', gap: 5,
                  padding: '3px 7px', borderRadius: 6,
                  background: ac.bg,
                  border: `1px solid ${ac.edge}`,
                  fontSize: 10.5, color: ac.fg, fontWeight: 500,
                  overflow: 'hidden', whiteSpace: 'nowrap', textOverflow: 'ellipsis',
                  textDecoration: e.todo ? 'line-through' : 'none',
                  textDecorationColor: 'rgba(138,180,255,0.4)',
                }}>
                  {e.time && <span style={{ fontFamily: B.mono, fontSize: 9.5, opacity: 0.85 }}>{e.time}</span>}
                  <span style={{ overflow: 'hidden', textOverflow: 'ellipsis' }}>{e.t}</span>
                </div>
              );
            })}
            {c.events && c.events.length > 3 && (
              <div style={{ fontSize: 10, color: B.textLo, fontFamily: B.mono, paddingLeft: 4 }}>+{c.events.length - 3}</div>
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

function AtmoCards() {
  const todo = DEMO_ASSETS.find(a => a.id === 'a1');
  const todoOverdue = DEMO_ASSETS.find(a => a.id === 'a7');
  const event = DEMO_ASSETS.find(a => a.id === 'a2');
  const idea = DEMO_ASSETS.find(a => a.id === 'a3');
  const expense = DEMO_ASSETS.find(a => a.id === 'a4');
  const contact = DEMO_ASSETS.find(a => a.id === 'a5');

  return (
    <div style={{ width: '100%', height: '100%', background: B.bgGradient, color: B.text, fontFamily: B.font, padding: 36, boxSizing: 'border-box', overflow: 'hidden', display: 'flex', flexDirection: 'column', gap: 22 }}>
      <div style={{ borderBottom: `1px solid ${B.border}`, paddingBottom: 14 }}>
        <div style={{ fontFamily: B.mono, fontSize: 10.5, letterSpacing: '0.2em', color: B.textLo, textTransform: 'uppercase' }}>04 / SKILLCARD SYSTEM</div>
        <div style={{ fontSize: 26, fontWeight: 700, color: B.textHi, marginTop: 8, letterSpacing: '-0.018em' }}>统一资产卡片 · 4 种 layout</div>
        <div style={{ fontSize: 12.5, color: B.textMid, marginTop: 4, lineHeight: 1.55 }}>每张卡是一团淡淡的"光"——accent.bg 整张 tint，hover 时辉光浮起。</div>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 22, flex: 1, minHeight: 0 }}>
        <BGroup label="horizontal" desc="主标题 + 副文本同行排布，适合 todo / event / expense / contact">
          <AtmoCard asset={todo} />
          <AtmoCard asset={event} />
          <AtmoCard asset={expense} />
          <AtmoCard asset={contact} />
        </BGroup>

        <BGroup label="stacked" desc="标题在上 + 多行内容在下，适合 idea / note">
          <AtmoCard asset={idea} />
          <AtmoCard asset={DEMO_ASSETS.find(a => a.id === 'a8')} />
        </BGroup>

        <BGroup label="inline" desc="一行紧凑布局，适合历史归档 / 搜索结果">
          <AtmoCard asset={todo} layout="inline" />
          <AtmoCard asset={event} layout="inline" />
          <AtmoCard asset={expense} layout="inline" />
          <AtmoCard asset={contact} layout="inline" />
        </BGroup>

        <BGroup label="compact + states" desc="日历格子内 chip + hover / selected / overdue">
          <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
            <AtmoCard asset={event} layout="compact" />
            <AtmoCard asset={{ ...event, payload: { title: 'demo 演练', start_at: '5月27日 15:00' }, accent: 'purple' }} layout="compact" />
            <AtmoCard asset={{ ...todo, payload: { title: '回 Linus 邮件' }, accent: 'blue' }} layout="compact" />
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: 'auto 1fr', gap: '4px 10px', alignItems: 'center', marginTop: 4 }}>
            <BStateLabel label="hover" />
            <AtmoCard asset={todo} hover />
            <BStateLabel label="selected" />
            <AtmoCard asset={event} selected />
            <BStateLabel label="overdue" />
            <AtmoCard asset={todoOverdue} />
          </div>
        </BGroup>
      </div>
    </div>
  );
}

function BGroup({ label, desc, children }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 10, minHeight: 0, overflow: 'hidden' }}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
        <span style={{ fontSize: 10.5, color: B.textLo, fontFamily: B.mono, letterSpacing: '0.16em', textTransform: 'uppercase' }}>{label}</span>
        <span style={{ flex: 1, height: 1, background: B.border }}></span>
      </div>
      <div style={{ fontSize: 11, color: B.textMid, lineHeight: 1.5 }}>{desc}</div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8, minHeight: 0 }}>{children}</div>
    </div>
  );
}

function BStateLabel({ label }) {
  return (
    <div style={{ fontFamily: B.mono, fontSize: 9.5, color: B.textLo, letterSpacing: '0.16em', textTransform: 'uppercase', alignSelf: 'center', minWidth: 60 }}>{label}</div>
  );
}

Object.assign(window, {
  AtmoFoundations, AtmoChat, AtmoTimeline, AtmoCalendar, AtmoCards,
});
