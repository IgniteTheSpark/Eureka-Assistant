// var-a-slate.jsx — Variation A · Slate
// Engineering-grade quiet tech. IBM Plex Sans + Plex Mono. Tight density.
// Deep slate background, low-saturation accents, sharp 4-6-10 radius.

const A = {
  name: 'A · Slate',
  subtitle: 'Engineering-grade quiet tech',
  // Surfaces
  bg: '#0d1117',
  surface: '#161b22',
  surface2: '#1c2128',
  surface3: '#22272e',
  border: '#2d333b',
  borderStrong: '#444c56',
  divider: 'rgba(205,217,229,0.06)',
  // Text
  textHi: '#e6edf3',
  text:   '#cdd9e5',
  textMid:'#9aa5b1',
  textLo: '#6e7681',
  textMuted: '#4d555f',
  // Brand
  brand: '#5b8def',
  brandHi: '#7aa2f7',
  brandFaint: 'rgba(91,141,239,0.10)',
  brandLine: 'rgba(91,141,239,0.30)',
  // Semantic accents — each: fg (text/icon), bg (tint background), edge (border/ring)
  accent: {
    blue:    { fg: '#7aa2f7', bg: 'rgba(122,162,247,0.09)', edge: 'rgba(122,162,247,0.22)', solid: '#5b8def' },
    amber:   { fg: '#e0af68', bg: 'rgba(224,175,104,0.09)', edge: 'rgba(224,175,104,0.22)', solid: '#d49a4d' },
    green:   { fg: '#9ece6a', bg: 'rgba(158,206,106,0.09)', edge: 'rgba(158,206,106,0.22)', solid: '#7fb950' },
    red:     { fg: '#f7768e', bg: 'rgba(247,118,142,0.09)', edge: 'rgba(247,118,142,0.22)', solid: '#e25c75' },
    purple:  { fg: '#bb9af7', bg: 'rgba(187,154,247,0.09)', edge: 'rgba(187,154,247,0.22)', solid: '#a07ce0' },
    gray:    { fg: '#9aa5b1', bg: 'rgba(154,165,177,0.08)', edge: 'rgba(154,165,177,0.20)', solid: '#7a8593' },
    neutral: { fg: '#cdd9e5', bg: 'rgba(205,217,229,0.04)', edge: 'rgba(205,217,229,0.14)', solid: '#9aa5b1' },
  },
  // Type
  font: '"IBM Plex Sans","Noto Sans SC", system-ui, sans-serif',
  mono: '"IBM Plex Mono", ui-monospace, monospace',
  // Geometry
  radius: { sm: 4, md: 6, lg: 10, xl: 14 },
  // Shadow (very subtle; dark mode mostly relies on borders)
  shadow: '0 1px 0 rgba(0,0,0,0.4), 0 0 0 1px rgba(0,0,0,0.3)',
};

// ──────────────────────────────────────────────────────────────────────
// SkillCard for Slate
// ──────────────────────────────────────────────────────────────────────

function SlateCard({ asset, hover, selected, layout }) {
  const ac = A.accent[asset.accent];
  const lay = layout || asset.layout;
  const baseBg = ac.bg;
  const baseBorder = hover || selected ? ac.edge : A.border;
  const radius = A.radius.md;

  const iconEl = (
    <div style={{
      width: 22, height: 22, borderRadius: 4, flex: '0 0 22px',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      background: 'rgba(0,0,0,0.20)', color: ac.fg,
      fontFamily: A.mono, fontSize: 12, fontWeight: 600,
      border: `1px solid ${ac.edge}`,
    }}>{asset.icon}</div>
  );

  if (lay === 'inline') {
    return (
      <div style={{
        display: 'flex', alignItems: 'center', gap: 10,
        padding: '8px 10px', borderRadius: radius,
        background: baseBg, border: `1px solid ${baseBorder}`,
        fontSize: 12.5, color: A.text,
      }}>
        <span style={{ color: ac.fg, fontFamily: A.mono, fontSize: 11 }}>{asset.icon}</span>
        <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
          {asset.payload.content || asset.payload.title || asset.payload.name || asset.payload.description}
        </span>
        <span style={{ color: A.textLo, fontFamily: A.mono, fontSize: 10.5 }}>{asset.time}</span>
      </div>
    );
  }

  if (lay === 'compact') {
    return (
      <div style={{
        display: 'flex', alignItems: 'center', gap: 5,
        padding: '3px 5px', borderRadius: 3,
        background: ac.bg, color: ac.fg,
        fontSize: 10.5, fontWeight: 500,
        borderLeft: `2px solid ${ac.solid}`,
      }}>
        <span style={{ fontFamily: A.mono, fontSize: 9 }}>{asset.payload.start_at ? asset.payload.start_at.split(' ')[1] || '' : ''}</span>
        <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{asset.payload.title || asset.payload.content}</span>
      </div>
    );
  }

  if (lay === 'stacked') {
    const p = asset.payload;
    return (
      <div style={{
        display: 'flex', flexDirection: 'column', gap: 8,
        padding: 14, borderRadius: radius,
        background: baseBg, border: `1px solid ${baseBorder}`,
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          {iconEl}
          <div style={{ fontSize: 13, fontWeight: 600, color: A.textHi, letterSpacing: '0.005em' }}>{p.title}</div>
          <div style={{ marginLeft: 'auto', fontSize: 10.5, color: A.textLo, fontFamily: A.mono }}>{asset.time}</div>
        </div>
        <div style={{ fontSize: 12.5, color: A.text, lineHeight: 1.55 }}>{p.content}</div>
      </div>
    );
  }

  // horizontal (default)
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
      display: 'flex', alignItems: 'flex-start', gap: 12,
      padding: '12px 14px', borderRadius: radius,
      background: baseBg, border: `1px solid ${baseBorder}`,
    }}>
      {iconEl}
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{
          fontSize: 13, fontWeight: 500, color: asset.payload.status === 'overdue' ? ac.fg : A.textHi,
          letterSpacing: '0.005em', lineHeight: 1.4,
        }}>{primary}</div>
        {(secondary || meta.length) && (
          <div style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: 8, marginTop: 4 }}>
            {secondary && (
              <span style={{ fontSize: 11.5, color: A.textMid, fontFamily: asset.skill === 'event' || asset.skill === 'todo' ? A.mono : 'inherit' }}>{secondary}</span>
            )}
            {meta.map((m, i) => (
              <span key={i} style={{ fontSize: 11, color: A.textLo, fontFamily: A.mono }}>· {m}</span>
            ))}
          </div>
        )}
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 4, opacity: hover ? 1 : 0.5 }}>
        {asset.skill === 'todo' && (
          <button style={iconBtnA}>✓</button>
        )}
        <button style={iconBtnA}>⋯</button>
      </div>
    </div>
  );
}

const iconBtnA = {
  width: 22, height: 22, padding: 0, border: 'none', background: 'transparent',
  color: A.textLo, fontSize: 12, cursor: 'pointer', borderRadius: 3,
  display: 'flex', alignItems: 'center', justifyContent: 'center',
  fontFamily: A.mono,
};

// ──────────────────────────────────────────────────────────────────────
// 00 · Foundations
// ──────────────────────────────────────────────────────────────────────

function SlateFoundations() {
  return (
    <div style={{
      width: '100%', height: '100%', background: A.bg, color: A.text,
      fontFamily: A.font, padding: 40, boxSizing: 'border-box',
      display: 'flex', flexDirection: 'column', gap: 32,
      overflow: 'hidden',
    }}>
      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between', borderBottom: `1px solid ${A.border}`, paddingBottom: 24 }}>
        <div>
          <div style={{ fontFamily: A.mono, fontSize: 10.5, letterSpacing: '0.22em', color: A.textLo, textTransform: 'uppercase', marginBottom: 10 }}>EUREKA / VARIATION A</div>
          <div style={{ fontSize: 44, fontWeight: 600, letterSpacing: '-0.02em', color: A.textHi, lineHeight: 1 }}>Slate</div>
          <div style={{ fontSize: 14, color: A.textMid, marginTop: 8, maxWidth: 520 }}>克制到接近工程图。深色石板、几何无衬线、规整网格。Linear / GitHub 的精神后裔——给"在认真工作"的人。</div>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 6, fontFamily: A.mono, fontSize: 10.5, color: A.textLo, textAlign: 'right' }}>
          <div>IBM PLEX SANS / PLEX MONO</div>
          <div>4 / 6 / 10 / 14 RADIUS</div>
          <div>DENSITY · TIGHT</div>
        </div>
      </div>

      {/* Body 3 cols */}
      <div style={{ display: 'grid', gridTemplateColumns: '1.1fr 1.1fr 1fr', gap: 36, flex: 1, minHeight: 0 }}>
        {/* Col 1 — Neutrals */}
        <EuArtboardSection label="Neutrals" num="01" fontMono={A.mono}>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
            <EuSwatch color={A.bg}      label="bg"           sub="canvas"     mono="#0D1117" txt={A.text}   border={A.border} fontMono={A.mono} />
            <EuSwatch color={A.surface} label="surface"      sub="card"       mono="#161B22" txt={A.text}   border={A.border} fontMono={A.mono} />
            <EuSwatch color={A.surface2} label="surface.raised" sub="elev"    mono="#1C2128" txt={A.text}   border={A.border} fontMono={A.mono} />
            <EuSwatch color={A.surface3} label="surface.hover"  sub="hover"   mono="#22272E" txt={A.text}   border={A.border} fontMono={A.mono} />
            <EuSwatch color={A.border}  label="border"       sub="default"    mono="#2D333B" txt={A.text}   border="transparent" fontMono={A.mono} />
            <EuSwatch color={A.textHi}  label="text.hi"      sub="title"      mono="#E6EDF3" txt="#111"     border="transparent" fontMono={A.mono} />
          </div>
          <div style={{ marginTop: 10, display: 'flex', flexDirection: 'column', gap: 8 }}>
            <TextRow label="text.hi"  hex="#E6EDF3" color={A.textHi} mono={A.mono} sample="标题 · The quiet OS" />
            <TextRow label="text"     hex="#CDD9E5" color={A.text}   mono={A.mono} sample="正文 · 关于硬件断网的策略" />
            <TextRow label="text.mid" hex="#9AA5B1" color={A.textMid} mono={A.mono} sample="副文本 · 上午 10:00 · 60 min" />
            <TextRow label="text.lo"  hex="#6E7681" color={A.textLo}  mono={A.mono} sample="辅助 · created 14:32" />
            <TextRow label="text.muted" hex="#4D555F" color={A.textMuted} mono={A.mono} sample="占位 · placeholder" />
          </div>
        </EuArtboardSection>

        {/* Col 2 — Brand + Accents */}
        <EuArtboardSection label="Brand + Accents" num="02" fontMono={A.mono}>
          <div style={{ display: 'flex', gap: 10, alignItems: 'stretch' }}>
            <div style={{
              flex: '0 0 86px', height: 86, borderRadius: 8,
              background: `linear-gradient(135deg, ${A.brand} 0%, #2a4d8f 100%)`,
              display: 'flex', alignItems: 'flex-end', padding: 10,
              color: '#fff', fontFamily: A.mono, fontSize: 10,
            }}>#5B8DEF</div>
            <div style={{ flex: 1, padding: 12, borderRadius: 6, background: A.brandFaint, border: `1px solid ${A.brandLine}` }}>
              <div style={{ fontSize: 11.5, color: A.brandHi, fontWeight: 600, letterSpacing: '0.02em', fontFamily: A.mono, marginBottom: 4 }}>BRAND</div>
              <div style={{ fontSize: 12.5, color: A.text, lineHeight: 1.5 }}>深海蓝。仅用于品牌标识、user 气泡和首要操作。在 chrome 中不滥用。</div>
            </div>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 6, marginTop: 6 }}>
            {ACCENT_ROLES.map(r => {
              const ac = A.accent[r.key];
              return (
                <div key={r.key} style={{
                  display: 'flex', alignItems: 'center', gap: 8,
                  padding: '8px 10px', borderRadius: 5,
                  background: ac.bg, border: `1px solid ${ac.edge}`,
                }}>
                  <div style={{ width: 18, height: 18, borderRadius: 3, background: 'rgba(0,0,0,0.20)', color: ac.fg, fontFamily: A.mono, fontSize: 10, display: 'flex', alignItems: 'center', justifyContent: 'center', border: `1px solid ${ac.edge}` }}>{r.glyph}</div>
                  <div style={{ flex: 1 }}>
                    <div style={{ fontSize: 11.5, color: ac.fg, fontWeight: 600, fontFamily: A.mono, letterSpacing: '0.02em' }}>{r.key.toUpperCase()}</div>
                    <div style={{ fontSize: 10, color: A.textMid }}>{r.role}</div>
                  </div>
                </div>
              );
            })}
          </div>
        </EuArtboardSection>

        {/* Col 3 — Type + Geometry */}
        <EuArtboardSection label="Type · Space · Motion" num="03" fontMono={A.mono}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 6, borderLeft: `2px solid ${A.border}`, paddingLeft: 14 }}>
            <div style={{ fontSize: 28, fontWeight: 600, color: A.textHi, lineHeight: 1.1, letterSpacing: '-0.015em' }}>Aa 阿</div>
            <div style={{ fontSize: 10.5, color: A.textLo, fontFamily: A.mono }}>IBM PLEX SANS · NOTO SANS SC</div>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 6, borderLeft: `2px solid ${A.border}`, paddingLeft: 14 }}>
            <div style={{ fontSize: 22, fontWeight: 500, color: A.textHi, lineHeight: 1.1, fontFamily: A.mono }}>0123 ¥68</div>
            <div style={{ fontSize: 10.5, color: A.textLo, fontFamily: A.mono }}>IBM PLEX MONO · 数字 / 时间 / 标签</div>
          </div>

          <div style={{ marginTop: 8, display: 'flex', flexDirection: 'column', gap: 4, fontSize: 11, color: A.textMid, fontFamily: A.mono }}>
            <div style={{ display: 'flex', justifyContent: 'space-between' }}><span>radius.sm</span><span style={{ color: A.textLo }}>4px</span></div>
            <div style={{ display: 'flex', justifyContent: 'space-between' }}><span>radius.md</span><span style={{ color: A.textLo }}>6px</span></div>
            <div style={{ display: 'flex', justifyContent: 'space-between' }}><span>radius.lg</span><span style={{ color: A.textLo }}>10px</span></div>
            <div style={{ display: 'flex', justifyContent: 'space-between' }}><span>radius.xl</span><span style={{ color: A.textLo }}>14px</span></div>
          </div>

          <div style={{ marginTop: 4, display: 'flex', alignItems: 'flex-end', gap: 4 }}>
            {[4, 8, 12, 16, 24, 32, 48].map(n => (
              <div key={n} style={{ flexBasis: 0, flexGrow: n }}>
                <div style={{ height: 8, background: A.surface2, border: `1px solid ${A.border}`, borderRadius: 2 }}></div>
                <div style={{ fontSize: 9, color: A.textLo, fontFamily: A.mono, marginTop: 4, textAlign: 'center' }}>{n}</div>
              </div>
            ))}
          </div>

          <div style={{ marginTop: 8, padding: 10, background: A.surface, borderRadius: 6, border: `1px solid ${A.border}` }}>
            <div style={{ fontSize: 10.5, color: A.textLo, fontFamily: A.mono, letterSpacing: '0.1em', marginBottom: 6 }}>MOTION</div>
            <div style={{ fontSize: 11.5, color: A.text, lineHeight: 1.55 }}>
              <div style={{ fontFamily: A.mono, fontSize: 10.5, color: A.textMid }}>fast 150 · normal 250 · slow 400</div>
              <div style={{ marginTop: 4 }}>Token 出现间隔：32ms / 字。曲线 cubic-bezier(.2,.7,.3,1)</div>
            </div>
          </div>
        </EuArtboardSection>
      </div>
    </div>
  );
}

function TextRow({ label, hex, color, sample, mono }) {
  return (
    <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
      <div style={{ width: 70, fontSize: 10.5, color: A.textLo, fontFamily: mono }}>{label}</div>
      <div style={{ flex: 1, fontSize: 14, color, lineHeight: 1.4 }}>{sample}</div>
      <div style={{ fontSize: 10, color: A.textLo, fontFamily: mono }}>{hex}</div>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// 01 · AI Chat (desktop)
// ──────────────────────────────────────────────────────────────────────

function SlateChat() {
  return (
    <div style={{
      width: '100%', height: '100%', background: A.bg, color: A.text,
      fontFamily: A.font, display: 'grid', gridTemplateColumns: '220px 1fr',
      overflow: 'hidden',
    }}>
      <SlateSidebar active="chat" />
      <div style={{ display: 'grid', gridTemplateRows: '48px 1fr 84px', minHeight: 0 }}>
        {/* Top bar */}
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 20px', borderBottom: `1px solid ${A.border}` }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <span style={{ fontSize: 13, color: A.textHi, fontWeight: 500 }}>统一助手</span>
            <span style={{ fontSize: 10.5, color: A.textLo, fontFamily: A.mono }}>· session 7f3a</span>
          </div>
          <div style={{ display: 'flex', gap: 6 }}>
            <button style={{ ...iconBtnA, width: 26, height: 26, color: A.textMid }}>⌕</button>
            <button style={{ ...iconBtnA, width: 26, height: 26, color: A.textMid }}>⋯</button>
          </div>
        </div>

        {/* Messages */}
        <div className="eu-noscroll" style={{ padding: '24px 32px', overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 18 }}>
          {DEMO_CHAT.map((m, i) => <SlateMessage key={i} msg={m} />)}
        </div>

        {/* Composer */}
        <div style={{ borderTop: `1px solid ${A.border}`, padding: '16px 32px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '10px 14px', borderRadius: 8, background: A.surface, border: `1px solid ${A.border}` }}>
            <span style={{ color: A.textLo, fontFamily: A.mono, fontSize: 12 }}>›</span>
            <span style={{ flex: 1, color: A.textMuted, fontSize: 13 }}>问点什么，或者记录想法…</span>
            <button style={{ width: 28, height: 28, borderRadius: 5, background: 'transparent', border: `1px solid ${A.border}`, color: A.textMid, fontSize: 12, cursor: 'pointer' }}>🎙</button>
            <button style={{ width: 28, height: 28, borderRadius: 5, background: A.brand, border: 'none', color: '#fff', fontSize: 12, cursor: 'pointer', fontFamily: A.mono }}>↵</button>
          </div>
        </div>
      </div>
    </div>
  );
}

function SlateSidebar({ active }) {
  const items = [
    { key: 'chat', label: '对话', glyph: '◊' },
    { key: 'timeline', label: '时间流', glyph: '≡' },
    { key: 'calendar', label: '日历', glyph: '▦' },
    { key: 'library', label: '资产库', glyph: '⌗' },
  ];
  return (
    <div style={{
      background: 'rgba(0,0,0,0.20)', borderRight: `1px solid ${A.border}`,
      padding: '20px 14px', display: 'flex', flexDirection: 'column', gap: 4,
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '4px 8px 16px' }}>
        <div style={{ width: 22, height: 22, borderRadius: 5, background: `linear-gradient(135deg, ${A.brand}, #2a4d8f)`, display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff', fontFamily: A.mono, fontWeight: 700, fontSize: 11 }}>E</div>
        <div style={{ fontSize: 13, color: A.textHi, fontWeight: 600, letterSpacing: '-0.005em' }}>Eureka</div>
      </div>
      {items.map(it => {
        const isActive = it.key === active;
        return (
          <div key={it.key} style={{
            display: 'flex', alignItems: 'center', gap: 10, padding: '6px 10px', borderRadius: 5,
            background: isActive ? A.brandFaint : 'transparent',
            color: isActive ? A.brandHi : A.textMid,
            fontSize: 12.5, cursor: 'pointer',
            border: `1px solid ${isActive ? A.brandLine : 'transparent'}`,
          }}>
            <span style={{ fontFamily: A.mono, fontSize: 12, opacity: 0.8 }}>{it.glyph}</span>
            <span>{it.label}</span>
          </div>
        );
      })}
      <div style={{ flex: 1 }}></div>
      <div style={{ padding: '10px 8px', borderTop: `1px solid ${A.border}`, marginTop: 8 }}>
        <div style={{ fontSize: 10, color: A.textLo, fontFamily: A.mono, letterSpacing: '0.12em', marginBottom: 6 }}>MODE</div>
        <div style={{ display: 'flex', background: A.surface, borderRadius: 4, padding: 2, border: `1px solid ${A.border}` }}>
          <button style={{ flex: 1, padding: '4px 6px', fontSize: 10.5, background: A.brandFaint, color: A.brandHi, border: 'none', borderRadius: 3, fontFamily: A.mono, cursor: 'pointer' }}>资产</button>
          <button style={{ flex: 1, padding: '4px 6px', fontSize: 10.5, background: 'transparent', color: A.textLo, border: 'none', fontFamily: A.mono, cursor: 'pointer' }}>日历</button>
        </div>
      </div>
    </div>
  );
}

function SlateMessage({ msg }) {
  if (msg.role === 'user') {
    return (
      <div style={{ display: 'flex', justifyContent: 'flex-end' }}>
        <div style={{
          maxWidth: '70%', padding: '8px 14px', borderRadius: 12, borderTopRightRadius: 4,
          background: A.brand, color: '#fff',
          fontSize: 13, lineHeight: 1.5,
        }}>{msg.text}</div>
      </div>
    );
  }
  // agent
  const referenced = msg.card ? DEMO_ASSETS.find(a => a.id === msg.card.ref) : null;
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 10, maxWidth: '85%' }}>
      {msg.toolCall && (
        <div style={{
          alignSelf: 'flex-start',
          display: 'inline-flex', alignItems: 'center', gap: 6, padding: '3px 8px',
          fontSize: 10.5, fontFamily: A.mono, color: A.textLo,
          background: A.surface, border: `1px solid ${A.border}`, borderRadius: 999,
        }}>
          <span style={{ width: 4, height: 4, borderRadius: 2, background: A.accent.green.fg }}></span>
          tool · {msg.toolCall.name}({msg.toolCall.skill})
        </div>
      )}
      <div style={{ fontSize: 13, lineHeight: 1.6, color: A.text }}>
        {msg.text}
        {msg.streaming && <span style={{ display: 'inline-block', width: 6, height: 13, background: A.brandHi, marginLeft: 2, verticalAlign: 'middle', animation: 'eu-blink 1s infinite' }}></span>}
      </div>
      {referenced && (
        <div style={{ maxWidth: 360 }}>
          <SlateCard asset={referenced} />
        </div>
      )}
      {msg.precipitate && (
        <button style={{
          alignSelf: 'flex-start', marginTop: 2,
          display: 'inline-flex', alignItems: 'center', gap: 6,
          padding: '5px 10px', borderRadius: 5,
          background: 'transparent', color: A.textMid,
          border: `1px dashed ${A.borderStrong}`,
          fontSize: 11, cursor: 'pointer',
        }}>
          <span style={{ fontFamily: A.mono, color: A.accent.amber.fg }}>+</span>
          沉淀为想法
        </button>
      )}
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// 02 · Timeline
// ──────────────────────────────────────────────────────────────────────

function SlateTimeline() {
  return (
    <div style={{ width: '100%', height: '100%', background: A.bg, color: A.text, fontFamily: A.font, display: 'grid', gridTemplateRows: '52px auto 1fr', overflow: 'hidden' }}>
      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 24px', borderBottom: `1px solid ${A.border}` }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <span style={{ fontSize: 14, color: A.textHi, fontWeight: 600 }}>时间流</span>
          <span style={{ fontSize: 10.5, color: A.textLo, fontFamily: A.mono }}>52 items · 7d</span>
        </div>
        <button style={{ padding: '5px 10px', borderRadius: 5, background: A.surface, border: `1px solid ${A.border}`, color: A.textMid, fontSize: 11, fontFamily: A.mono, cursor: 'pointer' }}>📅 跳转</button>
      </div>
      {/* Filter tabs */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 4, padding: '12px 24px', borderBottom: `1px solid ${A.border}` }}>
        {[
          { k: '全部', n: 52, active: true },
          { k: '待办', n: 14 }, { k: '事件', n: 8 }, { k: '想法', n: 22 }, { k: '记账', n: 6 }, { k: '名片', n: 2 },
        ].map((t, i) => (
          <button key={i} style={{
            padding: '4px 10px', borderRadius: 4,
            background: t.active ? A.brandFaint : 'transparent',
            color: t.active ? A.brandHi : A.textMid,
            border: `1px solid ${t.active ? A.brandLine : 'transparent'}`,
            fontSize: 11.5, cursor: 'pointer',
            display: 'inline-flex', alignItems: 'center', gap: 5,
          }}>
            {t.k}
            <span style={{ fontFamily: A.mono, fontSize: 10, opacity: 0.7 }}>{t.n}</span>
          </button>
        ))}
      </div>
      {/* Stream */}
      <div className="eu-noscroll" style={{ overflowY: 'auto', padding: '4px 24px 24px' }}>
        {TIMELINE.map(group => (
          <div key={group.label}>
            <div style={{
              position: 'sticky', top: 0, background: A.bg, padding: '14px 0 8px', zIndex: 1,
              display: 'flex', alignItems: 'baseline', gap: 10,
            }}>
              <span style={{ fontSize: 13, color: A.textHi, fontWeight: 600 }}>{group.label}</span>
              <span style={{ fontSize: 11, color: A.textLo, fontFamily: A.mono }}>{group.sub}</span>
              <span style={{ flex: 1, height: 1, background: A.border }}></span>
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
              {group.items.map(id => {
                const a = DEMO_ASSETS.find(x => x.id === id);
                if (!a) return null;
                return <SlateCard key={id} asset={a} />;
              })}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// 03 · Calendar (month)
// ──────────────────────────────────────────────────────────────────────

function SlateCalendar() {
  return (
    <div style={{ width: '100%', height: '100%', background: A.bg, color: A.text, fontFamily: A.font, display: 'grid', gridTemplateRows: '52px 32px 1fr', overflow: 'hidden' }}>
      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 24px', borderBottom: `1px solid ${A.border}` }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
          <span style={{ fontSize: 14, color: A.textHi, fontWeight: 600 }}>{CAL.monthLabel}</span>
          <div style={{ display: 'flex', gap: 2 }}>
            <button style={{ ...iconBtnA, width: 24, height: 24 }}>‹</button>
            <button style={{ ...iconBtnA, width: 24, height: 24 }}>›</button>
            <button style={{ marginLeft: 6, padding: '3px 9px', borderRadius: 4, background: A.surface, border: `1px solid ${A.border}`, color: A.textMid, fontSize: 11, fontFamily: A.mono, cursor: 'pointer' }}>今天</button>
          </div>
        </div>
        <div style={{ display: 'flex', background: A.surface, borderRadius: 5, padding: 2, border: `1px solid ${A.border}`, gap: 0 }}>
          {['月', '周', '日'].map((v, i) => (
            <button key={i} style={{
              padding: '3px 12px', borderRadius: 3, fontSize: 11, cursor: 'pointer',
              background: i === 0 ? A.surface2 : 'transparent',
              color: i === 0 ? A.textHi : A.textLo,
              border: 'none', fontFamily: A.mono,
            }}>{v}</button>
          ))}
        </div>
      </div>
      {/* Weekday strip */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', borderBottom: `1px solid ${A.border}` }}>
        {CAL.weekdays.map(d => (
          <div key={d} style={{ padding: '8px 12px', fontSize: 10.5, color: A.textLo, fontFamily: A.mono, letterSpacing: '0.1em' }}>{d}</div>
        ))}
      </div>
      {/* Grid */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gridAutoRows: '1fr', minHeight: 0 }}>
        {CAL.cells.map((c, i) => (
          <div key={i} style={{
            borderRight: (i % 7 !== 6) ? `1px solid ${A.border}` : 'none',
            borderBottom: i < CAL.cells.length - 7 ? `1px solid ${A.border}` : 'none',
            padding: '6px 8px', minHeight: 0,
            display: 'flex', flexDirection: 'column', gap: 4,
            background: c.today ? A.brandFaint : 'transparent',
            opacity: c.out ? 0.35 : 1,
          }}>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
              <span style={{
                fontSize: 11.5, fontFamily: A.mono,
                color: c.today ? A.brandHi : (c.out ? A.textLo : A.text),
                fontWeight: c.today ? 700 : 500,
              }}>{String(c.d).padStart(2, '0')}</span>
              {c.today && <span style={{ fontSize: 9, color: A.brandHi, fontFamily: A.mono, letterSpacing: '0.1em' }}>TODAY</span>}
            </div>
            {c.events && c.events.slice(0, 3).map((e, j) => {
              const ac = A.accent[e.accent];
              return (
                <div key={j} style={{
                  display: 'flex', alignItems: 'center', gap: 4,
                  padding: '2px 5px', borderRadius: 2,
                  background: ac.bg,
                  borderLeft: `2px solid ${ac.solid}`,
                  fontSize: 10, color: ac.fg, fontWeight: 500,
                  overflow: 'hidden', whiteSpace: 'nowrap', textOverflow: 'ellipsis',
                  textDecoration: e.todo ? 'line-through' : 'none',
                  textDecorationColor: 'rgba(122,162,247,0.3)',
                }}>
                  {e.time && <span style={{ fontFamily: A.mono, fontSize: 9, opacity: 0.8 }}>{e.time}</span>}
                  <span style={{ overflow: 'hidden', textOverflow: 'ellipsis' }}>{e.t}</span>
                </div>
              );
            })}
            {c.events && c.events.length > 3 && (
              <div style={{ fontSize: 10, color: A.textLo, fontFamily: A.mono, paddingLeft: 5 }}>+{c.events.length - 3} more</div>
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

function SlateCards() {
  const todo = DEMO_ASSETS.find(a => a.id === 'a1');
  const todoOverdue = DEMO_ASSETS.find(a => a.id === 'a7');
  const event = DEMO_ASSETS.find(a => a.id === 'a2');
  const idea = DEMO_ASSETS.find(a => a.id === 'a3');
  const expense = DEMO_ASSETS.find(a => a.id === 'a4');
  const contact = DEMO_ASSETS.find(a => a.id === 'a5');

  return (
    <div style={{ width: '100%', height: '100%', background: A.bg, color: A.text, fontFamily: A.font, padding: 32, boxSizing: 'border-box', overflow: 'hidden', display: 'flex', flexDirection: 'column', gap: 22 }}>
      <div style={{ borderBottom: `1px solid ${A.border}`, paddingBottom: 14 }}>
        <div style={{ fontFamily: A.mono, fontSize: 10.5, letterSpacing: '0.2em', color: A.textLo, textTransform: 'uppercase' }}>04 / SKILLCARD SYSTEM</div>
        <div style={{ fontSize: 22, fontWeight: 600, color: A.textHi, marginTop: 6, letterSpacing: '-0.01em' }}>统一资产卡片 · 4 种 layout</div>
        <div style={{ fontSize: 11.5, color: A.textMid, marginTop: 4 }}>所有 skill 走同一个渲染器，由 <span style={{ fontFamily: A.mono, color: A.brandHi }}>render_spec</span> 决定。Slate 用 accent.bg 做整张卡的淡色 tint。</div>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 18, flex: 1, minHeight: 0 }}>
        <CardGroup label="horizontal" mono={A.mono} desc="主标题 + 副文本同行排布，适合 todo / event / expense / contact">
          <SlateCard asset={todo} />
          <SlateCard asset={event} />
          <SlateCard asset={expense} />
          <SlateCard asset={contact} />
        </CardGroup>

        <CardGroup label="stacked" mono={A.mono} desc="标题在上 + 多行内容在下，适合 idea / note">
          <SlateCard asset={idea} />
          <SlateCard asset={DEMO_ASSETS.find(a => a.id === 'a8')} />
        </CardGroup>

        <CardGroup label="inline" mono={A.mono} desc="一行极紧凑，适合时间流密集场景 / 历史归档">
          <SlateCard asset={todo} layout="inline" />
          <SlateCard asset={event} layout="inline" />
          <SlateCard asset={expense} layout="inline" />
          <SlateCard asset={contact} layout="inline" />
        </CardGroup>

        <CardGroup label="compact + states" mono={A.mono} desc="日历格子内的 chip，以及 hover / selected / overdue">
          <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
            <SlateCard asset={event} layout="compact" />
            <SlateCard asset={{ ...event, payload: { title: 'demo 演练', start_at: '5月27日 15:00' }, accent: 'purple' }} layout="compact" />
            <SlateCard asset={{ ...todo, payload: { title: '回 Linus 邮件', content: '回 Linus 邮件' }, accent: 'blue' }} layout="compact" />
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginTop: 8 }}>
            <StateLabel label="hover" mono={A.mono} />
            <SlateCard asset={todo} hover />
            <StateLabel label="selected" mono={A.mono} />
            <SlateCard asset={event} selected />
            <StateLabel label="overdue" mono={A.mono} />
            <SlateCard asset={todoOverdue} />
          </div>
        </CardGroup>
      </div>
    </div>
  );
}

function CardGroup({ label, desc, mono, children }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 10, minHeight: 0 }}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
        <span style={{ fontSize: 10.5, color: A.textLo, fontFamily: mono, letterSpacing: '0.15em', textTransform: 'uppercase' }}>{label}</span>
        <span style={{ flex: 1, height: 1, background: A.border }}></span>
      </div>
      <div style={{ fontSize: 10.5, color: A.textMid, lineHeight: 1.5 }}>{desc}</div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8, overflow: 'hidden' }}>{children}</div>
    </div>
  );
}

function StateLabel({ label, mono }) {
  return (
    <div style={{ fontFamily: mono, fontSize: 9.5, color: A.textLo, letterSpacing: '0.16em', textTransform: 'uppercase' }}>{label}</div>
  );
}

// Inject animation keyframes once
if (typeof document !== 'undefined' && !document.getElementById('eu-anim')) {
  const s = document.createElement('style');
  s.id = 'eu-anim';
  s.textContent = '@keyframes eu-blink { 0%,50% { opacity: 1 } 51%,100% { opacity: 0 } } @keyframes eu-pulse { 0%,100% { transform: scale(1); opacity: 0.6 } 50% { transform: scale(1.4); opacity: 0 } }';
  document.head.appendChild(s);
}

Object.assign(window, {
  SlateFoundations, SlateChat, SlateTimeline, SlateCalendar, SlateCards,
});
