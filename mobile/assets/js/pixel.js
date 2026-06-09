/* pixel.js — tiny crisp pixel-sprite engine.
 * A "map" is an array of equal-length strings; each char keys into a palette.
 * '.' or ' ' = transparent. Everything renders at integer scale, no smoothing. */
(function (global) {
  function makeCanvas(w, h, scale) {
    const c = document.createElement('canvas');
    c.width = w * scale;
    c.height = h * scale;
    c.className = 'pixel';
    const ctx = c.getContext('2d');
    ctx.imageSmoothingEnabled = false;
    return { c, ctx, w, h, scale };
  }

  // stamp a map onto ctx at logical offset (ox,oy)
  function stamp(ctx, scale, map, pal, ox, oy) {
    ox = ox | 0; oy = oy | 0;
    for (let y = 0; y < map.length; y++) {
      const row = map[y];
      for (let x = 0; x < row.length; x++) {
        const ch = row[x];
        if (ch === '.' || ch === ' ') continue;
        const col = pal[ch];
        if (!col) continue;
        ctx.fillStyle = col;
        ctx.fillRect((ox + x) * scale, (oy + y) * scale, scale, scale);
      }
    }
  }

  // single logical pixel
  function px(ctx, scale, x, y, color) {
    ctx.fillStyle = color;
    ctx.fillRect((x * scale) | 0, (y * scale) | 0, scale, scale);
  }

  // build an editable char grid (array of arrays) from a mask map
  function grid(maskMap) {
    return maskMap.map((r) => r.split(''));
  }
  function gridToMap(g) { return g.map((r) => r.join('')); }
  function setCell(g, x, y, ch) {
    if (y < 0 || y >= g.length) return;
    if (x < 0 || x >= g[y].length) return;
    g[y][x] = ch;
  }
  // stamp a small sprite map into a grid (transparent cells skipped)
  function blit(g, sprite, ox, oy) {
    for (let y = 0; y < sprite.length; y++) {
      for (let x = 0; x < sprite[y].length; x++) {
        const ch = sprite[y][x];
        if (ch === '.' || ch === ' ') continue;
        setCell(g, ox + x, oy + y, ch);
      }
    }
  }

  global.Pixel = { makeCanvas, stamp, px, grid, gridToMap, setCell, blit };
})(window);
