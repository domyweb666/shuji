#!/usr/bin/env node
// 擋畫面程式裡寫死的色碼、字級、間距、圓角。只准用 Domy 代號（Theme、Sp、Ty、Sz、Rd、DomyTokens）。
// 真的只用一次的數值，在那一行寫 `// domy-ignore: 原因`。
// 插畫（VineView 的藤、PotatoView 的地瓜座標）不在檢查範圍。
// 用法：node tools/check-ui-tokens.mjs
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const targets = ['Shuji/Views', 'Shuji/Design', 'Shuji/AI/AIViews.swift', 'ShujiWidget/ShujiWidget.swift'];
const skipFiles = new Set(['VineView.swift']);

const rules = [
  { name: '色碼', re: /0x[0-9A-Fa-f]{6}\b|#[0-9A-Fa-f]{6}\b/ },
  { name: '系統色', re: /Color\.(purple|blue|red|green|orange|gray|secondary|primary)\b|\.systemPurple|systemGroupedBackground/ },
  { name: '字級數字', re: /\.system\(size:\s*\d/ },
  { name: '系統字級（請用 Ty.*）', re: /\.font\(\.(largeTitle|title|title2|title3|headline|body|callout|subheadline|footnote|caption|caption2)\b/ },
  { name: '間距數字', re: /\.padding\((\.\w+,\s*)?-?\d+(\.\d+)?\)|spacing:\s*[1-9]\d*(\.\d+)?\b|EdgeInsets\(/ },
  { name: '尺寸數字', re: /\.frame\([^)]*\b(width|height|minHeight|maxHeight|minWidth):\s*\d/ },
  { name: '圓角數字', re: /cornerRadius:\s*\d/ },
];

function files(p) {
  const abs = join(root, p);
  if (statSync(abs).isFile()) return [abs];
  return readdirSync(abs).filter((f) => f.endsWith('.swift')).map((f) => join(abs, f));
}

let bad = 0;
for (const file of targets.flatMap(files)) {
  if (skipFiles.has(file.split(/[\\/]/).pop())) continue;
  const lines = readFileSync(file, 'utf8').split('\n');
  let inPotato = false;
  lines.forEach((line, i) => {
    if (/struct PotatoView\b/.test(line)) inPotato = true;
    else if (inPotato && /^struct /.test(line)) inPotato = false;
    if (inPotato || line.includes('domy-ignore') || line.trim().startsWith('//')) return;
    for (const r of rules) {
      if (r.re.test(line)) {
        bad++;
        console.log(`${relative(root, file)}:${i + 1}  [${r.name}]  ${line.trim()}`);
      }
    }
  });
}

if (bad) {
  console.error(`\n[check-ui-tokens] 有 ${bad} 處寫死的數值。改用 Domy 代號，或在那一行加 // domy-ignore: 原因`);
  process.exit(1);
}
console.log('[check-ui-tokens] 畫面程式都用 Domy 代號');
