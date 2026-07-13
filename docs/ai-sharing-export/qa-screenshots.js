const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const deckPath = path.resolve(process.argv[3] || path.join(__dirname, 'index.html'));
const outDir = process.argv[2] || '/tmp/ureka-slides-qa';
fs.mkdirSync(outDir, { recursive: true });

(async () => {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
  await page.goto(`file://${deckPath}`, { waitUntil: 'networkidle' });
  await page.waitForTimeout(500);

  const slideCount = await page.locator('.slide').count();
  const results = [];

  for (let i = 0; i < slideCount; i += 1) {
    await page.evaluate((index) => {
      const slides = Array.from(document.querySelectorAll('.slide'));
      slides.forEach((slide, idx) => {
        slide.classList.toggle('active', idx === index);
        slide.classList.toggle('visible', idx === index);
      });
    }, i);
    await page.waitForTimeout(1200);

    const screenshotPath = path.join(outDir, `slide-${String(i + 1).padStart(2, '0')}.png`);
    await page.screenshot({ path: screenshotPath, fullPage: false });

    const diagnostics = await page.evaluate((index) => {
      const stage = document.querySelector('.deck-stage');
      const slide = document.querySelectorAll('.slide')[index];
      const stageRect = stage.getBoundingClientRect();
      const slideRect = slide.getBoundingClientRect();
      const visible = Array.from(slide.querySelectorAll('*')).filter((el) => {
        const rect = el.getBoundingClientRect();
        const style = window.getComputedStyle(el);
        return rect.width > 1 && rect.height > 1 && style.visibility !== 'hidden' && style.display !== 'none';
      });

      const overflow = visible
        .map((el) => {
          const rect = el.getBoundingClientRect();
          const left = rect.left < slideRect.left - 1;
          const top = rect.top < slideRect.top - 1;
          const right = rect.right > slideRect.right + 1;
          const bottom = rect.bottom > slideRect.bottom + 1;
          if (!left && !top && !right && !bottom) return null;
          return {
            tag: el.tagName.toLowerCase(),
            className: String(el.className || ''),
            text: (el.textContent || '').trim().slice(0, 80),
            rect: {
              left: Math.round(rect.left - slideRect.left),
              top: Math.round(rect.top - slideRect.top),
              right: Math.round(rect.right - slideRect.left),
              bottom: Math.round(rect.bottom - slideRect.top),
              width: Math.round(rect.width),
              height: Math.round(rect.height),
            },
            sides: { left, top, right, bottom },
          };
        })
        .filter(Boolean);

      const brokenImages = Array.from(slide.querySelectorAll('img')).filter((img) => !img.complete || img.naturalWidth === 0).map((img) => img.src);
      const tooSmallText = Array.from(slide.querySelectorAll('p, span, strong, h1, h2, h3, div'))
        .map((el) => {
          const style = window.getComputedStyle(el);
          const size = parseFloat(style.fontSize);
          const text = (el.textContent || '').trim();
          if (!text || size >= 18) return null;
          return { tag: el.tagName.toLowerCase(), className: String(el.className || ''), size, text: text.slice(0, 80) };
        })
        .filter(Boolean);

      return {
        index: index + 1,
        title: slide.dataset.title || '',
        stage: { width: Math.round(stageRect.width), height: Math.round(stageRect.height) },
        overflow,
        brokenImages,
        tooSmallText,
      };
    }, i);
    results.push({ ...diagnostics, screenshotPath });
  }

  await browser.close();
  const reportPath = path.join(outDir, 'report.json');
  fs.writeFileSync(reportPath, JSON.stringify({ deckPath, slideCount, results }, null, 2));
  console.log(reportPath);
})();
