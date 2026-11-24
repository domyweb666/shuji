// 週報：推一份存檔、走完四問，淺色深色各拍程式寫的那句與假 AI 回覆（-weekDemo）。用法：node week.mjs <app.zip> <輸出資料夾>
const _ts = URLSearchParams.prototype.toString; URLSearchParams.prototype.toString = function () { return _ts.call(this).replace(/[+]/g, "%20"); };
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
const require = createRequire(import.meta.url);
const api = await import(pathToFileURL(require.resolve('@limrun/api')).href);
const Limrun = api.default?.default ?? api.default, Ios = api.Ios ?? api.default.Ios;
const SP = process.argv[3], OUT = join(SP, 'shots'); mkdirSync(OUT, { recursive: true });
const apiKey = process.env.LIM_API_KEY ?? readFileSync(join(process.env.USERPROFILE, '.lim', 'config.yaml'), 'utf8').match(/api-key:\s*(\S+)/)[1];
const BUNDLE = 'org.domyweb.shuji';
const lim = new Limrun({ apiKey }); const t0 = Date.now();
const log = (...a) => console.log(((Date.now() - t0) / 1000).toFixed(1) + 's', ...a);
const sleep = ms => new Promise(r => setTimeout(r, ms));
let inst, c;
const flat = (n, o = []) => { if (Array.isArray(n)) { n.forEach(x => flat(x, o)); return o; } if (n && typeof n === 'object') { o.push(n); (n.children ?? []).forEach(x => flat(x, o)); } return o; };
const nodes = async () => flat(await c.elementTree());
const shot = async n => { try { const s = await c.screenshot({ format: 'jpeg', size: 'scaled' }); writeFileSync(join(OUT, n + '.jpg'), Buffer.from(s.base64, 'base64')); log('shot', n, s.width + 'x' + s.height); } catch (e) { log('shot fail', n, e.message); } };
const dump = async n => { try { const ns = await nodes(); log('tree@' + n, ns.filter(x => x.AXLabel).map(x => x.AXLabel.slice(0, 40) + `[${Math.round(x.frame.x)},${Math.round(x.frame.y)},${Math.round(x.frame.width)},${Math.round(x.frame.height)}]`).join(' | ')); } catch (e) { log('dump fail', e.message); } };
const simctl = async a => { try { await c.simctl(a).wait(); } catch (e) { log('simctl fail', a.join(' '), e.message); } };
const tap = async (l, wait = 900) => { try { await c.tapElement({ AXLabel: l }); log('tap', l); await sleep(wait); return true; } catch (e) { log('tap FAIL', l, (e.message || '').slice(0, 120)); return false; } };
const frame = async l => (await nodes()).find(x => x.AXLabel === l)?.frame;
const ymd = d => d.toISOString().slice(0, 10);
let TODAY = new Date(Date.UTC(2026, 10, 25));
const at = n => new Date(TODAY.getTime() + n * 864e5), day = n => ymd(at(n));
// 最近一個星期日（含今天）離今天幾天；回顧日是星期日，週報看到那天為止
const back = () => TODAY.getUTCDay();
// 平日做、週末漏；那一週的星期三跳過（旅行）。四問看種下那天記問過沒有，每次換一個 n 才會再跳
function make(n) {
  const s = { logs: {}, weekly: [], queue: [], basket: [], settings: { reviewDay: 0 },
    habit: { floor: '坐上蒲團', trigger: '刷完牙', planted: day(-n), travelFloor: '', obstacle: '', backup: '', why: '', estimatedDays: 66 } };
  for (let i = -n; i < 0; i++) { const w = at(i).getUTCDay(); if (w !== 0 && w !== 6) s.logs[day(i)] = { t: 'done' }; }
  s.logs[day(-back() - 4)] = { t: 'leave', reason: '旅行' };
  s.logs[day(0)] = { t: 'done' };
  for (let i = 2; i >= 0; i--) s.weekly.push({ date: day(-13 - 7 * i), scores: [5, 5, 5, 5] });
  return s;
}
async function load(state, args = []) {
  try { await c.terminateApp(BUNDLE); } catch {}
  await sleep(500);
  const p = join(SP, 'week-state.json'); writeFileSync(p, JSON.stringify(state));
  await c.pushFile(p, 'Library/Application Support/Shuji/state.json', { bundleId: BUNDLE, containerType: 'data' });
  await simctl(['launch', 'booted', BUNDLE, ...args]); await sleep(3200);
}
async function answer() {
  for (let i = 1; i <= 4; i++) {
    const f = (await nodes()).find(x => x.frame?.height > 36 && x.frame?.height < 46 && x.frame?.width > 300 && x.frame?.y > 500 && x.AXLabel)?.frame;
    if (!f) { log('no scale', i); return false; }
    await c.tap(f.x + f.width * 4.5 / 7, f.y + f.height / 2); await sleep(1100);
  }
  await sleep(800); return true;
}
async function week(sfx, n) {
  await load(make(n)); await answer(); await shot('week' + sfx); await dump('week' + sfx);
  await load(make(n + 1), ['-weekDemo']); await answer(); await sleep(1500); await shot('week-ai' + sfx); await dump('week-ai' + sfx);
  if (await tap('就這樣改', 1200)) { await shot('week-changed' + sfx); await dump('week-changed' + sfx); }
}
try {
  const asset = await lim.assets.getOrUpload({ path: process.argv[2], name: 'shuji-sim-' + Date.now() + '.zip', platform: 'ios', kind: 'App', ttl: '2h' });
  for (let i = 0; ; i++) {
    try {
      inst = await lim.iosInstances.create({ wait: true, metadata: { labels: { project: 'shuji' } }, spec: { model: 'iphone', inactivityTimeout: '3m', hardTimeout: '20m', initialAssets: [{ kind: 'App', source: 'AssetName', assetName: asset.name, launchMode: 'RelaunchIfRunning' }] } });
      break;
    } catch (e) { if (i < 15 && /Concurrency/i.test(e.message)) { log('wait slot'); await sleep(40000); } else throw e; }
  }
  log('instance', inst.metadata.id);
  c = await Ios.createInstanceClient({ apiUrl: inst.status.apiUrl, token: inst.status.token, logLevel: 'none' });
  await sleep(3500);
  await load(make(40));
  // 四問那張蓋著的時候也讀得到今天頁的日期；讀不到就用電腦的日期
  const lab = (await nodes()).map(x => x.AXLabel).filter(Boolean).find(x => /\d+\s*月\s*\d+\s*日/.test(x));
  const m = lab?.match(/(\d+)\s*月\s*(\d+)\s*日/), now = new Date();
  TODAY = m ? new Date(Date.UTC(now.getFullYear(), +m[1] - 1, +m[2])) : new Date(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()));
  log('header', lab, 'today', ymd(TODAY));
  await week('', 47);
  await simctl(['ui', 'booted', 'appearance', 'dark']); await week('-dark', 49); await simctl(['ui', 'booted', 'appearance', 'light']);
  log('DONE');
} catch (e) { log('ERROR', e.stack || e); process.exitCode = 1; }
finally {
  try { c?.disconnect(); } catch {}
  if (inst) { try { await lim.iosInstances.delete(inst.metadata.id); log('deleted'); } catch (e) { log('DELETE FAILED', inst.metadata.id, e.message); } }
  process.exit();
}
