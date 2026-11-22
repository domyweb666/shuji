#!/usr/bin/env node
// 3-9 C（.analytics/09-驗證/計畫.md）：從薯記匯出的備份算多米自己要看的數字。
// 只讀檔、不上傳。只有一個人在用，數字只能當故事，不能當證據。
// 用法：node tools/analytics-c-report.mjs 薯記備份-2026-12-31.json
import { readFileSync } from 'node:fs';

const file = process.argv[2];
if (!file) {
  console.error('用法：node tools/analytics-c-report.mjs <備份檔.json>');
  process.exit(1);
}
const s = JSON.parse(readFileSync(file, 'utf8'));
if ((s.v ?? 1) < 2) {
  console.error('這是 v1 或原型的備份。先在新版 app 還原一次、再匯出，就會是 v2。');
  process.exit(1);
}

const habitId = s.habit?.id;
const days = (d) => Math.round(Date.parse(d + 'T00:00:00Z') / 86400000);
const fmt = (n) => new Date(n * 86400000).toISOString().slice(0, 10);

const records = (s.records ?? []).filter((r) => r.habit === habitId && !r.deletedAt);
const done = new Set(records.filter((r) => r.kind === 'done').map((r) => days(r.day)));
const leave = new Set(records.filter((r) => r.kind === 'leave').map((r) => days(r.day)));
const seen = (s.seen ?? []).filter((x) => x.habit === habitId);
const obs = (s.observations ?? []).filter((o) => o.habit === habitId);
const trials = (s.trials ?? []).filter((t) => t.habit === habitId);
const reviewDay = s.settings?.reviewDay ?? 0;

if (!habitId) {
  console.log('目前沒有種著的習慣。');
  process.exit(0);
}

// 回顧週：結束在回顧日的 7 天
const planted = days(s.habit.planted);
const lastDay = Math.max(planted, ...records.map((r) => days(r.day)));
const weekday = (n) => (((n % 7) + 7 + 4) % 7);
let end = lastDay;
while (weekday(end) !== reviewDay) end -= 1;

console.log(`習慣：如果${s.habit.trigger}，我就${s.habit.floor}（種下 ${s.habit.planted}）\n`);
console.log('週（結束日）  記了  請假  打開這週的田  觀察              原因          做法        試兩週');
const rows = [];
for (let e = end; e >= planted; e -= 7) {
  let d = 0, l = 0;
  for (let k = e - 6; k <= e; k++) {
    if (done.has(k)) d++;
    else if (leave.has(k)) l++;
  }
  const week = fmt(e);
  const opened = seen.some((x) => x.week === week) ? '有' : '—';
  const o = obs.find((x) => x.week === week);
  const t = o?.trial ? trials.find((x) => x.id === o.trial) : null;
  rows.push([week, String(d).padStart(4), String(l).padStart(4), opened.padStart(8),
    (o?.kind ?? '—').padEnd(16), (o?.cause ?? '—').padEnd(12), (o?.action ?? '—').padEnd(10),
    t ? `${t.status}${t.conclusion ? '／' + t.conclusion : ''}` : '—']);
}
for (const r of rows.reverse()) console.log(r.join('  '));

const asked = obs.filter((o) => o.kind !== 'leaveReason' && o.cause != null);
const skipped = asked.filter((o) => o.cause === 'unanswered').length;
const chose = obs.filter((o) => o.action && !['unanswered', 'none'].includes(o.action)).length;
console.log(`\n觀察 ${obs.length} 次；原因題跳過 ${skipped}／${asked.length}；選了做法 ${chose}；答應試兩週 ${trials.length}`);
console.log('分析類通知：0 則（薯記沒有分析類通知）');
console.log('\n提醒：觀察只在差很多時出現，之後本來就容易回來（回歸平均）。前後比較不是效果。');
