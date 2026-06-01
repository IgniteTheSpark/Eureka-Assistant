// eureka-lib.jsx — shared demo data, formatters, and lightweight icons
// Used by all three variation files. All exports go on window.

// ────────────────────────────────────────────────────────────────────────
// Demo data — realistic Eureka asset payloads
// ────────────────────────────────────────────────────────────────────────

const DEMO_ASSETS = [
  {
    id: 'a1',
    skill: 'todo',
    accent: 'blue',
    icon: '☑',
    payload: { content: '准备周三产品评审的 demo 脚本', due_date: '今天 18:00', status: 'open' },
    layout: 'horizontal',
    time: '14:32',
    transcript: '...对 然后周三那个评审 我得提前把脚本写好...',
  },
  {
    id: 'a2',
    skill: 'event',
    accent: 'purple',
    icon: '●',
    payload: { title: '产品评审 · Eureka v2', start_at: '5月26日 10:00', duration: '60 min', location: '会议室 B' },
    layout: 'horizontal',
    time: '14:33',
  },
  {
    id: 'a3',
    skill: 'idea',
    accent: 'amber',
    icon: '◇',
    payload: { title: 'SkillCard 的"沉淀"动画', content: '能不能让卡片从 chat 气泡里"析出"，像结晶一样飘到右侧资产栏。视觉上要有"AI 在帮我整理"的感受。' },
    layout: 'stacked',
    time: '11:08',
  },
  {
    id: 'a4',
    skill: 'expense',
    accent: 'green',
    icon: '¥',
    payload: { amount: '¥ 68', description: '团队午餐 · 拉面', category: '餐饮', date: '今天' },
    layout: 'horizontal',
    time: '12:47',
  },
  {
    id: 'a5',
    skill: 'contact',
    accent: 'neutral',
    icon: '◯',
    payload: { name: '林一帆', company: 'Aurora Capital', title: '投资经理', phone: '138 ···· 4827' },
    layout: 'horizontal',
    time: '昨天 16:21',
  },
  {
    id: 'a6',
    skill: 'todo',
    accent: 'blue',
    icon: '☑',
    payload: { content: '回复 Linus 关于硬件协议的邮件', due_date: '明天', status: 'open' },
    layout: 'horizontal',
    time: '昨天 09:14',
  },
  {
    id: 'a7',
    skill: 'todo',
    accent: 'red',
    icon: '!',
    payload: { content: '修复硬件录音断流问题', due_date: '已逾期 2 天', status: 'overdue' },
    layout: 'horizontal',
    time: '昨天',
  },
  {
    id: 'a8',
    skill: 'idea',
    accent: 'amber',
    icon: '◇',
    payload: { title: '语音输入的容错', content: 'Web Speech API 在嘈杂环境下识别会跳词，要不要做一个"轻确认"步骤——转录完之后用户能快速划掉错词？' },
    layout: 'stacked',
    time: '昨天 22:03',
  },
];

// ────────────────────────────────────────────────────────────────────────
// Chat transcript — mimics SSE token stream + tool_call + precipitate
// ────────────────────────────────────────────────────────────────────────

const DEMO_CHAT = [
  { role: 'user', text: '帮我加个明天上午 10 点的产品评审，60 分钟，B 会议室' },
  {
    role: 'agent',
    text: '已为你创建事件。',
    toolCall: { name: 'create_asset', skill: 'event' },
    card: { ref: 'a2' },
  },
  {
    role: 'user',
    voice: {
      filename: 'flash_20260524_143215.m4a',
      duration: '0:38',
      time: '14:32',
      // 40 amplitude points for the waveform
      wave: [0.42,0.58,0.34,0.72,0.50,0.66,0.40,0.62,0.88,0.54,0.32,0.70,0.48,0.60,0.42,0.78,0.52,0.34,0.62,0.44,0.70,0.52,0.40,0.58,0.82,0.42,0.50,0.32,0.60,0.50,0.40,0.32,0.50,0.42,0.60,0.50,0.34,0.42,0.50,0.30],
      transcript: '顺便提醒我周三之前把 demo 脚本写好，重点突出硬件断网恢复那块。还有，找时间跟林一帆约个咖啡，谈他上次说的那个合作。',
    },
  },
  {
    role: 'agent',
    text: '从这段录音里我抓到两件事 —— 一个待办、一个待安排的会面。已经分别建好了。',
    toolCall: { name: 'create_assets', skill: 'todo · event', batch: 2 },
    card: { ref: 'a1' },
  },
  { role: 'user', text: '我最近一直在想：硬件断网时怎么保证录音不丢？' },
  {
    role: 'agent',
    streaming: true,
    text: '硬件断网时录音保护可以分两层。第一层在设备端缓存——所有录音先写本地 NAND，分片 60s。第二层是后端去重——服务端用录音段的指纹（开头几秒哈希）合并，避免双写。这套设计意味着用户感知不到断网。',
    precipitate: true,
  },
];

// ────────────────────────────────────────────────────────────────────────
// Calendar — current month with sparse events
// ────────────────────────────────────────────────────────────────────────

const CAL = {
  monthLabel: '5月 · 2026',
  weekdays: ['一', '二', '三', '四', '五', '六', '日'],
  // grid: 35 cells starting from week-start. Each entry has day number (0=outside) and events.
  cells: (() => {
    // May 2026: 1 = Friday. We'll start week on Monday.
    // Monday-Sunday layout — May 1 (Fri) is column 5 of row 1.
    const days = [];
    // row 1
    days.push({ d: 28, out: true }, { d: 29, out: true }, { d: 30, out: true }, { d: 1 }, { d: 2 }, { d: 3 }, { d: 4 });
    // row 2
    days.push({ d: 5 }, { d: 6, events: [{ t: '设计评审', accent: 'purple', time: '14:00' }] }, { d: 7 }, { d: 8 }, { d: 9 }, { d: 10 }, { d: 11 });
    // row 3
    days.push(
      { d: 12 },
      { d: 13, events: [{ t: '一对一 · Lin', accent: 'purple', time: '10:00' }, { t: '体检', accent: 'purple', time: '15:30' }] },
      { d: 14 },
      { d: 15, events: [{ t: '提交方案', accent: 'blue', todo: true }] },
      { d: 16 },
      { d: 17 },
      { d: 18 },
    );
    // row 4
    days.push(
      { d: 19 },
      { d: 20 },
      { d: 21, events: [{ t: '客户拜访 · 林一帆', accent: 'purple', time: '16:00' }] },
      { d: 22 },
      { d: 23 },
      { d: 24, today: true, events: [{ t: '团队午餐', accent: 'purple', time: '12:30' }, { t: '回 Linus 邮件', accent: 'blue', todo: true }, { t: '准备 demo', accent: 'blue', todo: true }] },
      { d: 25 },
    );
    // row 5
    days.push(
      { d: 26, events: [{ t: '产品评审 · Eureka v2', accent: 'purple', time: '10:00' }, { t: '财务对账', accent: 'green', todo: true }] },
      { d: 27, events: [{ t: 'demo 演练', accent: 'purple', time: '15:00' }] },
      { d: 28 },
      { d: 29 },
      { d: 30 },
      { d: 31 },
      { d: 1, out: true },
    );
    return days;
  })(),
};

// ────────────────────────────────────────────────────────────────────────
// Timeline groups
// ────────────────────────────────────────────────────────────────────────

const TIMELINE = [
  {
    label: '今天',
    sub: '5月24日 · 周日',
    items: ['a4', 'a2', 'a1', 'a3'],
  },
  {
    label: '昨天',
    sub: '5月23日 · 周六',
    items: ['a8', 'a5', 'a6', 'a7'],
  },
];

// ────────────────────────────────────────────────────────────────────────
// Skill registry for the Add Skill wizard / library
// ────────────────────────────────────────────────────────────────────────

const SKILLS = [
  { name: 'todo', display: '待办', icon: '☑', accent: 'blue', count: 14 },
  { name: 'event', display: '事件', icon: '●', accent: 'purple', count: 8 },
  { name: 'idea', display: '想法', icon: '◇', accent: 'amber', count: 22 },
  { name: 'expense', display: '记账', icon: '¥', accent: 'green', count: 6 },
  { name: 'contact', display: '名片', icon: '◯', accent: 'neutral', count: 11 },
];

const ACCENT_ROLES = [
  { key: 'blue', role: '默认 / 待办', glyph: '☑' },
  { key: 'amber', role: '想法 / 提醒', glyph: '◇' },
  { key: 'green', role: '财务 / 正向', glyph: '¥' },
  { key: 'red', role: '紧急 / 逾期', glyph: '!' },
  { key: 'purple', role: '事件 / 日历', glyph: '●' },
  { key: 'gray', role: '次要', glyph: '·' },
  { key: 'neutral', role: '无语义', glyph: '◯' },
];

// ────────────────────────────────────────────────────────────────────────
// Helper: render a vertical legend swatch — used in foundation artboards
// ────────────────────────────────────────────────────────────────────────

function Swatch({ color, label, sub, mono, txt = '#fff', border = 'transparent', fontMono }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
      <div style={{
        height: 56, borderRadius: 8, background: color,
        border: `1px solid ${border}`,
        display: 'flex', alignItems: 'flex-end', padding: 8,
        color: txt, fontFamily: fontMono, fontSize: 10, letterSpacing: '0.04em',
      }}>{mono}</div>
      <div style={{ fontSize: 11, fontWeight: 600, letterSpacing: '0.02em' }}>{label}</div>
      <div style={{ fontSize: 10, opacity: 0.6 }}>{sub}</div>
    </div>
  );
}

// ────────────────────────────────────────────────────────────────────────
// Helper: section header inside an artboard
// ────────────────────────────────────────────────────────────────────────

function ArtboardSection({ label, num, color = 'currentColor', fontMono, children, style }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 14, ...style }}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, fontFamily: fontMono, fontSize: 10, letterSpacing: '0.18em', textTransform: 'uppercase', opacity: 0.55 }}>
        <span>{num}</span>
        <span style={{ flex: '0 0 18px', height: 1, background: 'currentColor', opacity: 0.4 }}></span>
        <span>{label}</span>
      </div>
      {children}
    </div>
  );
}

// ────────────────────────────────────────────────────────────────────────
// Helper: small chip
// ────────────────────────────────────────────────────────────────────────

function Chip({ children, color, bg, border, fontMono, mono }) {
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 4,
      padding: '2px 7px', borderRadius: 999,
      background: bg, color, border: `1px solid ${border || 'transparent'}`,
      fontSize: 10.5, fontWeight: 500, letterSpacing: '0.01em',
      fontFamily: mono ? fontMono : 'inherit',
      whiteSpace: 'nowrap',
    }}>{children}</span>
  );
}

Object.assign(window, {
  DEMO_ASSETS, DEMO_CHAT, CAL, TIMELINE, SKILLS, ACCENT_ROLES,
  EuSwatch: Swatch, EuArtboardSection: ArtboardSection, EuChip: Chip,
});
