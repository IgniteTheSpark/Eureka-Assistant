// var-b-calendar.jsx — Atmosphere · Timepage-inspired calendar
// 5 mobile views: Schedule / Month / Year / Day detail / Event editor
// + an annotated flow diagram showing swipe transitions.
//
// Visual language:
//   color = signal — day tiles take a deep gradient based on their dominant
//   asset accent (event=purple, todo=blue, idea=amber). empty days are
//   collapsed/dim. multi-day events flow visually across day tiles.

// ────────────────────────────────────────────────────────────────────────
// Calendar data — 10-day window + month/year scaffolds
// ────────────────────────────────────────────────────────────────────────

const CAL_DAYS = [
  { d: 22, wd: 'THU', month: '5月', items: [
    { time: '14:00', title: '设计评审', accent: 'purple', kind: 'event' },
  ]},
  { d: 23, wd: 'FRI', month: '5月', items: [
    { time: '11:00', title: '一对一 · Lin', accent: 'purple', kind: 'event' },
    { time: 'all', title: '体检报告寄到', accent: 'blue', kind: 'todo' },
  ]},
  { d: 24, wd: 'SAT', month: '5月', label: 'TODAY', today: true, items: [
    { time: '12:30', title: '团队午餐 · 拉面', accent: 'green', kind: 'expense' },
    { time: '15:00', title: '准备 demo 脚本', accent: 'blue', kind: 'todo' },
    { time: '18:00', title: '回 Linus 邮件', accent: 'blue', kind: 'todo' },
  ]},
  { d: 25, wd: 'SUN', month: '5月', label: 'TOMORROW', items: [] },
  { d: 26, wd: 'MON', month: '5月', items: [
    { time: '10:00', title: '产品评审 · Eureka v2', accent: 'purple', kind: 'event' },
    { time: '14:00', title: '财务对账', accent: 'green', kind: 'todo' },
  ]},
  { d: 27, wd: 'TUE', month: '5月', items: [
    { time: '15:00', title: 'demo 演练', accent: 'purple', kind: 'event' },
    { time: '20:00', title: '健身', accent: 'blue', kind: 'todo' },
  ]},
  { d: 28, wd: 'WED', month: '5月', items: [] },
  { d: 29, wd: 'THU', month: '5月', items: [
    { time: '16:00', title: '客户拜访 · 林一帆', accent: 'purple', kind: 'event' },
  ]},
  { d: 30, wd: 'FRI', month: '5月', items: [] },
  { d: 31, wd: 'SAT', month: '5月', items: [] },
];

// Month view — May 2026 (May 1 = Friday)
const CAL_MONTH = {
  label: '5月',
  yearLabel: '2026',
  cells: (() => {
    const days = [];
    // Sun-first layout (matches Timepage). May 1, 2026 = Fri = col 5 from Sun
    days.push({ out: true, d: 26 }, { out: true, d: 27 }, { out: true, d: 28 }, { out: true, d: 29 }, { out: true, d: 30 }, { d: 1, kind: null }, { d: 2 });
    days.push({ d: 3 }, { d: 4 }, { d: 5 }, { d: 6, kind: 'event' }, { d: 7 }, { d: 8 }, { d: 9 });
    days.push({ d: 10 }, { d: 11 }, { d: 12 }, { d: 13, kind: 'event' }, { d: 14 }, { d: 15, kind: 'todo' }, { d: 16 });
    days.push({ d: 17 }, { d: 18 }, { d: 19 }, { d: 20 }, { d: 21, kind: 'event' }, { d: 22, kind: 'event' }, { d: 23, kind: 'event' });
    days.push({ d: 24, today: true, kind: 'mixed' }, { d: 25 }, { d: 26, selected: true, kind: 'event' }, { d: 27, kind: 'event' }, { d: 28 }, { d: 29, kind: 'event' }, { d: 30 });
    days.push({ d: 31 }, { out: true, d: 1 }, { out: true, d: 2 }, { out: true, d: 3 }, { out: true, d: 4 }, { out: true, d: 5 }, { out: true, d: 6 });
    return days;
  })(),
};

// 12 mini month calendars for the year view
const YEAR_MONTHS = [
  { name: '1月', start: 4,  days: 31, eventDays: [9, 18, 27] },
  { name: '2月', start: 0,  days: 28, eventDays: [14, 22] },
  { name: '3月', start: 0,  days: 31, eventDays: [3, 11, 25, 30] },
  { name: '4月', start: 3,  days: 30, eventDays: [7, 15, 20] },
  { name: '5月', start: 5,  days: 31, eventDays: [6, 13, 21, 22, 23, 24, 26, 27, 29], today: 24 },
  { name: '6月', start: 1,  days: 30, eventDays: [4, 12, 18, 25] },
  { name: '7月', start: 3,  days: 31, eventDays: [] },
  { name: '8月', start: 6,  days: 31, eventDays: [3, 9] },
  { name: '9月', start: 2,  days: 30, eventDays: [10, 17] },
  { name: '10月', start: 4, days: 31, eventDays: [22, 31] },
  { name: '11月', start: 0, days: 30, eventDays: [13] },
  { name: '12月', start: 2, days: 31, eventDays: [25, 31] },
];

// ────────────────────────────────────────────────────────────────────────
// Helpers: day-tile color recipes, status bar, home indicator
// ────────────────────────────────────────────────────────────────────────

function dayTone(items) {
  const has = (k) => items && items.some(i => i.kind === k);
  if (has('event') && (has('todo') || has('expense'))) return {
    bg: 'linear-gradient(135deg, rgba(156,128,240,0.40) 0%, rgba(111,158,255,0.20) 100%), #16183a',
    text: '#ffffff', meta: 'rgba(255,255,255,0.72)', dot: '#c4a8ff',
  };
  if (has('event')) return {
    bg: 'linear-gradient(135deg, rgba(156,128,240,0.42) 0%, rgba(120,98,200,0.22) 100%), #18143a',
    text: '#ffffff', meta: 'rgba(255,255,255,0.74)', dot: '#c4a8ff',
  };
  if (has('todo') || has('expense')) return {
    bg: 'linear-gradient(135deg, rgba(111,158,255,0.34) 0%, rgba(82,128,200,0.18) 100%), #131a35',
    text: '#ffffff', meta: 'rgba(255,255,255,0.72)', dot: '#8ab4ff',
  };
  if (has('idea')) return {
    bg: 'linear-gradient(135deg, rgba(245,201,119,0.24) 0%, rgba(180,140,80,0.12) 100%), #1f1c14',
    text: '#fff5e0', meta: 'rgba(255,245,224,0.72)', dot: '#f5c977',
  };
  return { bg: '#0e1426', text: '#5b6478', meta: 'rgba(255,255,255,0.35)', dot: 'transparent' };
}

function MobileStatusBar({ color = '#ffffff' }) {
  return (
    <div style={{
      height: 44, display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '0 24px 0 28px', flex: '0 0 44px',
      color, fontSize: 14, fontWeight: 600,
      fontFamily: '"Manrope", system-ui, sans-serif',
    }}>
      <span>9:41</span>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 11 }}>
        <span>●●●●</span>
        <span style={{ width: 16, height: 10, border: `1px solid ${color}`, borderRadius: 2, padding: 1, opacity: 0.9 }}>
          <span style={{ display: 'block', width: '70%', height: '100%', background: color, borderRadius: 1 }}></span>
        </span>
      </div>
    </div>
  );
}

function MobileHomeIndicator({ color = '#ffffff' }) {
  return (
    <div style={{ flex: '0 0 34px', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
      <span style={{ width: 134, height: 5, borderRadius: 999, background: color, opacity: 0.55 }}></span>
    </div>
  );
}

// Tiny color hint strip on the right edge of Month view (gesture affordance)
function GestureStrip({ colors }) {
  return (
    <div style={{
      position: 'absolute', top: 80, bottom: 80, right: 0, width: 3,
      display: 'flex', flexDirection: 'column', gap: 3,
    }}>
      {colors.map((c, i) => (
        <div key={i} style={{ flex: 1, background: c, opacity: 0.7 }}></div>
      ))}
    </div>
  );
}

// ────────────────────────────────────────────────────────────────────────
// 01 · SCHEDULE — vertical colored day-tile timeline
// ────────────────────────────────────────────────────────────────────────

function CalSchedule() {
  const filters = [
    { k: '全部', n: 52, active: true },
    { k: '事件', n: 8, dot: '#c4a8ff' },
    { k: '待办', n: 14, dot: '#8ab4ff' },
    { k: '想法', n: 22, dot: '#f5c977' },
    { k: '记账', n: 6, dot: '#86e0a5' },
    { k: '名片', n: 11, dot: '#d4dbe6' },
  ];
  return (
    <div style={{
      width: '100%', height: '100%',
      background: '#06070d', color: '#d4dbe6',
      fontFamily: '"Manrope","Noto Sans SC", system-ui, sans-serif',
      display: 'flex', flexDirection: 'column', overflow: 'hidden',
    }}>
      <MobileStatusBar />

      {/* Top header — brand + month picker */}
      <div style={{ padding: '4px 22px 10px', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
          <span style={{ fontSize: 20, fontWeight: 700, color: '#a4c2ff', letterSpacing: '-0.01em', textShadow: '0 0 14px rgba(111,158,255,0.4)' }}>5月</span>
          <span style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 11, color: 'rgba(255,255,255,0.40)', letterSpacing: '0.14em' }}>2026</span>
        </div>
        <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
          <button style={{ width: 28, height: 28, borderRadius: 999, background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.08)', color: 'rgba(255,255,255,0.65)', fontSize: 13, cursor: 'pointer' }}>⌕</button>
          <button style={{ width: 28, height: 28, borderRadius: 999, background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.08)', color: 'rgba(255,255,255,0.65)', fontSize: 11, fontFamily: '"JetBrains Mono", monospace', cursor: 'pointer' }}>⋮</button>
        </div>
      </div>

      {/* Asset-type filter strip (replaces standalone timeline page) */}
      <div className="eu-noscroll" style={{ display: 'flex', gap: 6, padding: '0 16px 12px', overflowX: 'auto', borderBottom: '1px solid rgba(255,255,255,0.04)' }}>
        {filters.map((f, i) => (
          <button key={i} style={{
            display: 'inline-flex', alignItems: 'center', gap: 6,
            padding: '5px 10px 5px 10px', borderRadius: 999,
            background: f.active ? 'rgba(111,158,255,0.14)' : 'rgba(255,255,255,0.03)',
            color: f.active ? '#a4c2ff' : 'rgba(255,255,255,0.62)',
            border: `1px solid ${f.active ? 'rgba(111,158,255,0.32)' : 'transparent'}`,
            fontSize: 11.5, fontWeight: 500, cursor: 'pointer', whiteSpace: 'nowrap',
            fontFamily: '"Manrope", sans-serif',
          }}>
            {f.dot && <span style={{ width: 5, height: 5, borderRadius: 999, background: f.dot, boxShadow: `0 0 5px ${f.dot}` }}></span>}
            {f.k}
            <span style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 10, opacity: 0.62 }}>{f.n}</span>
          </button>
        ))}
      </div>

      {/* Month rail label on left, scrolling stream on right */}
      <div style={{ flex: 1, display: 'grid', gridTemplateColumns: '64px 1fr', overflow: 'hidden', position: 'relative' }}>
        {/* Left rail — date column */}
        <div style={{ position: 'relative', borderRight: '1px solid rgba(255,255,255,0.04)' }}>
          {/* Date numbers (mirrors items below) */}
          <div style={{ display: 'flex', flexDirection: 'column', paddingTop: 6 }}>
            {CAL_DAYS.map((day, i) => {
              const isToday = !!day.today;
              const tone = dayTone(day.items);
              const empty = day.items.length === 0;
              return (
                <div key={i} style={{
                  height: empty ? 56 : (day.items.length === 1 ? 88 : (day.items.length === 2 ? 112 : 136)),
                  display: 'flex', flexDirection: 'column', alignItems: 'flex-end',
                  justifyContent: 'flex-start', paddingTop: 12, paddingRight: 8,
                  position: 'relative',
                }}>
                  {isToday && <div style={{ position: 'absolute', top: 10, bottom: 10, right: 0, width: 2, background: '#6f9eff', boxShadow: '0 0 8px rgba(111,158,255,0.7)' }}></div>}
                  <span style={{
                    fontFamily: '"JetBrains Mono", monospace', fontSize: 9.5, letterSpacing: '0.16em',
                    color: isToday ? '#6f9eff' : 'rgba(255,255,255,0.40)',
                  }}>{day.wd}</span>
                  <span style={{
                    fontSize: isToday ? 22 : 18, fontWeight: isToday ? 700 : 500,
                    color: isToday ? '#a4c2ff' : 'rgba(255,255,255,0.85)',
                    letterSpacing: '-0.01em', marginTop: 1, fontFamily: '"Manrope", sans-serif',
                    textShadow: isToday ? '0 0 12px rgba(111,158,255,0.5)' : 'none',
                  }}>{day.d}</span>
                </div>
              );
            })}
          </div>
        </div>

        {/* Right — day tiles */}
        <div className="eu-noscroll" style={{ overflowY: 'auto', padding: '6px 16px 16px 6px', display: 'flex', flexDirection: 'column', gap: 6 }}>
          {CAL_DAYS.map((day, i) => {
            const tone = dayTone(day.items);
            const empty = day.items.length === 0;
            return (
              <div key={i} style={{
                height: empty ? 50 : 'auto', minHeight: empty ? 50 : 82,
                background: tone.bg, borderRadius: 14, padding: empty ? '12px 16px' : '14px 18px',
                position: 'relative', overflow: 'hidden',
                display: 'flex', flexDirection: 'column', justifyContent: empty ? 'center' : 'flex-start', gap: 8,
              }}>
                {day.label && (
                  <div style={{
                    position: 'absolute', top: 10, right: 14,
                    fontFamily: '"JetBrains Mono", monospace', fontSize: 9.5,
                    letterSpacing: '0.20em', color: 'rgba(255,255,255,0.55)', fontWeight: 600,
                  }}>{day.label}</div>
                )}
                {empty ? (
                  <span style={{ color: tone.meta, fontSize: 12, fontStyle: 'italic', opacity: 0.7 }}>空闲</span>
                ) : (
                  day.items.map((it, j) => (
                    <div key={j} style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                      <span style={{
                        fontFamily: '"JetBrains Mono", monospace', fontSize: 10.5,
                        color: tone.meta, fontWeight: 500, minWidth: 38, letterSpacing: '0.02em',
                      }}>{it.time === 'all' ? 'all-day' : it.time}</span>
                      <span style={{
                        width: 5, height: 5, borderRadius: 999,
                        background: tone.dot, boxShadow: `0 0 6px ${tone.dot}`,
                        flex: '0 0 5px',
                      }}></span>
                      <span style={{
                        fontSize: 13.5, color: tone.text, fontWeight: 500,
                        letterSpacing: '-0.005em', lineHeight: 1.35,
                        flex: 1, minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
                      }}>{it.title}</span>
                    </div>
                  ))
                )}
              </div>
            );
          })}
        </div>
      </div>

      {/* Floating + FAB */}
      <div style={{
        position: 'absolute', right: 18, bottom: 60,
        width: 56, height: 56, borderRadius: 999,
        background: 'linear-gradient(135deg, #6f9eff, #9c80f0)',
        boxShadow: '0 8px 28px rgba(111,158,255,0.45), 0 0 0 1px rgba(255,255,255,0.08)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        color: '#fff', fontSize: 26, fontWeight: 300,
      }}>+</div>

      <MobileHomeIndicator />
    </div>
  );
}

// ────────────────────────────────────────────────────────────────────────
// 02 · MONTH — dot grid + selected-day summary
// ────────────────────────────────────────────────────────────────────────

function CalMonth() {
  // Selected day = May 26 (产品评审)
  const selectedDayItems = [
    { time: '10:00', title: '产品评审 · Eureka v2', accent: 'purple' },
    { time: '14:00', title: '财务对账', accent: 'green' },
  ];
  return (
    <div style={{
      width: '100%', height: '100%',
      background: '#06070d', color: '#d4dbe6',
      fontFamily: '"Manrope","Noto Sans SC", system-ui, sans-serif',
      display: 'flex', flexDirection: 'column', overflow: 'hidden',
      position: 'relative',
    }}>
      <MobileStatusBar />

      {/* Title block */}
      <div style={{ padding: '12px 28px 16px', display: 'flex', alignItems: 'center', gap: 14 }}>
        <div style={{ display: 'grid', gridTemplateColumns: '4px 4px 4px', gridTemplateRows: '4px 4px 4px', gap: 3 }}>
          {[0,1,2,3,4,5,6,7,8].map(i => <div key={i} style={{ background: '#a4c2ff', boxShadow: '0 0 4px rgba(164,194,255,0.6)' }}></div>)}
        </div>
        <div>
          <div style={{
            fontSize: 36, fontWeight: 700, color: '#a4c2ff', letterSpacing: '0.04em',
            textShadow: '0 0 24px rgba(111,158,255,0.45)', lineHeight: 1,
            fontFamily: '"Manrope", sans-serif',
          }}>{CAL_MONTH.label.toUpperCase()}</div>
          <div style={{ fontSize: 12, color: 'rgba(255,255,255,0.45)', fontFamily: '"JetBrains Mono", monospace', letterSpacing: '0.14em', marginTop: 4 }}>{CAL_MONTH.yearLabel}</div>
        </div>
      </div>

      {/* Weekday header */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', padding: '0 18px', marginBottom: 8 }}>
        {['S','M','T','W','T','F','S'].map((d, i) => (
          <div key={i} style={{ textAlign: 'center', fontSize: 10.5, color: 'rgba(255,255,255,0.32)', fontFamily: '"JetBrains Mono", monospace', letterSpacing: '0.16em' }}>{d}</div>
        ))}
      </div>

      {/* Day-dot grid */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', padding: '4px 18px', gap: 4, position: 'relative' }}>
        {CAL_MONTH.cells.map((c, i) => {
          let bg = 'transparent', fg = 'rgba(255,255,255,0.85)', border = 'transparent', glow = 'none', size = 32;
          if (c.out) { fg = 'rgba(255,255,255,0.18)'; }
          if (c.kind === 'event') { bg = 'rgba(156,128,240,0.28)'; border = 'rgba(196,168,255,0.40)'; fg = '#e5d9ff'; }
          if (c.kind === 'todo')  { bg = 'rgba(111,158,255,0.20)'; border = 'rgba(138,180,255,0.40)'; fg = '#d4e2ff'; }
          if (c.kind === 'mixed') { bg = 'rgba(156,128,240,0.32)'; border = 'rgba(196,168,255,0.50)'; fg = '#e5d9ff'; }
          if (c.today)    { bg = '#ffffff'; fg = '#1a1735'; border = 'transparent'; glow = '0 0 20px rgba(255,255,255,0.65)'; }
          if (c.selected) { border = '#ffffff'; bg = 'rgba(156,128,240,0.20)'; fg = '#ffffff'; }
          return (
            <div key={i} style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '6px 0' }}>
              <div style={{
                width: size, height: size, borderRadius: 999,
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                background: bg, border: `1.5px solid ${border}`, boxShadow: glow,
                fontSize: c.today ? 14 : 13, fontWeight: c.today ? 700 : 500,
                color: fg, fontFamily: '"JetBrains Mono", monospace', letterSpacing: '0.02em',
                transition: 'all 280ms cubic-bezier(.2,.7,.3,1)',
              }}>{c.d}</div>
            </div>
          );
        })}
      </div>

      {/* Selected-day summary */}
      <div style={{
        flex: 1, padding: '24px 28px 0',
        display: 'flex', flexDirection: 'column', gap: 14,
        borderTop: '1px solid rgba(255,255,255,0.05)', marginTop: 16,
      }}>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
          <span style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 10.5, letterSpacing: '0.24em', color: 'rgba(255,255,255,0.45)', fontWeight: 600 }}>5月 26 日 · 周一</span>
        </div>
        <div style={{ fontSize: 13.5, color: '#a4c2ff', letterSpacing: '0.04em', fontFamily: '"Manrope", sans-serif', textTransform: 'uppercase', fontWeight: 600 }}>2 件事</div>
        {selectedDayItems.map((it, i) => (
          <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 12, paddingBottom: 10, borderBottom: i < selectedDayItems.length - 1 ? '1px solid rgba(255,255,255,0.04)' : 'none' }}>
            <span style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 11, color: 'rgba(255,255,255,0.55)', minWidth: 40 }}>{it.time}</span>
            <span style={{ width: 6, height: 6, borderRadius: 999, background: it.accent === 'purple' ? '#c4a8ff' : '#86e0a5', boxShadow: `0 0 6px ${it.accent === 'purple' ? 'rgba(196,168,255,0.6)' : 'rgba(134,224,165,0.5)'}` }}></span>
            <span style={{ fontSize: 14, color: '#f4f7fb', fontWeight: 500 }}>{it.title}</span>
          </div>
        ))}
        <div style={{ fontSize: 12, color: 'rgba(255,255,255,0.32)', marginTop: 4, fontFamily: '"JetBrains Mono", monospace', letterSpacing: '0.12em' }}>+ 添加事件</div>
      </div>

      {/* Right edge gesture strip */}
      <GestureStrip colors={['#9c80f0','#6f9eff','#86e0a5','#f5c977','#ec6a83']} />

      <MobileHomeIndicator />
    </div>
  );
}

// ────────────────────────────────────────────────────────────────────────
// 03 · YEAR — 12 mini calendars in 3-column grid
// ────────────────────────────────────────────────────────────────────────

function CalYear() {
  return (
    <div style={{
      width: '100%', height: '100%',
      background: '#06070d', color: '#d4dbe6',
      fontFamily: '"Manrope","Noto Sans SC", system-ui, sans-serif',
      display: 'flex', flexDirection: 'column', overflow: 'hidden', position: 'relative',
    }}>
      <MobileStatusBar />

      {/* Title */}
      <div style={{ padding: '16px 28px 14px' }}>
        <div style={{
          fontSize: 56, fontWeight: 700, color: '#a4c2ff',
          letterSpacing: '-0.02em', textShadow: '0 0 28px rgba(111,158,255,0.5)',
          fontFamily: '"Manrope", sans-serif', lineHeight: 1,
        }}>2026</div>
        <div style={{ fontSize: 11, color: 'rgba(255,255,255,0.35)', fontFamily: '"JetBrains Mono", monospace', letterSpacing: '0.20em', marginTop: 6, textTransform: 'uppercase' }}>YEAR · 47 EVENTS</div>
      </div>

      {/* 12 month mini grid (3 columns × 4 rows) */}
      <div className="eu-noscroll" style={{ flex: 1, overflowY: 'auto', padding: '6px 18px 14px', display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 14, alignContent: 'start' }}>
        {YEAR_MONTHS.map((m, idx) => {
          const isCurrent = m.name === '5月';
          // Build the days array — 6 rows × 7 cols
          const dayCells = Array(42).fill(null);
          for (let d = 1; d <= m.days; d++) dayCells[m.start + d - 1] = d;
          return (
            <div key={m.name} style={{
              display: 'flex', flexDirection: 'column', gap: 6,
              padding: '10px 8px',
              background: isCurrent ? 'rgba(156,128,240,0.06)' : 'transparent',
              borderRadius: 8,
              border: isCurrent ? '1px solid rgba(196,168,255,0.20)' : '1px solid transparent',
            }}>
              <div style={{
                fontSize: 11, fontWeight: 700, fontFamily: '"Manrope", sans-serif',
                color: isCurrent ? '#a4c2ff' : 'rgba(255,255,255,0.65)',
                letterSpacing: '0.06em', textTransform: 'uppercase',
                textShadow: isCurrent ? '0 0 8px rgba(111,158,255,0.4)' : 'none',
              }}>{m.name.toUpperCase()}</div>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 1.5 }}>
                {dayCells.map((d, i) => {
                  const isEvent = d && m.eventDays.includes(d);
                  const isToday = m.today === d;
                  return (
                    <div key={i} style={{
                      display: 'flex', alignItems: 'center', justifyContent: 'center',
                      height: 12, fontSize: 8.5,
                      fontFamily: '"JetBrains Mono", monospace',
                      color: !d ? 'transparent' : (isToday ? '#1a1735' : (isEvent ? '#c4a8ff' : 'rgba(255,255,255,0.42)')),
                      background: isToday ? '#ffffff' : 'transparent',
                      borderRadius: 999,
                      fontWeight: isEvent || isToday ? 700 : 400,
                      letterSpacing: '0.02em',
                    }}>{d || '·'}</div>
                  );
                })}
              </div>
            </div>
          );
        })}
      </div>

      <MobileHomeIndicator />
    </div>
  );
}

// ────────────────────────────────────────────────────────────────────────
// 04 · DAY DETAIL — full-bleed colored day
// ────────────────────────────────────────────────────────────────────────

function CalDay() {
  return (
    <div style={{
      width: '100%', height: '100%',
      background: 'linear-gradient(180deg, #3d2f7a 0%, #2a1f5a 100%)',
      color: '#ffffff',
      fontFamily: '"Manrope","Noto Sans SC", system-ui, sans-serif',
      display: 'flex', flexDirection: 'column', overflow: 'hidden',
      position: 'relative',
    }}>
      {/* Glow */}
      <div style={{ position: 'absolute', top: -60, right: -60, width: 280, height: 280, borderRadius: 999, background: 'radial-gradient(circle, rgba(196,168,255,0.35), transparent 70%)', pointerEvents: 'none' }}></div>
      <div style={{ position: 'absolute', bottom: -100, left: -80, width: 320, height: 320, borderRadius: 999, background: 'radial-gradient(circle, rgba(111,158,255,0.20), transparent 70%)', pointerEvents: 'none' }}></div>

      <MobileStatusBar color="#ffffff" />

      {/* Top bar */}
      <div style={{ padding: '4px 20px 0', display: 'flex', alignItems: 'center', justifyContent: 'space-between', position: 'relative' }}>
        <button style={{ width: 36, height: 36, background: 'rgba(255,255,255,0.08)', border: '1px solid rgba(255,255,255,0.12)', borderRadius: 999, color: '#fff', fontSize: 16, cursor: 'pointer' }}>‹</button>
        <div style={{ textAlign: 'center' }}>
          <div style={{ fontSize: 22, fontWeight: 700, letterSpacing: '0.20em', color: '#ffffff', fontFamily: '"Manrope", sans-serif', textShadow: '0 0 24px rgba(255,255,255,0.30)' }}>周一</div>
          <div style={{ fontSize: 11, fontFamily: '"JetBrains Mono", monospace', color: 'rgba(255,255,255,0.65)', letterSpacing: '0.18em', marginTop: 4 }}>MAY 26</div>
        </div>
        <button style={{ width: 36, height: 36, background: 'rgba(255,255,255,0.08)', border: '1px solid rgba(255,255,255,0.12)', borderRadius: 999, color: '#fff', fontSize: 18, cursor: 'pointer' }}>+</button>
      </div>

      {/* Sections */}
      <div className="eu-noscroll" style={{ flex: 1, overflowY: 'auto', padding: '24px 20px 16px', display: 'flex', flexDirection: 'column', gap: 16, position: 'relative' }}>
        <SectionLabel>事件</SectionLabel>
        <DayCard accent="rgba(255,255,255,0.10)" border="rgba(255,255,255,0.18)">
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 6 }}>
            <div style={{ fontSize: 11, color: 'rgba(255,255,255,0.68)', fontFamily: '"JetBrains Mono", monospace', letterSpacing: '0.14em' }}>10:00 — 11:00</div>
            <div style={{ fontSize: 10, color: 'rgba(255,255,255,0.45)', fontFamily: '"JetBrains Mono", monospace', letterSpacing: '0.16em' }}>EVENT</div>
          </div>
          <div style={{ fontSize: 17, fontWeight: 600, color: '#ffffff', letterSpacing: '-0.01em', marginBottom: 4 }}>产品评审 · Eureka v2</div>
          <div style={{ fontSize: 12.5, color: 'rgba(255,255,255,0.72)' }}>会议室 B · 60 min</div>
        </DayCard>

        <SectionLabel>待办</SectionLabel>
        <DayCard accent="rgba(255,255,255,0.10)" border="rgba(255,255,255,0.18)">
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 6 }}>
            <div style={{ fontSize: 11, color: 'rgba(255,255,255,0.68)', fontFamily: '"JetBrains Mono", monospace', letterSpacing: '0.14em' }}>14:00 截止</div>
            <div style={{ fontSize: 10, color: 'rgba(255,255,255,0.45)', fontFamily: '"JetBrains Mono", monospace', letterSpacing: '0.16em' }}>TODO</div>
          </div>
          <div style={{ fontSize: 16, fontWeight: 500, color: '#ffffff', letterSpacing: '-0.005em', marginBottom: 6 }}>财务对账</div>
          <SourceChip />
        </DayCard>
        <DayCard accent="rgba(255,255,255,0.10)" border="rgba(255,255,255,0.18)">
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 6 }}>
            <div style={{ fontSize: 11, color: 'rgba(255,255,255,0.68)', fontFamily: '"JetBrains Mono", monospace', letterSpacing: '0.14em' }}>18:00 截止</div>
            <div style={{ fontSize: 10, color: 'rgba(255,255,255,0.45)', fontFamily: '"JetBrains Mono", monospace', letterSpacing: '0.16em' }}>TODO</div>
          </div>
          <div style={{ fontSize: 16, fontWeight: 500, color: '#ffffff', letterSpacing: '-0.005em' }}>准备 demo 脚本</div>
        </DayCard>

        <SectionLabel>今日捕捉</SectionLabel>
        <DayCard accent="rgba(255,255,255,0.08)" border="rgba(255,255,255,0.14)">
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 6 }}>
            <span style={{ width: 22, height: 22, borderRadius: 6, background: 'rgba(245,201,119,0.16)', border: '1px solid rgba(245,201,119,0.30)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#f5c977', fontFamily: '"JetBrains Mono", monospace', fontSize: 12 }}>◇</span>
            <span style={{ fontSize: 10, color: 'rgba(255,255,255,0.50)', fontFamily: '"JetBrains Mono", monospace', letterSpacing: '0.16em' }}>IDEA</span>
          </div>
          <div style={{ fontSize: 14, fontWeight: 600, color: '#ffffff', letterSpacing: '-0.005em', marginBottom: 2 }}>SkillCard 的“沉淀”动画</div>
          <div style={{ fontSize: 12, color: 'rgba(255,255,255,0.72)', lineHeight: 1.5, marginBottom: 6 }}>能不能让卡片从 chat 气泡里“析出”，像结晶一样飘到右侧资产栏…</div>
          <SourceChip />
        </DayCard>
        <DayCard accent="rgba(255,255,255,0.08)" border="rgba(255,255,255,0.14)">
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <span style={{ width: 22, height: 22, borderRadius: 6, background: 'rgba(134,224,165,0.16)', border: '1px solid rgba(134,224,165,0.30)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#86e0a5', fontFamily: '"JetBrains Mono", monospace', fontSize: 11 }}>¥</span>
            <span style={{ fontSize: 10, color: 'rgba(255,255,255,0.50)', fontFamily: '"JetBrains Mono", monospace', letterSpacing: '0.16em' }}>EXPENSE</span>
            <span style={{ marginLeft: 'auto', fontSize: 16, fontWeight: 600, color: '#ffffff', fontFamily: '"JetBrains Mono", monospace' }}>¥ 68</span>
          </div>
          <div style={{ fontSize: 12.5, color: 'rgba(255,255,255,0.78)', marginTop: 6 }}>团队午餐 · 拉面 · 餐饮</div>
        </DayCard>
      </div>

      <MobileHomeIndicator />
    </div>
  );
}

function SectionLabel({ children }) {
  return (
    <div style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 10.5, letterSpacing: '0.22em', color: 'rgba(255,255,255,0.50)', fontWeight: 600, textTransform: 'uppercase' }}>{children}</div>
  );
}

function SourceChip({ label = '闪念 · 14:32', icon = '♪' }) {
  return (
    <div style={{
      display: 'inline-flex', alignItems: 'center', gap: 5,
      padding: '3px 8px 3px 7px', borderRadius: 999,
      background: 'rgba(0,0,0,0.22)',
      border: '1px solid rgba(255,255,255,0.08)',
      color: 'rgba(255,255,255,0.62)',
      fontSize: 10, fontFamily: '"JetBrains Mono", monospace', letterSpacing: '0.06em',
      alignSelf: 'flex-start',
    }}>
      <span style={{ color: 'rgba(164,194,255,0.85)' }}>{icon}</span>
      <span>{label}</span>
      <span style={{ color: 'rgba(255,255,255,0.45)' }}>→</span>
    </div>
  );
}

function DayCard({ children, accent, border }) {
  return (
    <div style={{
      padding: '14px 16px', borderRadius: 14,
      background: accent, border: `1px solid ${border}`,
      backdropFilter: 'blur(10px)',
      boxShadow: '0 4px 20px rgba(0,0,0,0.20)',
    }}>{children}</div>
  );
}

function FileCard() {
  return (
    <div style={{
      padding: '14px 16px', borderRadius: 14,
      background: 'rgba(0,0,0,0.25)', border: '1px solid rgba(255,255,255,0.08)',
      backdropFilter: 'blur(10px)',
      display: 'flex', flexDirection: 'column', gap: 10,
    }}>
      {/* File row */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
        <div style={{
          width: 32, height: 32, borderRadius: 8,
          background: 'rgba(111,158,255,0.12)', border: '1px solid rgba(111,158,255,0.28)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          color: '#a4c2ff', fontSize: 14, flex: '0 0 32px',
        }}>♪</div>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: 12.5, color: '#ffffff', fontWeight: 500, fontFamily: '"JetBrains Mono", monospace', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>flash_20260524_143215.m4a</div>
          <div style={{ display: 'flex', gap: 10, marginTop: 2, fontSize: 10.5, color: 'rgba(255,255,255,0.55)', fontFamily: '"JetBrains Mono", monospace', letterSpacing: '0.04em' }}>
            <span>38s</span>
            <span>·</span>
            <span>14:32</span>
            <span>·</span>
            <span style={{ color: '#86e0a5' }}>● ASR 完成</span>
          </div>
        </div>
      </div>
      {/* Mini waveform */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 1.5, height: 22 }}>
        {[0.4,0.6,0.3,0.8,0.5,0.7,0.4,0.6,0.9,0.5,0.3,0.7,0.5,0.6,0.4,0.8,0.5,0.3,0.6,0.4,0.7,0.5,0.4,0.6,0.8,0.4,0.5,0.3,0.6,0.5,0.4,0.3,0.5,0.4,0.6,0.5,0.3,0.4,0.5,0.3].map((h, i) => (
          <div key={i} style={{ flex: 1, height: `${h * 100}%`, background: 'rgba(164,194,255,0.45)', borderRadius: 1 }}></div>
        ))}
      </div>
      {/* Transcript preview + chevron */}
      <div style={{
        padding: '8px 10px', background: 'rgba(255,255,255,0.04)', borderRadius: 8,
        fontSize: 12, color: 'rgba(255,255,255,0.78)', lineHeight: 1.55, fontStyle: 'italic',
        display: 'flex', alignItems: 'center', gap: 10,
      }}>
        <span style={{ flex: 1 }}>“... 周三那个评审 我得提前把脚本写好 顺便提醒老板财务那边也对一下账 ...”</span>
        <span style={{ flex: '0 0 auto', color: '#a4c2ff', fontFamily: '"JetBrains Mono", monospace', fontSize: 11, letterSpacing: '0.06em' }}>→</span>
      </div>
      <div style={{ fontSize: 10.5, color: 'rgba(255,255,255,0.45)', fontFamily: '"JetBrains Mono", monospace', letterSpacing: '0.16em' }}>查看完整 TRANSCRIPT · 播放录音 · 下载</div>
    </div>
  );
}

// ────────────────────────────────────────────────────────────────────────
// 04b · ASSET DETAIL — full record with source FileCard at bottom
// ────────────────────────────────────────────────────────────────────────

function CalAssetDetail() {
  return (
    <div style={{
      width: '100%', height: '100%',
      background: 'linear-gradient(180deg, #1a2245 0%, #0e1430 100%)',
      color: '#ffffff',
      fontFamily: '"Manrope","Noto Sans SC", system-ui, sans-serif',
      display: 'flex', flexDirection: 'column', overflow: 'hidden',
      position: 'relative',
    }}>
      {/* Glows */}
      <div style={{ position: 'absolute', top: -60, right: -60, width: 280, height: 280, borderRadius: 999, background: 'radial-gradient(circle, rgba(138,180,255,0.30), transparent 70%)', pointerEvents: 'none' }}></div>
      <div style={{ position: 'absolute', bottom: -100, left: -80, width: 280, height: 280, borderRadius: 999, background: 'radial-gradient(circle, rgba(111,158,255,0.18), transparent 70%)', pointerEvents: 'none' }}></div>

      <MobileStatusBar color="#ffffff" />

      {/* Top bar */}
      <div style={{ padding: '4px 18px 12px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', position: 'relative', zIndex: 1 }}>
        <button style={{ width: 36, height: 36, background: 'rgba(255,255,255,0.06)', border: '1px solid rgba(255,255,255,0.10)', borderRadius: 999, color: '#fff', fontSize: 16, cursor: 'pointer' }}>‹</button>
        <span style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 10.5, color: 'rgba(255,255,255,0.55)', letterSpacing: '0.20em' }}>TODO · A001</span>
        <button style={{ width: 36, height: 36, background: 'rgba(255,255,255,0.06)', border: '1px solid rgba(255,255,255,0.10)', borderRadius: 999, color: '#fff', fontSize: 14, cursor: 'pointer' }}>⋯</button>
      </div>

      {/* Scrollable body */}
      <div className="eu-noscroll" style={{ flex: 1, overflowY: 'auto', padding: '4px 22px 22px', display: 'flex', flexDirection: 'column', gap: 22, position: 'relative', zIndex: 1 }}>
        {/* Hero */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <span style={{
              width: 28, height: 28, borderRadius: 8,
              background: 'rgba(138,180,255,0.16)', border: '1px solid rgba(138,180,255,0.32)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              color: '#8ab4ff', fontFamily: '"JetBrains Mono", monospace', fontSize: 13, boxShadow: '0 0 14px rgba(111,158,255,0.30)',
            }}>☑</span>
            <span style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 10.5, letterSpacing: '0.18em', color: '#8ab4ff', fontWeight: 600 }}>待办</span>
            <span style={{ marginLeft: 'auto', fontFamily: '"JetBrains Mono", monospace', fontSize: 10, color: 'rgba(255,255,255,0.50)' }}>14:00 截止</span>
          </div>
          <div style={{ fontSize: 24, fontWeight: 700, color: '#ffffff', letterSpacing: '-0.018em', lineHeight: 1.3 }}>财务对账</div>
          <div style={{ fontSize: 13, color: 'rgba(255,255,255,0.72)', lineHeight: 1.6 }}>
            把这个月的报销跟会计核一下，主要是上周出差那几笔。
          </div>
        </div>

        {/* Meta strip — single inline row */}
        <div style={{
          display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: 10,
          padding: '10px 0', borderTop: '1px solid rgba(255,255,255,0.06)',
          borderBottom: '1px solid rgba(255,255,255,0.06)',
          fontFamily: '"JetBrains Mono", monospace', fontSize: 11, color: 'rgba(255,255,255,0.65)', letterSpacing: '0.04em',
        }}>
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
            <span style={{ width: 6, height: 6, borderRadius: 999, background: '#f5c977', boxShadow: '0 0 6px rgba(245,201,119,0.55)' }}></span>
            进行中
          </span>
          <span style={{ color: 'rgba(255,255,255,0.25)' }}>·</span>
          <span>创建 5月24日 14:32</span>
          <span style={{ color: 'rgba(255,255,255,0.25)' }}>·</span>
          <span style={{ color: 'rgba(164,194,255,0.85)', display: 'inline-flex', alignItems: 'center', gap: 4, cursor: 'pointer' }}>在日历 →</span>
        </div>

        {/* Source — minimal hint + jump (full session detail lives in session page) */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          <SectionLabel>来源</SectionLabel>
          <button style={{
            display: 'flex', alignItems: 'center', gap: 12,
            padding: '11px 14px', borderRadius: 12,
            background: 'rgba(111,158,255,0.08)', border: '1px solid rgba(111,158,255,0.22)',
            color: 'inherit', cursor: 'pointer', textAlign: 'left', width: '100%',
          }}>
            <span style={{
              width: 22, height: 22, borderRadius: 6,
              background: 'rgba(111,158,255,0.16)', border: '1px solid rgba(111,158,255,0.28)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              color: '#a4c2ff', fontSize: 11, flex: '0 0 22px',
            }}>♪</span>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
                <span style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 9.5, letterSpacing: '0.16em', color: '#a4c2ff', fontWeight: 600 }}>SESSION · FLASH</span>
                <span style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 10, color: 'rgba(255,255,255,0.50)', marginLeft: 'auto' }}>5月24日 14:32</span>
              </div>
              <div style={{ fontSize: 12.5, color: '#ffffff', marginTop: 2, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>闪念 · demo 准备</div>
            </div>
            <span style={{ color: 'rgba(164,194,255,0.85)', fontSize: 14 }}>›</span>
          </button>
        </div>
      </div>

      <MobileHomeIndicator />
    </div>
  );
}

function MetaCell({ k, v, dot, link }) {
  return (
    <div style={{
      padding: '12px 14px', background: 'rgba(0,0,0,0.16)',
      display: 'flex', flexDirection: 'column', gap: 4,
    }}>
      <div style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 10, letterSpacing: '0.18em', color: 'rgba(255,255,255,0.50)', textTransform: 'uppercase' }}>{k}</div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 13, color: '#ffffff', fontWeight: 500 }}>
        {dot && <span style={{ width: 6, height: 6, borderRadius: 999, background: dot, boxShadow: `0 0 6px ${dot}` }}></span>}
        <span>{v}</span>
        {link && <span style={{ marginLeft: 'auto', color: 'rgba(164,194,255,0.85)', fontFamily: '"JetBrains Mono", monospace', fontSize: 11 }}>→</span>}
      </div>
    </div>
  );
}

function LinkRow({ accent, icon, iconColor, label, title, sub }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 12,
      padding: '10px 12px', borderRadius: 12,
      background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.07)',
    }}>
      <span style={{
        width: 24, height: 24, borderRadius: 6,
        background: 'rgba(0,0,0,0.20)', border: `1px solid ${accent}`,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        color: iconColor, fontFamily: '"JetBrains Mono", monospace', fontSize: 11,
        flex: '0 0 24px',
      }}>{icon}</span>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
          <span style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 9.5, letterSpacing: '0.18em', color: iconColor, fontWeight: 600 }}>{label}</span>
          <span style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 10, color: 'rgba(255,255,255,0.45)', marginLeft: 'auto' }}>{sub}</span>
        </div>
        <div style={{ fontSize: 13, color: '#ffffff', fontWeight: 500, marginTop: 2, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{title}</div>
      </div>
      <span style={{ color: 'rgba(255,255,255,0.40)', fontSize: 12 }}>›</span>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────
// SessionTurnCard — source = a session + the input turn that spawned it
// ─────────────────────────────────────────────────────────────────────

function SessionTurnCard() {
  return (
    <div style={{
      borderRadius: 14,
      background: 'rgba(0,0,0,0.22)', border: '1px solid rgba(255,255,255,0.08)',
      backdropFilter: 'blur(10px)',
      display: 'flex', flexDirection: 'column', overflow: 'hidden',
    }}>
      {/* Session header */}
      <button style={{
        display: 'flex', alignItems: 'center', gap: 12,
        padding: '12px 14px', background: 'rgba(111,158,255,0.08)',
        border: 'none', borderBottom: '1px solid rgba(255,255,255,0.06)',
        cursor: 'pointer', textAlign: 'left', color: 'inherit',
      }}>
        <span style={{
          width: 28, height: 28, borderRadius: 8,
          background: 'rgba(111,158,255,0.16)', border: '1px solid rgba(111,158,255,0.30)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          color: '#a4c2ff', fontSize: 14, flex: '0 0 28px',
        }}>♪</span>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
            <span style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 10, letterSpacing: '0.18em', color: '#a4c2ff', fontWeight: 600 }}>SESSION · FLASH</span>
            <span style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 10, color: 'rgba(255,255,255,0.50)', marginLeft: 'auto' }}>5月24日 14:32</span>
          </div>
          <div style={{ fontSize: 13.5, color: '#ffffff', fontWeight: 500, marginTop: 2 }}>闪念 · demo 准备</div>
        </div>
        <span style={{ color: 'rgba(255,255,255,0.45)', fontSize: 14 }}>›</span>
      </button>

      {/* The exact input turn */}
      <div style={{ padding: '14px 14px 12px', position: 'relative' }}>
        <div style={{ position: 'absolute', left: 14, top: 14, bottom: 12, width: 2, background: 'rgba(138,180,255,0.50)', borderRadius: 1 }}></div>
        <div style={{ paddingLeft: 14 }}>
          <div style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 9.5, letterSpacing: '0.18em', color: 'rgba(255,255,255,0.55)', fontWeight: 600, marginBottom: 6 }}>INPUT TURN · 产生当前资产</div>
          <div style={{ fontSize: 13, color: 'rgba(255,255,255,0.88)', lineHeight: 1.65, fontStyle: 'italic' }}>
            “顺便提醒我周三之前把 demo 脚本写好，重点突出硬件断网恢复那块。还有，找时间跟林一帆约个咖啡…”
          </div>
        </div>
      </div>

      {/* Sibling assets */}
      <div style={{ padding: '0 14px 12px' }}>
        <div style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 9.5, letterSpacing: '0.18em', color: 'rgba(255,255,255,0.50)', marginBottom: 6, fontWeight: 600 }}>同一 SESSION 还创建了 · 1</div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '8px 10px', borderRadius: 8, background: 'rgba(255,255,255,0.03)', border: '1px solid rgba(255,255,255,0.05)' }}>
          <span style={{ width: 18, height: 18, borderRadius: 4, background: 'rgba(196,168,255,0.16)', border: '1px solid rgba(196,168,255,0.32)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#c4a8ff', fontFamily: '"JetBrains Mono", monospace', fontSize: 10, flex: '0 0 18px' }}>●</span>
          <span style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 9.5, color: '#c4a8ff', letterSpacing: '0.14em', fontWeight: 600 }}>EVENT</span>
          <span style={{ flex: 1, fontSize: 12, color: '#f4f7fb', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>跟林一帆约咖啡</span>
          <span style={{ color: 'rgba(255,255,255,0.40)', fontSize: 11 }}>›</span>
        </div>
      </div>

      {/* Indirect file pointer */}
      <div style={{
        padding: '10px 14px', borderTop: '1px solid rgba(255,255,255,0.05)',
        display: 'flex', alignItems: 'center', gap: 8,
        background: 'rgba(0,0,0,0.18)',
      }}>
        <span style={{ color: 'rgba(164,194,255,0.85)', fontSize: 11 }}>♪</span>
        <code style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 10.5, color: 'rgba(255,255,255,0.65)', flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>flash_20260524_143215.m4a</code>
        <span style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 10, color: 'rgba(255,255,255,0.45)' }}>38s</span>
        <span style={{ color: 'rgba(164,194,255,0.65)', fontSize: 11 }}>↗</span>
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────────────────────────
// 06 · ASSET LIBRARY HUB — type tiles + recent stream
// ────────────────────────────────────────────────────────────────────────

const LIB_ACCENT = {
  blue:    { fg: '#8ab4ff', bg: 'rgba(138,180,255,0.10)', edge: 'rgba(138,180,255,0.24)', glow: 'rgba(111,158,255,0.30)' },
  amber:   { fg: '#f5c977', bg: 'rgba(245,201,119,0.10)', edge: 'rgba(245,201,119,0.24)', glow: 'rgba(245,201,119,0.30)' },
  green:   { fg: '#86e0a5', bg: 'rgba(134,224,165,0.10)', edge: 'rgba(134,224,165,0.24)', glow: 'rgba(134,224,165,0.30)' },
  purple:  { fg: '#c4a8ff', bg: 'rgba(196,168,255,0.10)', edge: 'rgba(196,168,255,0.24)', glow: 'rgba(196,168,255,0.30)' },
  neutral: { fg: '#d4dbe6', bg: 'rgba(212,219,230,0.05)', edge: 'rgba(212,219,230,0.16)', glow: 'rgba(212,219,230,0.18)' },
  cyan:    { fg: '#7dd3df', bg: 'rgba(125,211,223,0.10)', edge: 'rgba(125,211,223,0.24)', glow: 'rgba(125,211,223,0.30)' },
};

const TYPE_TILES = [
  { key: 'todo',    label: '待办',  n: 14, icon: '☑', accent: 'blue',    preview: '财务对账' },
  { key: 'event',   label: '事件',  n: 8,  icon: '●', accent: 'purple',  preview: '产品评审 · 5月26' },
  { key: 'idea',    label: '想法',  n: 22, icon: '◇', accent: 'amber',   preview: 'SkillCard "沉淀" 动画' },
  { key: 'expense', label: '记账',  n: 6,  icon: '¥', accent: 'green',   preview: '本月 ¥ 1,240' },
  { key: 'contact', label: '名片',  n: 11, icon: '◯', accent: 'neutral', preview: '林一帆 · Aurora Capital' },
  { key: 'file',    label: '文件',  n: 7,  icon: '♪', accent: 'cyan',    preview: '7 闪念 · 1 会议' },
];

function CalAssetLibrary() {
  return (
    <div style={{
      width: '100%', height: '100%',
      background: 'radial-gradient(800px 500px at 20% -10%, rgba(111,158,255,0.10), transparent 60%), #06070d',
      color: '#d4dbe6',
      fontFamily: '"Manrope","Noto Sans SC", system-ui, sans-serif',
      display: 'flex', flexDirection: 'column', overflow: 'hidden',
    }}>
      <MobileStatusBar />

      <div style={{ padding: '6px 22px 14px', display: 'flex', alignItems: 'baseline', justifyContent: 'space-between' }}>
        <div>
          <div style={{ fontSize: 26, fontWeight: 700, color: '#f4f7fb', letterSpacing: '-0.02em' }}>资产库</div>
          <div style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 10.5, color: 'rgba(255,255,255,0.45)', letterSpacing: '0.16em', marginTop: 4 }}>68 ITEMS · LAST 30D</div>
        </div>
        <button style={{ width: 32, height: 32, borderRadius: 999, background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.08)', color: 'rgba(255,255,255,0.70)', fontSize: 13, cursor: 'pointer' }}>⌕</button>
      </div>

      <div className="eu-noscroll" style={{ flex: 1, overflowY: 'auto', padding: '0 16px 18px' }}>
        {/* Type tile grid */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10, marginBottom: 22 }}>
          {TYPE_TILES.map(t => {
            const ac = LIB_ACCENT[t.accent];
            return (
              <button key={t.key} style={{
                display: 'flex', flexDirection: 'column', gap: 12,
                padding: '14px 14px 12px', borderRadius: 14,
                background: ac.bg, border: `1px solid ${ac.edge}`,
                color: 'inherit', cursor: 'pointer', textAlign: 'left',
                minHeight: 116,
              }}>
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                  <span style={{
                    width: 30, height: 30, borderRadius: 8,
                    background: 'rgba(0,0,0,0.20)', border: `1px solid ${ac.edge}`,
                    display: 'flex', alignItems: 'center', justifyContent: 'center',
                    color: ac.fg, fontFamily: '"JetBrains Mono", monospace', fontSize: 14,
                    boxShadow: `0 0 10px ${ac.glow}`,
                  }}>{t.icon}</span>
                  <span style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 22, fontWeight: 700, color: '#ffffff', letterSpacing: '-0.01em' }}>{t.n}</span>
                </div>
                <div>
                  <div style={{ fontSize: 15, fontWeight: 600, color: '#f4f7fb', letterSpacing: '-0.005em' }}>{t.label}</div>
                  <div style={{
                    fontSize: 11, color: 'rgba(255,255,255,0.50)', marginTop: 4,
                    overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
                    fontFamily: t.key === 'file' ? '"JetBrains Mono", monospace' : 'inherit',
                  }}>{t.preview}</div>
                </div>
              </button>
            );
          })}
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 10 }}>
          <span style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 10.5, letterSpacing: '0.22em', color: 'rgba(255,255,255,0.55)', fontWeight: 600 }}>最近</span>
          <span style={{ flex: 1, height: 1, background: 'rgba(255,255,255,0.05)' }}></span>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          <LibCard accent="amber" icon="◇" label="IDEA" title="SkillCard 的“沉淀”动画" sub="14:32 · 闪念" hasSource />
          <LibCard accent="blue" icon="☑" label="TODO" title="财务对账" sub="截止 5月26 14:00" hasSource />
          <LibCard accent="green" icon="¥" label="EXPENSE" title="团队午餐 · 拉面" sub="¥ 68 · 餐饮" amount="¥ 68" />
          <LibCard accent="purple" icon="●" label="EVENT" title="产品评审 · Eureka v2" sub="5月26日 10:00" />
        </div>
      </div>

      <MobileHomeIndicator />
    </div>
  );
}

// ────────────────────────────────────────────────────────────────────────
// 07 · ASSET TYPE — 想法 list (representative type entry)
// ────────────────────────────────────────────────────────────────────────

function CalAssetIdeas() {
  const groups = [
    { d: '今天 · 5月24日', items: [
      { t: 'SkillCard 的"沉淀"动画', s: '14:32 · 闪念', hasSource: true,
        body: '能不能让卡片从 chat 气泡里"析出"，像结晶一样飘到右侧资产栏。要有"AI 在帮我整理"的感受。' },
      { t: 'demo 脚本要突出硬件断流恢复', s: '14:32 · 闪念', hasSource: true },
    ]},
    { d: '昨天 · 5月23日', items: [
      { t: '语音输入的容错策略', s: '22:03 · 闪念', hasSource: true,
        body: 'Web Speech API 在嘈杂环境下识别会跳词，要不要做个"轻确认"步骤？' },
      { t: '上下文恢复在多会话间的表现', s: '15:11 · 手动' },
    ]},
    { d: '上周', items: [
      { t: '闪念 FAB 的长按手感', s: '5月19日 · chat' },
      { t: '事件和待办合并为"仿生物"？', s: '5月18日' },
    ]},
  ];
  return (
    <div style={{
      width: '100%', height: '100%',
      background: 'radial-gradient(700px 460px at 20% -10%, rgba(245,201,119,0.10), transparent 60%), #06070d',
      color: '#d4dbe6',
      fontFamily: '"Manrope","Noto Sans SC", system-ui, sans-serif',
      display: 'flex', flexDirection: 'column', overflow: 'hidden',
    }}>
      <MobileStatusBar />
      <div style={{ padding: '4px 18px 12px', display: 'flex', alignItems: 'center', gap: 10 }}>
        <button style={{ width: 32, height: 32, background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.08)', borderRadius: 999, color: 'rgba(255,255,255,0.85)', fontSize: 14, cursor: 'pointer' }}>‹</button>
        <span style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 10.5, color: 'rgba(255,255,255,0.55)', letterSpacing: '0.20em' }}>资产库 →</span>
      </div>
      <div style={{ padding: '0 22px 16px', display: 'flex', alignItems: 'center', gap: 12, borderBottom: '1px solid rgba(255,255,255,0.05)' }}>
        <span style={{
          width: 38, height: 38, borderRadius: 10,
          background: 'rgba(245,201,119,0.14)', border: '1px solid rgba(245,201,119,0.30)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          color: '#f5c977', fontFamily: '"JetBrains Mono", monospace', fontSize: 18,
          boxShadow: '0 0 14px rgba(245,201,119,0.25)',
        }}>◇</span>
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: 24, fontWeight: 700, color: '#f4f7fb', letterSpacing: '-0.015em' }}>想法</div>
          <div style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 10.5, color: 'rgba(255,255,255,0.45)', letterSpacing: '0.14em', marginTop: 2 }}>22 ITEMS · LAST 30D</div>
        </div>
        <button style={{ padding: '5px 12px', borderRadius: 999, background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.08)', color: 'rgba(255,255,255,0.70)', fontSize: 11, fontFamily: '"JetBrains Mono", monospace', letterSpacing: '0.08em', cursor: 'pointer' }}>按时间 ↓</button>
      </div>

      <div className="eu-noscroll" style={{ flex: 1, overflowY: 'auto', padding: '14px 18px 18px', display: 'flex', flexDirection: 'column', gap: 18 }}>
        {groups.map(g => (
          <div key={g.d} style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
              <span style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 10.5, letterSpacing: '0.22em', color: 'rgba(255,255,255,0.55)', fontWeight: 600 }}>{g.d}</span>
              <span style={{ flex: 1, height: 1, background: 'rgba(255,255,255,0.05)' }}></span>
            </div>
            {g.items.map((it, i) => (
              <div key={i} style={{
                padding: '12px 14px', borderRadius: 14,
                background: 'rgba(245,201,119,0.06)', border: '1px solid rgba(245,201,119,0.18)',
                display: 'flex', flexDirection: 'column', gap: 6,
              }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                  <span style={{ fontSize: 14, fontWeight: 600, color: '#f4f7fb', letterSpacing: '-0.005em', flex: 1, lineHeight: 1.35 }}>{it.t}</span>
                  {it.hasSource && <span style={{ fontSize: 11, color: 'rgba(164,194,255,0.65)' }}>♪</span>}
                </div>
                {it.body && <div style={{ fontSize: 12.5, color: 'rgba(255,255,255,0.70)', lineHeight: 1.6 }}>{it.body}</div>}
                <div style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 10, color: 'rgba(255,255,255,0.45)', letterSpacing: '0.06em' }}>{it.s}</div>
              </div>
            ))}
          </div>
        ))}
      </div>
      <MobileHomeIndicator />
    </div>
  );
}

// ────────────────────────────────────────────────────────────────────────
// 08 · ASSET TYPE — 文件 list (the missing files list)
// ────────────────────────────────────────────────────────────────────────

function CalAssetFiles() {
  const files = [
    { d: '今天 · 5月24日', items: [
      { t: 'flash_20260524_143215.m4a', kind: 'flash', dur: '38s', n: 2, time: '14:32', asr: true },
    ]},
    { d: '昨天 · 5月23日', items: [
      { t: 'flash_20260523_220308.m4a', kind: 'flash', dur: '1:12', n: 2, time: '22:03', asr: true },
      { t: 'flash_20260523_091422.m4a', kind: 'flash', dur: '0:24', n: 1, time: '09:14', asr: true },
    ]},
    { d: '上周', items: [
      { t: 'flash_20260519_154820.m4a', kind: 'flash', dur: '0:46', n: 1, time: '5月19日', asr: true },
      { t: 'meeting_20260517_team_review.m4a', kind: 'meeting', dur: '42:15', n: 6, time: '5月17日', asr: 'pending' },
      { t: 'flash_20260516_191100.m4a', kind: 'flash', dur: '0:32', n: 1, time: '5月16日', asr: true },
      { t: 'flash_20260515_080510.m4a', kind: 'flash', dur: '0:18', n: 0, time: '5月15日', asr: true },
    ]},
  ];
  return (
    <div style={{
      width: '100%', height: '100%',
      background: 'radial-gradient(700px 460px at 20% -10%, rgba(125,211,223,0.10), transparent 60%), #06070d',
      color: '#d4dbe6',
      fontFamily: '"Manrope","Noto Sans SC", system-ui, sans-serif',
      display: 'flex', flexDirection: 'column', overflow: 'hidden',
    }}>
      <MobileStatusBar />
      <div style={{ padding: '4px 18px 12px', display: 'flex', alignItems: 'center', gap: 10 }}>
        <button style={{ width: 32, height: 32, background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.08)', borderRadius: 999, color: 'rgba(255,255,255,0.85)', fontSize: 14, cursor: 'pointer' }}>‹</button>
        <span style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 10.5, color: 'rgba(255,255,255,0.55)', letterSpacing: '0.20em' }}>资产库 →</span>
      </div>
      <div style={{ padding: '0 22px 16px', display: 'flex', alignItems: 'center', gap: 12, borderBottom: '1px solid rgba(255,255,255,0.05)' }}>
        <span style={{
          width: 38, height: 38, borderRadius: 10,
          background: 'rgba(125,211,223,0.14)', border: '1px solid rgba(125,211,223,0.30)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          color: '#7dd3df', fontFamily: '"JetBrains Mono", monospace', fontSize: 18,
          boxShadow: '0 0 14px rgba(125,211,223,0.20)',
        }}>♪</span>
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: 24, fontWeight: 700, color: '#f4f7fb', letterSpacing: '-0.015em' }}>文件</div>
          <div style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 10.5, color: 'rgba(255,255,255,0.45)', letterSpacing: '0.14em', marginTop: 2 }}>7 FILES · 13 LINKED ASSETS</div>
        </div>
        <button style={{ padding: '5px 12px', borderRadius: 999, background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.08)', color: 'rgba(255,255,255,0.70)', fontSize: 11, fontFamily: '"JetBrains Mono", monospace', letterSpacing: '0.08em', cursor: 'pointer' }}>全部 ↓</button>
      </div>

      <div className="eu-noscroll" style={{ flex: 1, overflowY: 'auto', padding: '14px 18px 18px', display: 'flex', flexDirection: 'column', gap: 18 }}>
        {files.map(g => (
          <div key={g.d} style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
              <span style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 10.5, letterSpacing: '0.22em', color: 'rgba(255,255,255,0.55)', fontWeight: 600 }}>{g.d}</span>
              <span style={{ flex: 1, height: 1, background: 'rgba(255,255,255,0.05)' }}></span>
            </div>
            {g.items.map((it, i) => {
              const isMeeting = it.kind === 'meeting';
              return (
                <div key={i} style={{
                  padding: '12px 14px', borderRadius: 12,
                  background: isMeeting ? 'rgba(196,168,255,0.06)' : 'rgba(125,211,223,0.05)',
                  border: `1px solid ${isMeeting ? 'rgba(196,168,255,0.18)' : 'rgba(125,211,223,0.16)'}`,
                  display: 'flex', alignItems: 'center', gap: 12,
                }}>
                  <span style={{
                    width: 30, height: 30, borderRadius: 8,
                    background: 'rgba(0,0,0,0.20)', border: `1px solid ${isMeeting ? 'rgba(196,168,255,0.30)' : 'rgba(125,211,223,0.28)'}`,
                    display: 'flex', alignItems: 'center', justifyContent: 'center',
                    color: isMeeting ? '#c4a8ff' : '#7dd3df', fontSize: 13, flex: '0 0 30px',
                  }}>{isMeeting ? '▶' : '♪'}</span>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
                      <span style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 9.5, letterSpacing: '0.16em', color: isMeeting ? '#c4a8ff' : '#7dd3df', fontWeight: 600 }}>{isMeeting ? 'MEETING' : 'FLASH'}</span>
                      <span style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 10, color: 'rgba(255,255,255,0.50)' }}>{it.dur}</span>
                      {it.asr === 'pending' && <span style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 9.5, color: '#f5c977', letterSpacing: '0.08em' }}>· ASR 转录中</span>}
                      {it.asr === true && <span style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 9.5, color: 'rgba(255,255,255,0.50)', letterSpacing: '0.08em' }}>· {it.n} 资产</span>}
                    </div>
                    <div style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 11.5, color: '#f4f7fb', marginTop: 3, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{it.t}</div>
                  </div>
                  <span style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 10, color: 'rgba(255,255,255,0.45)' }}>{it.time}</span>
                </div>
              );
            })}
          </div>
        ))}
      </div>
      <MobileHomeIndicator />
    </div>
  );
}

function _OldCalAssetLibrary() {
  const filters = [
    { k: '全部', n: 61, active: true },
    { k: '待办', n: 14, dot: '#8ab4ff' },
    { k: '事件', n: 8, dot: '#c4a8ff' },
    { k: '想法', n: 22, dot: '#f5c977' },
    { k: '记账', n: 6, dot: '#86e0a5' },
    { k: '名片', n: 11, dot: '#d4dbe6' },
  ];
  return (
    <div style={{
      width: '100%', height: '100%',
      background: 'radial-gradient(800px 500px at 20% -10%, rgba(111,158,255,0.10), transparent 60%), #06070d',
      color: '#d4dbe6',
      fontFamily: '"Manrope","Noto Sans SC", system-ui, sans-serif',
      display: 'flex', flexDirection: 'column', overflow: 'hidden',
    }}>
      <MobileStatusBar />

      {/* Title */}
      <div style={{ padding: '6px 22px 14px', display: 'flex', alignItems: 'baseline', justifyContent: 'space-between' }}>
        <div>
          <div style={{ fontSize: 26, fontWeight: 700, color: '#f4f7fb', letterSpacing: '-0.02em' }}>资产库</div>
          <div style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 10.5, color: 'rgba(255,255,255,0.45)', letterSpacing: '0.16em', marginTop: 4 }}>61 ITEMS · LAST 30D</div>
        </div>
        <div style={{ display: 'flex', gap: 8 }}>
          <button style={{ width: 32, height: 32, borderRadius: 999, background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.08)', color: 'rgba(255,255,255,0.7)', fontSize: 13, cursor: 'pointer' }}>⌕</button>
          <button style={{ width: 32, height: 32, borderRadius: 999, background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.08)', color: 'rgba(255,255,255,0.7)', fontSize: 13, cursor: 'pointer' }}>⌗</button>
        </div>
      </div>

      {/* Filter chips */}
      <div className="eu-noscroll" style={{ display: 'flex', gap: 6, padding: '0 16px 14px', overflowX: 'auto' }}>
        {filters.map((f, i) => (
          <button key={i} style={{
            display: 'inline-flex', alignItems: 'center', gap: 6,
            padding: '5px 10px', borderRadius: 999,
            background: f.active ? 'rgba(111,158,255,0.14)' : 'rgba(255,255,255,0.03)',
            color: f.active ? '#a4c2ff' : 'rgba(255,255,255,0.62)',
            border: `1px solid ${f.active ? 'rgba(111,158,255,0.32)' : 'transparent'}`,
            fontSize: 11.5, fontWeight: 500, cursor: 'pointer', whiteSpace: 'nowrap',
            fontFamily: '"Manrope", sans-serif',
          }}>
            {f.dot && <span style={{ width: 5, height: 5, borderRadius: 999, background: f.dot, boxShadow: `0 0 5px ${f.dot}` }}></span>}
            {f.k}
            <span style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 10, opacity: 0.62 }}>{f.n}</span>
          </button>
        ))}
      </div>

      {/* Sub-tabs */}
      <div style={{ display: 'flex', gap: 0, padding: '0 22px', borderBottom: '1px solid rgba(255,255,255,0.05)' }}>
        {[
          { k: '最近', active: true },
          { k: '进行中' },
          { k: '已完成' },
          { k: '归档' },
        ].map((t, i) => (
          <button key={i} style={{
            padding: '10px 14px',
            background: 'transparent', border: 'none',
            color: t.active ? '#f4f7fb' : 'rgba(255,255,255,0.50)',
            borderBottom: `2px solid ${t.active ? '#6f9eff' : 'transparent'}`,
            fontSize: 12.5, fontWeight: t.active ? 600 : 400, cursor: 'pointer',
            marginBottom: -1,
          }}>{t.k}</button>
        ))}
      </div>

      {/* List */}
      <div className="eu-noscroll" style={{ flex: 1, overflowY: 'auto', padding: '12px 16px 16px', display: 'flex', flexDirection: 'column', gap: 14 }}>
        <LibGroup label="今天 · 5月24日">
          <LibCard accent="amber" icon="◇" label="IDEA" title="SkillCard 的“沉淀”动画" sub="14:32 · 闪念" hasSource />
          <LibCard accent="blue"  icon="☑" label="TODO" title="财务对账" sub="截止 5月26 14:00" hasSource />
          <LibCard accent="green" icon="¥" label="EXPENSE" title="团队午餐 · 拉面" sub="¥ 68 · 餐饮" amount="¥ 68" />
          <LibCard accent="purple" icon="●" label="EVENT" title="产品评审 · Eureka v2" sub="5月26日 10:00" />
        </LibGroup>

        <LibGroup label="昨天 · 5月23日">
          <LibCard accent="amber" icon="◇" label="IDEA" title="语音输入的容错策略" sub="22:03 · 闪念" hasSource />
          <LibCard accent="neutral" icon="◯" label="CONTACT" title="林一帆 · Aurora Capital" sub="投资经理" />
          <LibCard accent="blue" icon="☑" label="TODO" title="回 Linus 关于硬件协议的邮件" sub="截止 5月25" />
        </LibGroup>
      </div>

      <MobileHomeIndicator />
    </div>
  );
}

function LibGroup({ label, children }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
      <div style={{
        position: 'sticky', top: 0, zIndex: 1,
        padding: '2px 0 6px',
        background: 'linear-gradient(to bottom, #06070d 80%, transparent)',
        display: 'flex', alignItems: 'center', gap: 10,
      }}>
        <span style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 10, letterSpacing: '0.22em', color: 'rgba(255,255,255,0.55)', fontWeight: 600, textTransform: 'uppercase' }}>{label}</span>
        <span style={{ flex: 1, height: 1, background: 'rgba(255,255,255,0.05)' }}></span>
      </div>
      {children}
    </div>
  );
}

function LibCard({ accent, icon, label, title, sub, amount, hasSource }) {
  const ac = {
    blue:    { fg: '#8ab4ff', bg: 'rgba(138,180,255,0.10)', edge: 'rgba(138,180,255,0.24)' },
    amber:   { fg: '#f5c977', bg: 'rgba(245,201,119,0.10)', edge: 'rgba(245,201,119,0.24)' },
    green:   { fg: '#86e0a5', bg: 'rgba(134,224,165,0.10)', edge: 'rgba(134,224,165,0.24)' },
    purple:  { fg: '#c4a8ff', bg: 'rgba(196,168,255,0.10)', edge: 'rgba(196,168,255,0.24)' },
    neutral: { fg: '#d4dbe6', bg: 'rgba(212,219,230,0.05)', edge: 'rgba(212,219,230,0.16)' },
  }[accent];
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 12,
      padding: '12px 14px', borderRadius: 14,
      background: ac.bg, border: `1px solid ${ac.edge}`,
    }}>
      <span style={{
        width: 28, height: 28, borderRadius: 8, flex: '0 0 28px',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        background: 'rgba(0,0,0,0.18)', border: `1px solid ${ac.edge}`,
        color: ac.fg, fontFamily: '"JetBrains Mono", monospace', fontSize: 13,
      }}>{icon}</span>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <span style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 9.5, letterSpacing: '0.18em', color: ac.fg, fontWeight: 600 }}>{label}</span>
          {hasSource && <span style={{ fontSize: 9.5, color: 'rgba(164,194,255,0.65)', fontFamily: '"JetBrains Mono", monospace', letterSpacing: '0.04em' }}>♪</span>}
        </div>
        <div style={{ fontSize: 13.5, color: '#f4f7fb', fontWeight: 500, marginTop: 2, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{title}</div>
        <div style={{ fontSize: 11, color: 'rgba(255,255,255,0.55)', fontFamily: '"JetBrains Mono", monospace', letterSpacing: '0.04em', marginTop: 2 }}>{sub}</div>
      </div>
      {amount && <span style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 16, fontWeight: 600, color: ac.fg }}>{amount}</span>}
    </div>
  );
}

// ────────────────────────────────────────────────────────────────────────
// 05 · EVENT EDITOR — colored top + time scrub
// ────────────────────────────────────────────────────────────────────────

function CalEditor() {
  return (
    <div style={{
      width: '100%', height: '100%',
      background: '#06070d', color: '#d4dbe6',
      fontFamily: '"Manrope","Noto Sans SC", system-ui, sans-serif',
      display: 'flex', flexDirection: 'column', overflow: 'hidden',
    }}>
      <MobileStatusBar color="#ffffff" />

      {/* Colored top panel ~55% of height */}
      <div style={{
        flex: '0 0 64%',
        background: 'linear-gradient(155deg, #4a3a8f 0%, #2a1f6a 100%)',
        position: 'relative',
        display: 'flex', flexDirection: 'column',
        padding: '8px 24px 22px',
        overflow: 'hidden',
      }}>
        <div style={{ position: 'absolute', top: -60, right: -40, width: 240, height: 240, borderRadius: 999, background: 'radial-gradient(circle, rgba(196,168,255,0.30), transparent 70%)' }}></div>

        {/* Title input area */}
        <div style={{ position: 'relative', flex: 1, display: 'flex', flexDirection: 'column' }}>
          <div style={{ marginTop: 6, fontSize: 11, color: 'rgba(255,255,255,0.55)', fontFamily: '"JetBrains Mono", monospace', letterSpacing: '0.18em', textAlign: 'right' }}>EVENT</div>
          <div style={{ marginTop: 18, fontSize: 26, fontWeight: 700, color: '#ffffff', letterSpacing: '-0.015em', lineHeight: 1.3 }}>
            产品评审 · Eureka v2<span style={{
              display: 'inline-block', width: 2, height: 28, background: '#ffffff', marginLeft: 4, verticalAlign: 'middle', animation: 'eu-blink 1s infinite',
            }}></span>
          </div>
          <div style={{ marginTop: 4, fontSize: 13, color: 'rgba(255,255,255,0.70)' }}>会议室 B</div>

          <div style={{ flex: 1 }}></div>

          {/* Day label */}
          <div style={{ textAlign: 'center', marginTop: 8 }}>
            <div style={{ fontSize: 20, fontWeight: 700, letterSpacing: '0.18em', color: '#ffffff', textShadow: '0 0 20px rgba(255,255,255,0.30)' }}>周一</div>
            <div style={{ fontSize: 11, color: 'rgba(255,255,255,0.55)', fontFamily: '"JetBrains Mono", monospace', letterSpacing: '0.20em', marginTop: 4 }}>MAY 26</div>
          </div>

          {/* Time range */}
          <div style={{ marginTop: 18, display: 'flex', alignItems: 'baseline', justifyContent: 'center', gap: 16 }}>
            <span style={{ fontSize: 26, fontWeight: 600, color: '#ffffff', fontFamily: '"JetBrains Mono", monospace', letterSpacing: '0.02em' }}>10:00</span>
            <span style={{ color: 'rgba(255,255,255,0.55)', fontSize: 18 }}>→</span>
            <span style={{ fontSize: 26, fontWeight: 600, color: 'rgba(255,255,255,0.85)', fontFamily: '"JetBrains Mono", monospace', letterSpacing: '0.02em' }}>11:00</span>
          </div>

          {/* Time scrub bar */}
          <div style={{ marginTop: 14, height: 24, background: 'rgba(255,255,255,0.10)', borderRadius: 4, position: 'relative', overflow: 'hidden' }}>
            <div style={{ position: 'absolute', top: 0, left: '40%', right: '54%', bottom: 0, background: 'rgba(255,255,255,0.30)', borderRadius: 4 }}></div>
            {/* tick marks */}
            <div style={{ position: 'absolute', inset: 0, display: 'flex' }}>
              {Array(48).fill().map((_, i) => (
                <div key={i} style={{ flex: 1, borderRight: i < 47 ? '1px solid rgba(255,255,255,0.10)' : 'none' }}></div>
              ))}
            </div>
          </div>

          {/* Mode tabs */}
          <div style={{ marginTop: 14, display: 'flex', justifyContent: 'space-around', alignItems: 'center' }}>
            {[
              { k: 'SET TIME', active: true },
              { k: 'ALL DAY' },
              { k: 'MULTI-DAY' },
            ].map(t => (
              <div key={t.k} style={{
                fontFamily: '"JetBrains Mono", monospace', fontSize: 10, letterSpacing: '0.16em',
                color: t.active ? '#ffffff' : 'rgba(255,255,255,0.50)',
                fontWeight: t.active ? 700 : 400,
                paddingBottom: 6,
                borderBottom: `2px solid ${t.active ? '#ffffff' : 'transparent'}`,
              }}>{t.k}</div>
            ))}
          </div>
        </div>
      </div>

      {/* Toolbar */}
      <div style={{ background: '#0b0d14', padding: '12px 24px', display: 'flex', alignItems: 'center', justifyContent: 'space-around', borderBottom: '1px solid rgba(255,255,255,0.05)' }}>
        {['✕', '≡', '◎', '◯', '⌗ → ✓'].map((g, i) => (
          <div key={i} style={{
            width: 36, height: 36, borderRadius: 8,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            color: i === 0 ? 'rgba(255,255,255,0.55)' : (i === 4 ? '#6f9eff' : 'rgba(255,255,255,0.85)'),
            fontSize: i === 4 ? 11 : 16,
            fontFamily: i === 4 ? '"JetBrains Mono", monospace' : 'inherit',
            background: i === 4 ? 'rgba(111,158,255,0.12)' : 'transparent',
            border: i === 4 ? '1px solid rgba(111,158,255,0.30)' : '1px solid transparent',
          }}>{g}</div>
        ))}
      </div>

      {/* Recent events tray */}
      <div style={{ flex: 1, padding: '14px 22px', overflow: 'hidden' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 10 }}>
          <span style={{ fontSize: 10.5, fontFamily: '"JetBrains Mono", monospace', letterSpacing: '0.22em', color: 'rgba(255,255,255,0.55)', fontWeight: 600 }}>最近事件</span>
          <span style={{ fontSize: 12, color: 'rgba(255,255,255,0.40)' }}>✕</span>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 0 }}>
          {[
            { c: '#ec6a83', t: '客户拜访 · 林一帆', sub: '5月29日 16:00' },
            { c: '#f5c977', t: 'demo 脚本草稿', sub: '5月22日 · 想法' },
            { c: '#f5c977', t: '硬件断流问题分析', sub: '5月21日 · 想法' },
            { c: '#ec6a83', t: '设计评审', sub: '5月22日 14:00' },
          ].map((it, i) => (
            <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '9px 0', borderBottom: i < 3 ? '1px solid rgba(255,255,255,0.04)' : 'none' }}>
              <span style={{ width: 3, height: 22, background: it.c }}></span>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 13.5, color: '#d4dbe6', fontWeight: 500, marginBottom: 2 }}>{it.t}</div>
                <div style={{ fontSize: 11, color: 'rgba(255,255,255,0.40)', fontFamily: '"JetBrains Mono", monospace', letterSpacing: '0.04em' }}>{it.sub}</div>
              </div>
            </div>
          ))}
        </div>
      </div>

      <MobileHomeIndicator />
    </div>
  );
}

// ────────────────────────────────────────────────────────────────────────
// 06 · FLOW — annotated swipe transitions between views
// ────────────────────────────────────────────────────────────────────────

function CalFlow() {
  const phoneW = 140, phoneH = 280;
  const phones = [
    { x: 80,  y: 90,  label: 'SCHEDULE', sub: '默认 · 纵向时间流', detail: '颜色密度 = 信息密度' },
    { x: 290, y: 90,  label: 'MONTH',    sub: '右滑切换',         detail: '点圆点 → 选中日' },
    { x: 500, y: 90,  label: 'YEAR',     sub: '继续右滑',         detail: '点月份 → 回到月视图' },
    { x: 290, y: 410, label: 'DAY DETAIL', sub: '在 SCHEDULE 点某日', detail: '全屏铺色 · 当日所有资产' },
    { x: 500, y: 410, label: 'EVENT EDITOR', sub: '点 + 或某事件',   detail: '上半铺色 · 时间 scrub · 工具栏' },
  ];
  return (
    <div style={{
      width: '100%', height: '100%',
      background: 'radial-gradient(900px 600px at 30% 30%, rgba(82,128,200,0.12), transparent 60%), #0b1220',
      color: '#d4dbe6',
      fontFamily: '"Manrope","Noto Sans SC", system-ui, sans-serif',
      padding: 36, boxSizing: 'border-box', overflow: 'hidden', position: 'relative',
    }}>
      {/* Title */}
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 14, marginBottom: 14 }}>
        <div style={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 10.5, letterSpacing: '0.22em', color: '#a4c2ff' }}>NAVIGATION FLOW</div>
        <div style={{ flex: 1, height: 1, background: 'rgba(255,255,255,0.10)' }}></div>
      </div>
      <div style={{ fontSize: 24, fontWeight: 700, color: '#f4f7fb', letterSpacing: '-0.015em', maxWidth: 720, lineHeight: 1.35, marginBottom: 6 }}>
        日历是 5 个状态之间的滑动 — 颜色和滑动方向是唯一的导航。
      </div>
      <div style={{ fontSize: 12.5, color: '#9aa6b8', maxWidth: 640, lineHeight: 1.6, marginBottom: 8 }}>
        默认进入 SCHEDULE。右滑 → MONTH → YEAR（缩放视角）。在 SCHEDULE 点某日 → DAY DETAIL。点 + 或某事件 → EVENT EDITOR。所有过渡 280ms slide + crossfade。
      </div>

      <svg viewBox="0 0 680 760" style={{ width: '100%', height: 'auto', maxHeight: 'calc(100% - 140px)' }}>
        {/* Connection arrows */}
        <defs>
          <marker id="arrow" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto">
            <path d="M0,0 L10,5 L0,10 Z" fill="#6f9eff" />
          </marker>
          <linearGradient id="phoneG" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="rgba(255,255,255,0.05)" />
            <stop offset="100%" stopColor="rgba(255,255,255,0.02)" />
          </linearGradient>
        </defs>

        {/* arrows between phones */}
        <g stroke="#6f9eff" strokeWidth="1.5" fill="none" strokeDasharray="4 4" opacity="0.7">
          <path d={`M ${80 + phoneW + 4} 230 L ${290 - 4} 230`} markerEnd="url(#arrow)" />
          <path d={`M ${290 + phoneW + 4} 230 L ${500 - 4} 230`} markerEnd="url(#arrow)" />
          {/* schedule → day detail */}
          <path d={`M ${80 + phoneW/2} ${90 + phoneH} Q ${80 + phoneW/2} ${380}, ${290 + phoneW/2} ${410}`} markerEnd="url(#arrow)" />
          {/* day detail → event editor */}
          <path d={`M ${290 + phoneW + 4} 550 L ${500 - 4} 550`} markerEnd="url(#arrow)" />
        </g>

        {/* Swipe labels */}
        <g fontFamily="'JetBrains Mono', monospace" fontSize="10" letterSpacing="2" fill="#a4c2ff">
          <text x={180} y={220} textAnchor="start">SWIPE →</text>
          <text x={390} y={220} textAnchor="start">SWIPE →</text>
          <text x={150} y={388} textAnchor="start" fill="#c4a8ff">TAP DAY ↓</text>
          <text x={390} y={540} textAnchor="start" fill="#c4a8ff">TAP + ↗</text>
        </g>

        {/* Phone frames */}
        {phones.map((p, i) => {
          // Inner content visual: small representation of each view
          return (
            <g key={p.label} transform={`translate(${p.x},${p.y})`}>
              <rect width={phoneW} height={phoneH} rx="22" fill="url(#phoneG)" stroke="rgba(255,255,255,0.12)" strokeWidth="1" />
              {/* Status bar */}
              <rect x={8} y={8} width={phoneW - 16} height={3} rx="1.5" fill="rgba(255,255,255,0.15)" />
              {/* Content stub for each */}
              {p.label === 'SCHEDULE' && (
                <g>
                  <rect x={10} y={26} width={20} height={50} rx="3" fill="rgba(255,255,255,0.06)" />
                  <rect x={34} y={26} width={phoneW - 44} height={50} rx="6" fill="rgba(156,128,240,0.32)" />
                  <rect x={10} y={82} width={20} height={28} rx="3" fill="rgba(255,255,255,0.06)" />
                  <rect x={34} y={82} width={phoneW - 44} height={28} rx="6" fill="rgba(255,255,255,0.04)" />
                  <rect x={10} y={116} width={20} height={68} rx="3" fill="rgba(255,255,255,0.06)" />
                  <rect x={34} y={116} width={phoneW - 44} height={68} rx="6" fill="rgba(111,158,255,0.28)" />
                  <rect x={10} y={190} width={20} height={42} rx="3" fill="rgba(255,255,255,0.06)" />
                  <rect x={34} y={190} width={phoneW - 44} height={42} rx="6" fill="rgba(156,128,240,0.20)" />
                  <circle cx={phoneW - 22} cy={phoneH - 32} r="11" fill="#6f9eff" />
                </g>
              )}
              {p.label === 'MONTH' && (
                <g>
                  <text x={14} y={36} fontSize="13" fill="#a4c2ff" fontWeight="700" letterSpacing="1.5">5月</text>
                  {Array(35).fill().map((_, i) => {
                    const col = i % 7, row = Math.floor(i / 7);
                    const isToday = i === 24;
                    const isEvent = [10, 12, 17, 20, 24, 25, 28].includes(i);
                    return (
                      <circle key={i}
                        cx={14 + col * 18}
                        cy={60 + row * 18}
                        r="6"
                        fill={isToday ? '#ffffff' : (isEvent ? 'rgba(156,128,240,0.30)' : 'transparent')}
                        stroke={isEvent && !isToday ? 'rgba(196,168,255,0.40)' : 'none'}
                      />
                    );
                  })}
                  <line x1={10} x2={phoneW - 10} y1={200} y2={200} stroke="rgba(255,255,255,0.10)" />
                  <rect x={14} y={210} width={50} height={4} rx="1" fill="rgba(255,255,255,0.35)" />
                  <rect x={14} y={220} width={phoneW - 28} height={3} rx="1.5" fill="rgba(255,255,255,0.20)" />
                  <rect x={14} y={228} width={phoneW - 50} height={3} rx="1.5" fill="rgba(255,255,255,0.15)" />
                  {/* edge strip */}
                  {[0,1,2,3,4].map(k => <rect key={k} x={phoneW - 4} y={50 + k*40} width={3} height={36} fill={['#9c80f0','#6f9eff','#86e0a5','#f5c977','#ec6a83'][k]} opacity="0.6" />)}
                </g>
              )}
              {p.label === 'YEAR' && (
                <g>
                  <text x={14} y={38} fontSize="20" fill="#a4c2ff" fontWeight="700">2026</text>
                  {Array(12).fill().map((_, i) => {
                    const col = i % 3, row = Math.floor(i / 3);
                    const isCurrent = i === 4;
                    return (
                      <g key={i} transform={`translate(${10 + col * 42}, ${52 + row * 50})`}>
                        <rect width={38} height={44} rx="3" fill={isCurrent ? 'rgba(156,128,240,0.10)' : 'transparent'} stroke={isCurrent ? 'rgba(196,168,255,0.30)' : 'transparent'} />
                        <text x={3} y={9} fontSize="6" fill={isCurrent ? '#a4c2ff' : 'rgba(255,255,255,0.55)'} fontWeight="700">{(i + 1) + '月'}</text>
                        {Array(6).fill().map((__, r) => (
                          <rect key={r} x={3} y={14 + r * 4.5} width={32} height={2.5} rx="0.5" fill="rgba(255,255,255,0.12)" />
                        ))}
                      </g>
                    );
                  })}
                </g>
              )}
              {p.label === 'DAY DETAIL' && (
                <g>
                  <rect x={1} y={1} width={phoneW - 2} height={phoneH - 2} rx="21" fill="rgba(74,58,143,0.60)" />
                  <text x={phoneW / 2} y={36} textAnchor="middle" fontSize="11" fill="#ffffff" fontWeight="700" letterSpacing="3">周一</text>
                  <text x={phoneW / 2} y={50} textAnchor="middle" fontSize="7" fill="rgba(255,255,255,0.7)" fontFamily="'JetBrains Mono', monospace" letterSpacing="2">MAY 26</text>
                  <rect x={14} y={70} width={phoneW - 28} height={50} rx="6" fill="rgba(255,255,255,0.10)" />
                  <rect x={14} y={130} width={phoneW - 28} height={36} rx="6" fill="rgba(255,255,255,0.10)" />
                  <rect x={14} y={176} width={phoneW - 28} height={48} rx="6" fill="rgba(0,0,0,0.20)" />
                </g>
              )}
              {p.label === 'EVENT EDITOR' && (
                <g>
                  <rect x={1} y={1} width={phoneW - 2} height={(phoneH - 2) * 0.6} rx="21" fill="rgba(74,58,143,0.60)" />
                  <text x={phoneW / 2} y={64} textAnchor="middle" fontSize="9" fill="#fff" fontWeight="700" letterSpacing="2">产品评审</text>
                  <text x={phoneW / 2} y={106} textAnchor="middle" fontSize="10" fill="#fff" fontWeight="700" letterSpacing="3">周一</text>
                  <text x={phoneW / 2} y={130} textAnchor="middle" fontSize="11" fill="#fff" fontFamily="'JetBrains Mono', monospace">10:00 → 11:00</text>
                  <rect x={20} y={138} width={phoneW - 40} height={8} rx="2" fill="rgba(255,255,255,0.15)" />
                  <rect x={20 + (phoneW - 40) * 0.4} y={138} width={(phoneW - 40) * 0.06} height={8} rx="2" fill="rgba(255,255,255,0.55)" />
                  {/* toolbar */}
                  <rect x={1} y={(phoneH * 0.6)} width={phoneW - 2} height={26} fill="#0b0d14" />
                  {Array(5).fill().map((_, k) => <circle key={k} cx={20 + k * 25} cy={(phoneH * 0.6) + 13} r="4" fill="rgba(255,255,255,0.30)" />)}
                  {/* list */}
                  <rect x={10} y={(phoneH * 0.6) + 36} width={phoneW - 20} height={3} rx="1" fill="rgba(255,255,255,0.25)" />
                  <rect x={10} y={(phoneH * 0.6) + 46} width={phoneW - 40} height={3} rx="1" fill="rgba(255,255,255,0.12)" />
                </g>
              )}

              {/* label */}
              <text x={phoneW / 2} y={phoneH + 22} textAnchor="middle" fontFamily="'JetBrains Mono', monospace" fontSize="10" letterSpacing="2" fill="#a4c2ff" fontWeight="700">{p.label}</text>
              <text x={phoneW / 2} y={phoneH + 38} textAnchor="middle" fontSize="10" fill="#9aa6b8">{p.sub}</text>
              <text x={phoneW / 2} y={phoneH + 52} textAnchor="middle" fontSize="9" fill="#6c7689">{p.detail}</text>
            </g>
          );
        })}
      </svg>
    </div>
  );
}

Object.assign(window, {
  CalSchedule, CalMonth, CalYear, CalDay, CalEditor, CalFlow,
  CalAssetDetail, CalAssetLibrary, CalAssetIdeas, CalAssetFiles,
});
