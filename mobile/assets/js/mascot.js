/* mascot.js — Reka: the Eureka mark abstracted into a glossy jelly creature.
 * DNA from the logo: a gradient jelly body + a glowing forehead EMBLEM (replaceable / random).
 * Slots: [skin = colorway] [emblem = forehead mark] [eyes] [mouth] [two hands→items] [head accessory].
 * Requires pixel.js. */
(function (global) {
  const P = global.Pixel;

  // base palette: features + items + accessories (body ramp + emblem injected per-skin)
  const BASE_PAL = {
    '.': null,
    'E': '#101c30',  // eye
    'W': '#ffffff',  // eye glint
    'M': '#101c30',  // mouth
    't': '#ff9bb0',  // tongue
    'S': '#ffffff',  // emblem core
    // accessories / items
    'H': '#8a5a34', 'h': '#b07c44', 'k': '#5b3c22',
    'r': '#e85d6b', 'y': '#f7c948', 'c': '#7ad7c6', 'p': '#bb9af7',
    'w': '#ffffff', 'l': '#cfd6e2', 'a': '#8a93a3', 'e': '#27314a',
    'q': '#ffd24a', 'm': '#bfe3ff', 'L': '#aeb8c8', 'z': '#223153',
    'v': '#5bbf5a', 'f': '#f48fb1', 'u': '#e07a86', 'o': '#c98a4e',
  };

  // ── colorways (jelly) — top light → bottom saturated; not just blue-green ──
  const SKINS = {
    aurora:  { label: '极光', ramp: ['#e6fff2', '#9af0cf', '#56d6c6', '#46b6e8', '#3a86e0', '#2f63c4'], O: '#15324f', hi: '#f4fffb' },
    grape:   { label: '葡萄', ramp: ['#f4e9ff', '#dab8ff', '#bb8cf7', '#9a5fe8', '#7d3fd0', '#5c2bae'], O: '#2c1a52', hi: '#fbf3ff' },
    coral:   { label: '珊瑚', ramp: ['#ffeee6', '#ffc4ad', '#ff9d7e', '#f77662', '#e85566', '#c23c58'], O: '#4a1f2a', hi: '#fff6f1' },
    lime:    { label: '青柠', ramp: ['#f6ffe2', '#d8f78e', '#aee85c', '#86d046', '#5fb040', '#46902f'], O: '#243f12', hi: '#fbffee' },
    ocean:   { label: '海洋', ramp: ['#e6f9ff', '#a8e6ff', '#6fcdf7', '#46a8ee', '#3a82e0', '#2f5fc4'], O: '#143150', hi: '#f2fdff' },
    bubble:  { label: '泡泡糖', ramp: ['#ffe9f6', '#ffb6e2', '#f78cd2', '#e85fbd', '#d03fa2', '#ad2b86'], O: '#4a1640', hi: '#fff2fa' },
    ember:   { label: '余烬', ramp: ['#fff2db', '#ffd28f', '#ffab5a', '#f7864e', '#e85f3f', '#c43f3f'], O: '#4a2418', hi: '#fff8ee' },
    mint:    { label: '薄荷', ramp: ['#e6fff2', '#a8ffd8', '#6ff0c0', '#46e0b0', '#3ac49a', '#2f9c80'], O: '#13402f', hi: '#f2fffa' },
    sky:     { label: '晴空', ramp: ['#eef6ff', '#c0dcff', '#94bcff', '#6f9eff', '#5278e8', '#3f57c4'], O: '#1a2750', hi: '#f7faff' },
    gold:    { label: '蜜金', ramp: ['#fff8e0', '#ffe79a', '#ffd45a', '#f7b63f', '#e8902f', '#c46f2f'], O: '#4a3416', hi: '#fffbee' },
  };
  const SKIN_KEYS = Object.keys(SKINS);

  // ── canvas geometry ──
  const CW = 26, CH = 22;
  const BOX = 6, BOY = 5;
  const CENTER = BOX + 7;

  const MASK = [
    '...########...',
    '.############.',
    '##############',
    '##############',
    '##############',
    '##############',
    '##############',
    '##############',
    '##############',
    '##############',
    '##############',
    '##############',
    '.############.',
    '...########...',
  ];

  function isBody(x, y) {
    if (y < 0 || y >= MASK.length) return false;
    const r = MASK[y];
    if (x < 0 || x >= r.length) return false;
    return r[x] === '#';
  }

  // map a body row (0..13) → ramp index (0..5)
  function zone(y) {
    if (y <= 1) return 0;
    if (y <= 3) return 1;
    if (y <= 6) return 2;
    if (y <= 8) return 3;
    if (y <= 11) return 4;
    return 5;
  }

  // body grid uses digit keys '0'..'5' for ramp, 'O' outline, 'I' specular highlight
  function buildBody() {
    const g = MASK.map((r) => r.split(''));
    for (let y = 0; y < g.length; y++) {
      for (let x = 0; x < g[y].length; x++) {
        if (g[y][x] !== '#') { g[y][x] = '.'; continue; }
        const edge = !isBody(x - 1, y) || !isBody(x + 1, y) || !isBody(x, y - 1) || !isBody(x, y + 1);
        g[y][x] = edge ? 'O' : String(zone(y));
      }
    }
    // glossy specular highlight (top-left) — the jelly sheen
    [[4, 2], [5, 2], [4, 3], [9, 2]].forEach(([x, y]) => { if (g[y] && g[y][x] && g[y][x] !== 'O' && g[y][x] !== '.') g[y][x] = 'I'; });
    // a soft rim glow along the bottom edge interior
    for (let x = 2; x <= 11; x++) { if (g[11] && g[11][x] !== 'O' && g[11][x] !== '.') g[11][x] = '5'; }
    return g;
  }

  // ── emblem (forehead mark) — a composed badge: dark outline + colored fill + highlight,
  //    so it reads on ANY body color. Shape = opts.emblem, color = opts.emblemColor. ──
  const EMBLEMS = {
    star:  ['..XX..', '.XCCX.', 'XCiiCX', 'XCiiCX', '.XCCX.', '..XX..'],     // gem / spark
    plus:  ['.XCCX.', '.XCCX.', 'XCCCCX', 'XCCCCX', '.XCCX.', '.XCCX.'],     // cross
    heart: ['.X..X.', 'XCXXCX', 'XCiiCX', 'XCCCCX', '.XCCX.', '..XX..'],
    drop:  ['..XX..', '..CC..', '.XCCX.', '.XiCX.', 'XCiCCX', 'XCCCCX', '.XCCX.', '..XX..'],   // teardrop (enlarged)
    ring:  ['.XXXX.', 'XCCCCX', 'XC..CX', 'XC..CX', 'XCCCCX', '.XXXX.'],
    bolt:  ['.XXX..', 'XCCX..', 'XCCXX.', 'XCCCCX', '.XXCCX', '...XCX', '..XCX.', '..XX..'],   // lightning (enlarged)
    leaf:  ['...XX.', '..XCCX', '.XCiCX', 'XCiCCX', 'XCiCXk', 'XCCXk.', '.XXk..', '..k...'],   // leaf + stem (enlarged)
    none:  ['......', '......', '......', '......', '......', '......'],
  };
  const EMBLEM_KEYS = Object.keys(EMBLEMS);

  // emblem colorways: { O outline, fill, hi }
  const EMBLEM_COLORS = {
    gold:    { label: '金', O: '#6b4a12', fill: '#ffd24a', hi: '#fff0b0' },
    white:   { label: '白', O: '#2a3550', fill: '#ffffff', hi: '#ffffff' },
    cyan:    { label: '青', O: '#10433f', fill: '#6ff0e0', hi: '#d6fff8' },
    magenta: { label: '粉', O: '#52163e', fill: '#ff8fd0', hi: '#ffd8ee' },
    sky:     { label: '蓝', O: '#16315a', fill: '#7ab8ff', hi: '#d8ecff' },
    lime:    { label: '绿', O: '#284a12', fill: '#bff060', hi: '#eaffc0' },
    coral:   { label: '橙', O: '#5a2418', fill: '#ff9a6e', hi: '#ffd9c4' },
  };
  const EMBLEM_COLOR_KEYS = Object.keys(EMBLEM_COLORS);
  // auto-pick a contrasting emblem color when none is given (warm body → cool mark, etc.)
  const WARM_SKINS = { coral: 1, ember: 1, gold: 1, bubble: 1 };
  function defaultEmblemColor(skin) { return WARM_SKINS[skin] ? 'sky' : 'gold'; }

  const EYE_N = ['WE', 'EE'];
  const EYE_HAPPY = ['.E.', 'E.E'];
  const EYE_BLINK = ['EE'];
  const EYE_LISTEN = ['EE', 'EW'];

  const MOUTH = {
    idle:      ['M..M', '.MM.'],
    celebrate: ['.MMM.', 'MtttM', '.MMM.'],
    listen:    ['.M.', 'M.M', '.M.'],
    flat:      ['MMMM'],
  };

  function placeFeatures(g, opts) {
    const eye = opts.eyes || 'normal';
    if (eye === 'happy') { P.blit(g, EYE_HAPPY, 3, 6); P.blit(g, EYE_HAPPY, 8, 6); }
    else if (eye === 'blink' || eye === 'closed') { P.blit(g, EYE_BLINK, 3, 7); P.blit(g, EYE_BLINK, 9, 7); }
    else if (eye === 'listen') { P.blit(g, EYE_LISTEN, 3, 6); P.blit(g, EYE_LISTEN, 9, 6); }
    else { P.blit(g, EYE_N, 3, 6); P.blit(g, EYE_N, 9, 6); }
    const m = MOUTH[opts.mouth] || MOUTH.idle;
    const mw = m[0].length;
    P.blit(g, m, Math.round(6.5 - mw / 2), opts.mouth === 'celebrate' ? 9 : 10);
    return g;
  }

  // emblem placed as its own TOP layer (not baked into body) so it is centered on
  // the forehead and free to overflow above the head silhouette (per design review).
  function stampEmblem(ctx, scale, opts, pal) {
    const em = EMBLEMS[opts.emblem]; if (!em || opts.emblem === 'none') return;
    const ew = em[0].length, eh = em.length;
    // even-width emblems centre exactly on the body centre (canvas col BOX+6.5).
    const ex = BOX + ((14 - ew) >> 1);
    // sit on the forehead with the base just above the eyes; taller emblems
    // crest the head (overflow up). Slightly lower when a hat is worn.
    const hasHead = opts.head && opts.head !== 'none';
    const ey = (BOY + 6) - eh + (hasHead ? 1 : 0) + (opts.emblemY || 0);
    // soft glow disc behind the emblem so it reads on any body colour
    const ec = EMBLEM_COLORS[opts.emblemColor] || EMBLEM_COLORS[defaultEmblemColor(opts.skin || 'aurora')];
    if (opts.emblemGlow !== false) {
      ctx.save();
      ctx.globalAlpha = 0.26;
      ctx.fillStyle = ec.fill;
      const gx = (ex + ew / 2) * scale, gy = (ey + eh / 2) * scale, gr = Math.max(ew, eh) * 0.5 * scale;
      ctx.beginPath(); ctx.arc(gx, gy, gr, 0, Math.PI * 2); ctx.fill();
      ctx.restore();
    }
    P.stamp(ctx, scale, em, pal, ex, ey);
  }

  // ── egg (pre-hatch spawn) — shell tinted to the assigned skin, with speckles ──
  const EGG_MAP = [
    '....OOOO....',
    '..OO1II1OO..',
    '.O1I111111O.',
    'O1111111111O',
    'O1111111111O',
    'O1d111111d1O',
    'O1111111111O',
    'O2221111222O',
    'O2222222222O',
    'O2222d22222O',
    'O2222222222O',
    'O3322222233O',
    'O3333333333O',
    'O33d3333d33O',
    '.O33333333O.',
    '..OO3333OO..',
  ];
  function eggSprite(opts) {
    opts = Object.assign({}, DEFAULTS, opts || {});
    const scale = opts.scale || 6;
    const sk = skinOf(opts);
    const W = 12, H = 18;
    const { c, ctx } = P.makeCanvas(W, H, scale);
    const pal = { '.': null, 'O': sk.O, 'I': sk.hi, '1': sk.ramp[1], '2': sk.ramp[2], '3': sk.ramp[3], 'd': sk.ramp[4] };
    ctx.fillStyle = 'rgba(0,0,0,0.20)';
    ctx.fillRect(2 * scale, (H - 1.2) * scale, 8 * scale, 1.1 * scale);
    P.stamp(ctx, scale, EGG_MAP, pal, 0, 1);
    c.style.filter = glowFilter(opts, scale);
    return c;
  }

  // hands use the body mid tone ('3') + outline ('O')
  // both hands tuck 1px into the body edge so they read as symmetric & attached
  const HAND = ['.O.', 'O3O', '.O.'];
  const LH = { x: 4, y: 13 };
  const RH = { x: 19, y: 13 };

  const ITEMS = {
    none:   null,
    laptop: { s: ['lllll', 'lzzzl', 'lzzzl', 'aaaaa'], lx: -4, ly: -1, rx: 2, ry: -1 },
    book:   { s: ['prrp', 'pwwp', 'pwwp', 'pwwp'], lx: -3, ly: -2, rx: 2, ry: -2 },
    coin:   { s: ['.yy.', 'yqqy', 'yqqy', '.yy.'], lx: -3, ly: -2, rx: 2, ry: -2 },
    pen:    { s: ['...y', '..y.', '.l..', 'e...'], lx: -3, ly: -3, rx: 2, ry: -3 },
    umbrella:{ s: ['.uuu.', 'uuuuu', '..k..', '..k..', '..k.'], lx: -4, ly: -4, rx: 2, ry: -4 },
    magnify:{ s: ['.mm.', 'm..m', 'm..m', '.mm.', '...k', '....k'], lx: -4, ly: -3, rx: 2, ry: -3 },
    flower: { s: ['f.f', '.q.', 'f.f', '.v.', '.v.'], lx: -3, ly: -4, rx: 2, ry: -4 },
    dumbbell:{ s: ['a..a', 'aaaa', 'a..a'], lx: -4, ly: -1, rx: 2, ry: -1 },
    leaf:   { s: ['.v.', 'vvv', 'vvv', '.v.'], lx: -3, ly: -2, rx: 2, ry: -2 },
  };

  const HEADS = {
    none: null,
    safari: { s: ['.....HHHH.....', '....HhhhhH....', '...HhhhhhhH...', '..HhhhhhhhhH..', 'kkkkkkkkkkkkkk', '..kk......kk..'], ox: 6, oy: 0 },
    beanie: { s: ['....pppp....', '..pppppppp..', '.pppppppppp.', 'wwwwwwwwwwww'], ox: 7, oy: 1 },
    horns:  { s: ['w........w', 'ww......ww', '.ww....ww.'], ox: 8, oy: 1 },
    antenna:{ s: ['...c..', '...c..', '.c.c..', '..cc..'], ox: 10, oy: 0 },
    sprout: { s: ['..v..', '.vvv.', 'v.v.v', '..v..'], ox: 10, oy: 1 },
    crown:  { s: ['y.y.y.y', 'yyyyyyy', 'yqyqyqy'], ox: 9, oy: 2 },
  };

  // ── carriers — a mount/vehicle that sits BELOW Reka (idea: 承载物) ──
  // drawn at the canvas bottom (rows 18–21); Reka's base overlaps its top edge.
  const CARRIERS = {
    none:   null,
    cloud:  { s: ['...wwww...', '.wwwwwwww.', 'wwwwwwwwww', '.wllllllw.'], ox: 8, oy: 18 },
    disc:   { s: ['.mmmmmmmm.', 'cccccccccc', '.cc....cc.'], ox: 8, oy: 19 },
    pad:    { s: ['.vvvvvvvv.', 'vvvvvvvvvv', '..vvvvvv..'], ox: 8, oy: 19 },
    board:  { s: ['oooooooooo', 'kkkkkkkkkk', '.e......e.'], ox: 8, oy: 19 },
    ring:   { s: ['.yyyyyyyy.', 'yqyqyqyqyq', '.yyyyyyyy.'], ox: 8, oy: 19 },
  };

  // ── auras — the background glow, promoted to its own cosmetic slot ──
  // 'soft' = skin-derived default; named auras override with their own colors.
  const AURAS = {
    none:    null,
    soft:    'skin',
    gold:    ['#ffd24a', '#ffb000'],
    cyan:    ['#6ff0e0', '#3ac49a'],
    magenta: ['#ff8fd0', '#e85fbd'],
    azure:   ['#7ab8ff', '#3a82e0'],
    ember:   ['#ffb072', '#ff6a3d'],
    verdant: ['#bdf07a', '#5db84a'],
    frost:   ['#cfeaff', '#8fd0ff'],
    rainbow: ['#ff8fd0', '#7ab8ff', '#9ece6a'],
  };

  function skinOf(opts) { return SKINS[opts.skin] || SKINS.aurora; }

  function paletteFor(opts) {
    const sk = skinOf(opts);
    const ec = EMBLEM_COLORS[opts.emblemColor] || EMBLEM_COLORS[defaultEmblemColor(opts.skin || 'aurora')];
    const pal = Object.assign({}, BASE_PAL, {
      '0': sk.ramp[0], '1': sk.ramp[1], '2': sk.ramp[2], '3': sk.ramp[3], '4': sk.ramp[4], '5': sk.ramp[5],
      'O': sk.O, 'I': sk.hi, 's': sk.ramp[0],
      'X': ec.O, 'C': ec.fill, 'i': ec.hi,
    });
    if (opts.palette) Object.assign(pal, opts.palette);
    return pal;
  }

  function compose(ctx, scale, opts) {
    const pal = paletteFor(opts);
    ctx.clearRect(0, 0, CW * scale, CH * scale);
    const carrier = CARRIERS[opts.carrier];
    ctx.fillStyle = 'rgba(0,0,0,0.20)';
    const sh = opts.shadow == null ? 1 : opts.shadow;
    const shW = (carrier ? 9 : 12) * sh, shX = (CENTER - shW / 2);
    ctx.fillRect(shX * scale, (CH - 1.5) * scale, shW * scale, 1.2 * scale);

    // carrier sits below the body (drawn first so Reka's base overlaps its top edge)
    if (carrier) P.stamp(ctx, scale, carrier.s, pal, carrier.ox, carrier.oy);

    const head = HEADS[opts.head];
    if (head) P.stamp(ctx, scale, head.s, pal, head.ox, head.oy);

    const g = placeFeatures(buildBody(), opts);
    P.stamp(ctx, scale, P.gridToMap(g), pal, BOX, BOY);
    stampEmblem(ctx, scale, opts, pal);

    P.stamp(ctx, scale, HAND, pal, LH.x, LH.y);
    P.stamp(ctx, scale, HAND, pal, RH.x, RH.y);

    const li = ITEMS[opts.leftItem];
    if (li) P.stamp(ctx, scale, li.s, pal, LH.x + li.lx, LH.y + li.ly);
    const ri = ITEMS[opts.rightItem];
    if (ri) P.stamp(ctx, scale, ri.s, pal, RH.x + ri.rx, RH.y + ri.ry);
  }

  function hexA(hex, a) {
    const h = hex.replace('#', '');
    const r = parseInt(h.slice(0, 2), 16), g = parseInt(h.slice(2, 4), 16), b = parseInt(h.slice(4, 6), 16);
    return `rgba(${r},${g},${b},${a})`;
  }
  function glowFilter(opts, scale) {
    if (opts.glow === false) return '';
    const aura = opts.aura || 'soft';
    if (aura === 'none') return '';
    if (aura === 'soft' || !AURAS[aura]) {
      const sk = skinOf(opts);
      return `drop-shadow(0 0 ${Math.max(2, scale * 1.2)}px ${hexA(sk.ramp[2], 0.55)}) drop-shadow(0 0 ${Math.max(4, scale * 2.4)}px ${hexA(sk.ramp[3], 0.30)})`;
    }
    const cols = AURAS[aura];
    let f = `drop-shadow(0 0 ${Math.max(2, scale * 1.3)}px ${hexA(cols[0], 0.7)}) drop-shadow(0 0 ${Math.max(5, scale * 2.8)}px ${hexA(cols[cols.length - 1], 0.4)})`;
    if (cols.length > 2) f += ` drop-shadow(0 0 ${Math.max(7, scale * 3.6)}px ${hexA(cols[1], 0.32)})`;
    return f;
  }

  function glowColors(opts) {
    // the representative glow color(s) for a build — single source of truth so UI
    // (e.g. the menu panel tint) can match Reka's aura. Mirrors glowFilter().
    opts = Object.assign({}, DEFAULTS, opts || {});
    const aura = opts.aura || 'soft';
    if (aura === 'soft' || aura === 'none' || !AURAS[aura]) {
      const sk = skinOf(opts); return [sk.ramp[2], sk.ramp[3]];
    }
    return AURAS[aura].slice();
  }

  const DEFAULTS = { eyes: 'normal', mouth: 'idle', head: 'none', leftItem: 'none', rightItem: 'none', skin: 'aurora', emblem: 'star', carrier: 'none', aura: 'soft' };

  function sprite(opts) {
    opts = Object.assign({}, DEFAULTS, opts || {});
    const scale = opts.scale || 6;
    const { c, ctx } = P.makeCanvas(CW, CH, scale);
    compose(ctx, scale, opts);
    c.style.filter = glowFilter(opts, scale);
    return c;
  }

  // render a SINGLE component in isolation (the parts are componentized, so an
  // icon = just that part's sprite). kind: skin|head|item|carrier|emblem.
  function partSprite(kind, key, opts) {
    opts = opts || {};
    const fitScale = (w, h) => opts.fit ? Math.max(1, Math.round(opts.fit / Math.max(w, h))) : (opts.scale || 4);
    if (kind === 'skin') {
      const map = P.gridToMap(buildBody());
      const w = map[0].length, h = map.length, scale = fitScale(w, h);
      const { c, ctx } = P.makeCanvas(w, h, scale);
      P.stamp(ctx, scale, map, paletteFor({ skin: key }), 0, 0);
      if (opts.glow !== false) c.style.filter = glowFilter({ skin: key, aura: 'soft' }, scale);
      return c;
    }
    const pal = paletteFor({ skin: opts.skin || 'grape', emblemColor: opts.emblemColor || 'gold' });
    const s = kind === 'emblem' ? EMBLEMS[key] : ({ head: HEADS, item: ITEMS, carrier: CARRIERS }[kind] || {})[key] && ({ head: HEADS, item: ITEMS, carrier: CARRIERS }[kind])[key].s;
    if (!s || !s.length) return P.makeCanvas(1, 1, opts.scale || 4).c;
    const w = Math.max.apply(null, s.map(r => r.length)), h = s.length, scale = fitScale(w, h);
    const { c, ctx } = P.makeCanvas(w, h, scale);
    P.stamp(ctx, scale, s, pal, 0, 0);
    return c;
  }

  // deterministic random colorway from a string/number seed
  function seededSkin(seed) {
    let h = 2166136261;
    const s = String(seed);
    for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); }
    return SKIN_KEYS[(h >>> 0) % SKIN_KEYS.length];
  }

  class Mascot {
    constructor(mount, opts) {
      opts = opts || {};
      this.scale = opts.scale || 6;
      this.opts = Object.assign({}, DEFAULTS, opts);
      this.state = 'idle';
      this.t0 = performance.now();
      this.lastBlink = 0; this.blinking = false; this.lastSpawn = 0;

      this.wrap = document.createElement('div');
      this.wrap.style.cssText = 'position:relative;display:inline-block;will-change:transform;';
      this.fx = document.createElement('div');
      this.fx.style.cssText = 'position:absolute;left:50%;top:-10%;width:0;height:0;pointer-events:none;overflow:visible;z-index:3;';
      const cv = P.makeCanvas(CW, CH, this.scale);
      this.c = cv.c; this.ctx = cv.ctx;
      this.inner = document.createElement('div');
      this.inner.style.cssText = 'will-change:transform;transform-origin:50% 100%;';
      this.inner.appendChild(this.c);
      this.wrap.appendChild(this.inner);
      this.wrap.appendChild(this.fx);
      mount.appendChild(this.wrap);

      this.draw();
      this.raf = requestAnimationFrame((t) => this.loop(t));
    }
    set(opts) { Object.assign(this.opts, opts); this.draw(); }
    setState(s) { this.state = s; this.t0 = performance.now(); this.lastSpawn = 0; if (s !== 'sleep' && this.opts.eyes === 'closed') { this.opts.eyes = 'normal'; this.draw(); } }
    draw() { compose(this.ctx, this.scale, this.opts); this.c.style.filter = glowFilter(this.opts, this.scale); }

    spawnConfetti() {
      const sk = skinOf(this.opts);
      const cols = [sk.ramp[1], sk.ramp[2], '#f7c948', '#f48fb1', '#bb9af7', '#7ad7c6'];
      for (let i = 0; i < 5; i++) {
        const d = document.createElement('div');
        const s = (this.scale * (Math.random() < .5 ? 2 : 3)) | 0;
        d.style.cssText = `position:absolute;width:${s}px;height:${s}px;background:${cols[(Math.random() * cols.length) | 0]};left:0;top:0;border-radius:1px;`;
        const ang = Math.random() * Math.PI - Math.PI;
        const dist = 30 + Math.random() * 55;
        const tx = Math.cos(ang) * dist, ty = -Math.abs(Math.sin(ang)) * dist - 10;
        d.animate([
          { transform: 'translate(0,0) rotate(0deg)', opacity: 1 },
          { transform: `translate(${tx}px,${ty + 60}px) rotate(${(Math.random() * 720 - 360) | 0}deg)`, opacity: 0 },
        ], { duration: 850 + Math.random() * 350, easing: 'cubic-bezier(.2,.7,.3,1)' });
        this.fx.appendChild(d);
        setTimeout(() => d.remove(), 1250);
      }
    }
    spawnRing() {
      const sk = skinOf(this.opts);
      const d = document.createElement('div');
      const base = this.scale * 6;
      d.style.cssText = `position:absolute;width:${base}px;height:${base}px;left:${-base / 2}px;top:${-base}px;border:2px solid ${sk.ramp[2]};border-radius:3px;transform:rotate(45deg);`;
      d.animate([
        { transform: 'translateY(0) rotate(45deg) scale(.6)', opacity: .8 },
        { transform: 'translateY(-22px) rotate(45deg) scale(1.7)', opacity: 0 },
      ], { duration: 1100, easing: 'cubic-bezier(.2,.7,.3,1)' });
      this.fx.appendChild(d);
      setTimeout(() => d.remove(), 1150);
    }

    spawnZ() {
      const d = document.createElement('div');
      d.textContent = 'Z';
      d.style.cssText = `position:absolute;left:4px;top:-4px;color:${skinOf(this.opts).ramp[2]};font:700 ${this.scale * 3}px system-ui,sans-serif;pointer-events:none;text-shadow:0 1px 2px rgba(0,0,0,.3);`;
      d.animate([
        { transform: 'translate(0,0) scale(.6)', opacity: 0 },
        { transform: 'translate(12px,-22px) scale(1.05)', opacity: .9, offset: .35 },
        { transform: 'translate(24px,-44px) scale(1.2)', opacity: 0 },
      ], { duration: 1900, easing: 'ease-out' });
      this.fx.appendChild(d);
      setTimeout(() => d.remove(), 1950);
    }

    loop(now) {
      const t = (now - this.t0) / 1000;
      let ty = 0, rot = 0, sx = 1, sy = 1;
      if (this.state !== 'celebrate' && this.state !== 'sleep') {
        if (now - this.lastBlink > 2600 + Math.random() * 2200 && !this.blinking) {
          this.blinking = true; this.lastBlink = now;
          const prev = this.opts.eyes;
          this.opts.eyes = 'blink'; this.draw();
          setTimeout(() => { this.opts.eyes = (this.state === 'listen' ? 'listen' : prev === 'blink' ? 'normal' : prev); this.blinking = false; this.draw(); }, 120);
        }
      }
      if (this.state === 'idle') {
        ty = Math.sin(t * 1.9) * 3.2;
        sy = 1 + Math.sin(t * 1.9 + 1) * 0.018; sx = 1 - Math.sin(t * 1.9 + 1) * 0.018; // jelly squash
      } else if (this.state === 'celebrate') {
        const hop = Math.abs(Math.sin(t * 6.2));
        ty = -hop * 12; sy = 1 + hop * 0.06; sx = 1 - hop * 0.05; rot = Math.sin(t * 12) * 4;
        if (now - this.lastSpawn > 230) { this.lastSpawn = now; this.spawnConfetti(); }
      } else if (this.state === 'listen') {
        ty = Math.sin(t * 2.4) * 2; rot = Math.sin(t * 1.3) * 5;
        if (now - this.lastSpawn > 700) { this.lastSpawn = now; this.spawnRing(); }
      } else if (this.state === 'sleep') {
        if (this.opts.eyes !== 'closed') { this.opts.eyes = 'closed'; this.draw(); }
        ty = Math.sin(t * 0.9) * 2;
        sy = 1 + Math.sin(t * 0.9 + 1) * 0.012; sx = 1 - Math.sin(t * 0.9 + 1) * 0.012;
        if (now - this.lastSpawn > 1500) { this.lastSpawn = now; this.spawnZ(); }
      }
      this.inner.style.transform = `translateY(${ty}px) rotate(${rot}deg) scale(${sx},${sy})`;
      this.raf = requestAnimationFrame((n) => this.loop(n));
    }
    destroy() { cancelAnimationFrame(this.raf); this.wrap.remove(); }
  }

  // runtime-extensible part registry: add/replace a part without editing core (Reka 后期拓展)
  function register(kind, id, def) {
    const tbl = { skin: SKINS, emblem: EMBLEMS, emblemColor: EMBLEM_COLORS, head: HEADS, item: ITEMS, carrier: CARRIERS, aura: AURAS }[kind];
    if (tbl) { tbl[id] = def; return true; }
    return false;
  }
  function partKeys(kind) {
    const tbl = { skin: SKINS, emblem: EMBLEMS, emblemColor: EMBLEM_COLORS, head: HEADS, item: ITEMS, carrier: CARRIERS, aura: AURAS }[kind];
    return tbl ? Object.keys(tbl) : [];
  }

  global.Mascot = {
    sprite, eggSprite, partSprite, mount: (m, o) => new Mascot(m, o), CW, CH,
    ITEMS: Object.keys(ITEMS), HEADS: Object.keys(HEADS), CARRIERS: Object.keys(CARRIERS), AURAS: Object.keys(AURAS),
    SKINS, SKIN_KEYS, EMBLEMS, EMBLEM_KEYS, EMBLEM_COLORS, EMBLEM_COLOR_KEYS, defaultEmblemColor, seededSkin, glowColors,
    register, partKeys,
  };
})(window);
