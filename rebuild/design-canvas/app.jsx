// app.jsx — Eureka design canvas. B · Atmosphere selected.

const { DesignCanvas, DCSection, DCArtboard, DCPostIt } = window;

function App() {
  return (
    <DesignCanvas>
      {/* ────────────────────────────────────────────────────────────── */}
      {/* INTRO */}
      {/* ────────────────────────────────────────────────────────────── */}
      <DCSection
        id="intro"
        title="Eureka · B · Atmosphere"
        subtitle="选定方向：Quiet tech with depth and pulse. 暗色优先 / 冷色调 / 微辉光 / Manrope + JetBrains Mono。"
      >
        <DCArtboard id="brief" label="Brief / Direction" width={1100} height={620}>
          <BriefCard />
        </DCArtboard>
        <DCPostIt x={1180} y={30}>
          A · Slate 和 C · Lab 已存档（tokens 仍在 tokens/ 目录）。下面是 B 的完整设计语言。
        </DCPostIt>
      </DCSection>

      {/* ────────────────────────────────────────────────────────────── */}
      {/* B · ATMOSPHERE — Foundations + Core surfaces */}
      {/* ────────────────────────────────────────────────────────────── */}
      <DCSection
        id="atmosphere"
        title="Foundations & Core Surfaces"
        subtitle="Tokens 总览 + AI 对话 + SkillCard 系统。时间流已并入 Calendar Schedule。"
      >
        <DCArtboard id="b-found"    label="00 · Foundations"     width={1280} height={780}><AtmoFoundations /></DCArtboard>
        <DCArtboard id="b-chat"     label="01 · AI 对话"          width={1080} height={720}><AtmoChat /></DCArtboard>
        <DCArtboard id="b-cards"    label="02 · SkillCard System" width={1000} height={880}><AtmoCards /></DCArtboard>
      </DCSection>

      {/* ────────────────────────────────────────────────────────────── */}
      {/* CALENDAR — Timepage-inspired */}
      {/* ────────────────────────────────────────────────────────────── */}
      <DCSection
        id="calendar"
        title="Calendar · Timepage-inspired"
        subtitle="移动端 5 个状态 · 颜色 = 信号 · 滑动 = 视角切换。SCHEDULE → MONTH → YEAR / DAY DETAIL / EVENT EDITOR。"
      >
        <DCArtboard id="cal-flow"     label="00 · Navigation Flow" width={1200} height={820}><CalFlow /></DCArtboard>
        <DCArtboard id="cal-schedule" label="01 · Schedule (default)" width={392} height={844}><CalSchedule /></DCArtboard>
        <DCArtboard id="cal-month"    label="02 · Month + selected day" width={392} height={844}><CalMonth /></DCArtboard>
        <DCArtboard id="cal-year"     label="03 · Year overview" width={392} height={844}><CalYear /></DCArtboard>
        <DCArtboard id="cal-day"      label="04 · Day detail" width={392} height={844}><CalDay /></DCArtboard>
        <DCArtboard id="cal-asset"    label="05 · Asset detail (source = session turn)" width={392} height={844}><CalAssetDetail /></DCArtboard>
        <DCArtboard id="cal-library"  label="06 · Asset library (hub)" width={392} height={844}><CalAssetLibrary /></DCArtboard>
        <DCArtboard id="cal-ideas"    label="07 · 想法 list (type entry)" width={392} height={844}><CalAssetIdeas /></DCArtboard>
        <DCArtboard id="cal-files"    label="08 · 文件 list (sources view)" width={392} height={844}><CalAssetFiles /></DCArtboard>
        <DCArtboard id="cal-editor"   label="09 · Event editor" width={392} height={844}><CalEditor /></DCArtboard>

        <DCPostIt x={1230} y={30}>
          Timepage 的核心：颜色密度就是信息密度。这里把 accent 系统升级成「日色」—— event 紫 / todo 蓝 / idea 琥珀 / 混合渐变。
        </DCPostIt>
      </DCSection>

      {/* ────────────────────────────────────────────────────────────── */}
      {/* DELIVERABLES */}
      {/* ────────────────────────────────────────────────────────────── */}
      <DCSection
        id="deliverables"
        title="Deliverables"
        subtitle="选定 B 后产出的文件清单。"
      >
        <DCArtboard id="files" label="Files" width={760} height={460}>
          <DeliverablesCard />
        </DCArtboard>
      </DCSection>
    </DesignCanvas>
  );
}

// ────────────────────────────────────────────────────────────────────────
// Brief intro card — B selected
// ────────────────────────────────────────────────────────────────────────

function BriefCard() {
  return (
    <div style={{
      width: '100%', height: '100%', boxSizing: 'border-box',
      padding: 56, color: '#f4f7fb',
      background: 'radial-gradient(900px 600px at 20% -10%, rgba(111,158,255,0.18), transparent 60%), radial-gradient(700px 500px at 110% 110%, rgba(156,128,240,0.12), transparent 60%), #0b1220',
      fontFamily: '"Manrope","Noto Sans SC", system-ui, sans-serif',
      display: 'flex', flexDirection: 'column', gap: 28, position: 'relative', overflow: 'hidden',
    }}>
      <div style={{ position: 'absolute', top: 40, right: 40, width: 200, height: 200, borderRadius: 999, background: 'radial-gradient(circle, rgba(111,158,255,0.20), transparent 70%)', pointerEvents: 'none' }}></div>

      <div style={{ display: 'flex', alignItems: 'center', gap: 14, position: 'relative' }}>
        <span style={{ width: 12, height: 12, borderRadius: 999, background: '#6f9eff', boxShadow: '0 0 16px rgba(111,158,255,0.55)' }}></span>
        <span style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 11, letterSpacing: '0.24em', textTransform: 'uppercase', color: '#a4c2ff' }}>EUREKA · B · ATMOSPHERE — SELECTED</span>
      </div>

      <div style={{ fontSize: 52, fontWeight: 700, letterSpacing: '-0.035em', color: '#f4f7fb', lineHeight: 1.05, maxWidth: 900, position: 'relative' }}>
        一个私人 AI 在为我工作。<br />
        <span style={{ color: '#9aa6b8' }}>沉静、有秩序、值得信任。</span>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 20, marginTop: 12, position: 'relative' }}>
        {[
          { l: 'TONE', v: 'Quiet tech with depth' },
          { l: 'COLOR', v: '深海蓝 #6F9EFF + 微辉光' },
          { l: 'TYPE', v: 'Manrope · JetBrains Mono' },
          { l: 'DENSITY', v: 'Airy · 8/12/16/24 radius' },
        ].map((s, i) => (
          <div key={i} style={{
            padding: 18, borderRadius: 14,
            background: 'rgba(255,255,255,0.03)', border: '1px solid rgba(255,255,255,0.06)',
          }}>
            <div style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 10, color: '#6c7689', letterSpacing: '0.22em' }}>{s.l}</div>
            <div style={{ fontSize: 13.5, color: '#f4f7fb', marginTop: 8, fontWeight: 500, letterSpacing: '-0.005em' }}>{s.v}</div>
          </div>
        ))}
      </div>

      <div style={{ borderTop: '1px solid rgba(255,255,255,0.06)', paddingTop: 20, position: 'relative' }}>
        <div style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 10.5, letterSpacing: '0.22em', color: '#9aa6b8', marginBottom: 10 }}>ON THIS CANVAS</div>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 18, fontSize: 13.5, color: '#d4dbe6', lineHeight: 1.6 }}>
          <div><strong style={{ color: '#a4c2ff' }}>Foundations & Core</strong> — tokens 总览 / AI 对话 / SkillCard（4 layouts × 状态）</div>
          <div><strong style={{ color: '#c4a8ff' }}>Calendar · Timepage</strong> — Schedule（合并了时间流）/ Month / Year / Day / Editor + 导航流</div>
        </div>
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────────────────────────
// Deliverables card
// ────────────────────────────────────────────────────────────────────────

function DeliverablesCard() {
  const items = [
    { f: 'DESIGN.md', d: '完整设计系统文档（含日历交互规范）' },
    { f: 'tokens/eureka-tokens-b.json', d: 'Atmosphere · 选定的 design tokens（机器可读）' },
    { f: 'tokens/tokens.css', d: 'CSS variables（B 为默认）' },
    { f: 'index.html', d: '本 design canvas — 浏览 / 标注 / 协作' },
    { f: 'tokens/eureka-tokens-a.json', d: 'Slate · 存档备查', archived: true },
    { f: 'tokens/eureka-tokens-c.json', d: 'Lab · 存档备查', archived: true },
  ];
  return (
    <div style={{ width: '100%', height: '100%', boxSizing: 'border-box', padding: 36, background: '#0b1220', color: '#d4dbe6', fontFamily: '"Manrope","Noto Sans SC", system-ui, sans-serif' }}>
      <div style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 11, letterSpacing: '0.22em', color: '#9aa6b8', textTransform: 'uppercase' }}>FILES</div>
      <div style={{ fontSize: 26, fontWeight: 700, color: '#f4f7fb', marginTop: 8, letterSpacing: '-0.018em' }}>已交付</div>
      <div style={{ fontSize: 13, color: '#9aa6b8', marginTop: 6, marginBottom: 24, maxWidth: 600, lineHeight: 1.6 }}>
        所有 token 文件都在 <code style={{ fontFamily: '"JetBrains Mono",monospace', color: '#a4c2ff' }}>tokens/</code>。设计系统文档 <code style={{ fontFamily: '"JetBrains Mono",monospace', color: '#a4c2ff' }}>DESIGN.md</code> 解释了三套方向之间的差异、B 的选定理由、以及完整组件 + 日历交互规范。
      </div>
      <div style={{ border: '1px solid rgba(255,255,255,0.08)', borderRadius: 10, overflow: 'hidden' }}>
        {items.map((it, i) => (
          <div key={i} style={{
            display: 'grid', gridTemplateColumns: '14px auto 1fr', gap: 14,
            padding: '14px 18px', alignItems: 'center',
            borderBottom: i < items.length - 1 ? '1px solid rgba(255,255,255,0.04)' : 'none',
            opacity: it.archived ? 0.55 : 1,
          }}>
            <span style={{
              width: 6, height: 6, borderRadius: 999,
              background: it.archived ? '#6c7689' : '#86e0a5',
              boxShadow: it.archived ? 'none' : '0 0 8px rgba(134,224,165,0.5)',
            }}></span>
            <code style={{ fontFamily: '"JetBrains Mono",monospace', fontSize: 12.5, color: '#a4c2ff' }}>{it.f}</code>
            <span style={{ fontSize: 12.5, color: '#9aa6b8' }}>{it.d}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

// Mount
ReactDOM.createRoot(document.getElementById('root')).render(<App />);
