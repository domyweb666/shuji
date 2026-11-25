// 把各狀態的存檔直接塞進 app，淺色深色各拍一輪。用法：node states.mjs <app.zip> <輸出資料夾> [狀態,用逗號]
const _ts = URLSearchParams.prototype.toString; URLSearchParams.prototype.toString = function () { return _ts.call(this).replace(/[+]/g, "%20"); };
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
const require = createRequire(import.meta.url);
const api = await import(pathToFileURL(require.resolve('@limrun/api')).href);
const Limrun = api.default?.default ?? api.default, Ios = api.Ios ?? api.default.Ios;
const SP = process.argv[3], OUT = join(SP, 'shots'); mkdirSync(OUT, { recursive: true });
const only = process.argv[4] ? process.argv[4].split(',') : null;
const want = n => !only || only.includes(n);
const apiKey = process.env.LIM_API_KEY ?? readFileSync(join(process.env.USERPROFILE, '.lim', 'config.yaml'), 'utf8').match(/api-key:\s*(\S+)/)[1];
const BUNDLE = 'org.domyweb.shuji', HOLD = '按住一秒半，記一節';
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
let TODAY = new Date(Date.UTC(2026, 10, 24));
const day = n => ymd(new Date(TODAY.getTime() + n * 864e5));
function make({ skipLast = 0, log: lg, letgo, reviewDay = 0, lastReview = -1, n = 45, trigger = '起床喝完第一杯水', floor = '打開檔案寫一句', backup = '如果中午前還沒打開過檔案，就在第一餐吃完時打開', why = '把複雜的事想清楚、寫下來', empty = false, travel = false, flat = false } = {}) {
  const s = { logs: {}, weekly: [], queue: ['坐上蒲團按計時器'], basket: [], travel, settings: { reviewDay },
    habit: { floor, trigger, planted: day(empty ? 0 : -n), travelFloor: travel ? '' : '在手機上寫三行', obstacle: '', backup, why } };
  if (!empty) for (let i = -n; i < 0; i++) { if ([5, 6, 13, 21, 30].includes(i + n)) continue; if (i >= -skipLast) continue; s.logs[day(i)] = { t: 'done' }; }
  if (lg) s.logs[day(0)] = lg;
  if (!empty) for (let i = 5; i >= 0; i--) s.weekly.push({ date: day(lastReview - 7 * i), scores: Array(4).fill(flat ? 4 : Math.max(1, 6 - i)) });
  if (letgo) s.letgo = { start: day(-3), prior: 12 };
  return s;
}
async function load(state, args = []) {
  try { await c.terminateApp(BUNDLE); } catch {}
  await sleep(500);
  const p = join(SP, 'state.json'); writeFileSync(p, JSON.stringify(state));
  await c.pushFile(p, 'Library/Application Support/Shuji/state.json', { bundleId: BUNDLE, containerType: 'data' });
  await simctl(['launch', 'booted', BUNDLE, ...args]); await sleep(2600);
}
const LONGT = '週末早上帶孩子從公園回到家，把鞋子放進櫃子', LONGF = '坐到書桌前打開昨天的稿子補一句話';
const L40T = '每天晚上睡前把手機放到客廳的充電座，再回房間坐到床邊之後了';
const L40F = '拿起床頭的書翻開夾著書籤的那一頁讀三行，讀完把書籤往後移一頁再把書放回去就好';
async function holdShot(name) {
  const f = await frame(HOLD); if (!f) { log('no hold'); return; }
  const x = f.x + f.width / 2, y = f.y + f.height / 2; log('hold frame', JSON.stringify(f));
  await c.startRecording({ touchIndicators: false }); await sleep(800);
  await c.performActions([{ type: 'touchDown', x, y }, { type: 'wait', durationMs: 1300 }, { type: 'touchUp', x, y }]);
  await sleep(1200);
  await c.performActions([{ type: 'touchDown', x, y }, { type: 'wait', durationMs: 1900 }, { type: 'touchUp', x, y }]);
  await sleep(3000); await c.stopRecording({ localPath: join(OUT, name + '.mp4') }); await shot(name + '-done'); await dump(name + '-done');
}
async function states(sfx) {
  const t = async (n, st) => { if (!want(n)) return; await load(st); await shot(n + sfx); await dump(n + sfx); };
  await t('empty', make({ empty: true }));
  await t('todo', make());
  if (want('hold')) { await load(make()); await holdShot('hold' + sfx); }
  if (want('undo') && !sfx) { await load(make({ log: { t: 'done' } })); await tap('復原', 2000); await shot('undo'); await holdShot('undo-hold'); }
  await t('done', make({ log: { t: 'done' } }));
  await t('leave', make({ log: { t: 'leave', reason: '出遠門' } }));
  await t('letgo', make({ letgo: true }));
  await t('absent', make({ skipLast: 16 }));
  await t('missed2', make({ skipLast: 2 }));
  await t('long', make({ trigger: LONGT, floor: LONGF }));
  await t('long40', make({ trigger: L40T, floor: L40F, skipLast: 2, travel: true }));
  await t('ask-grown', make({ log: { t: 'done' }, flat: true }));
  // 四問同一天只跳一次，所以只在淺色那輪走
  if (want('review') && !sfx) { await load(make({ log: { t: 'done' }, lastReview: -9 })); await shot('review'); await dump('review'); for (let i = 1; i <= 4; i++) { const f = (await nodes()).find(x => x.frame?.height > 36 && x.frame?.height < 46 && x.frame?.width > 300 && x.frame?.y > 500 && x.AXLabel)?.frame; if (!f) { log('no scale', i); break; } await c.tap(f.x + f.width * 4.5 / 7, f.y + f.height / 2); await sleep(1100); if (i === 1) await shot('review-q2' + sfx); } await shot('review-after' + sfx); await dump('review-after' + sfx); }
  if (want('field')) { await load(make({ log: { t: 'done' } })); await tap('田', 1500); await shot('field-month' + sfx); await dump('field-month' + sfx); await tap('分析', 1200); await shot('field-charts' + sfx); await tap('竹籃與排隊', 1500); await shot('field-basket' + sfx); await load(make({ log: { t: 'done' } })); await tap('田', 1500); await tap('分析', 1200); try { await c.scroll('down', 620); } catch {} await sleep(1000); await shot('field-charts2' + sfx); await load(make({ empty: true })); await tap('田', 1500); await shot('field-empty' + sfx); await tap('分析', 1200); await shot('field-empty-charts' + sfx); }
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
  await load(make());
  const lab = (await nodes()).map(x => x.AXLabel).filter(Boolean).find(x => /\d+\s*[月\/]\s*\d+/.test(x));
  log('header', lab);
  const m = lab?.match(/(\d+)\s*[月\/]\s*(\d+)/); if (m) { TODAY = new Date(Date.UTC(2026, +m[1] - 1, +m[2])); log('today', ymd(TODAY)); }
  await states('');
  await simctl(['ui', 'booted', 'appearance', 'dark']); await states('-dark'); await simctl(['ui', 'booted', 'appearance', 'light']);
  if (want('settings')) {
    const drag = async () => { try { await c.scroll('down', 620); } catch (e) { log('scroll fail', e.message); } await sleep(1000); };
    const go = async (re, name) => { const f = (await nodes()).find(x => re.test(x.AXLabel || '') && x.frame.y > 40 && x.frame.y < 740); if (!f) { log('row not found', String(re)); return false; } await c.tap(f.frame.x + f.frame.width / 2, f.frame.y + f.frame.height / 2); await sleep(1800); await shot(name); await dump(name); return true; };
    const toBottom = async () => { await tap('設定', 1500); await drag(); await drag(); };
    await load(make()); await tap('設定', 1500); await shot('set1'); await dump('set1');
    await drag(); await shot('set2'); await dump('set2'); await drag(); await shot('set3'); await dump('set3');
    await load(make()); await tap('設定', 1500); await drag(); await drag(); await go(/什麼時候不適合/, 'unfit');
    await load(make()); await tap('設定', 1500); await drag(); await go(/^完整版/, 'paywall');
    await load(make()); await tap('設定', 1500); await drag(); await drag(); await go(/家族|其他.*app|蔬果|更多/i, 'family');
    await simctl(['ui', 'booted', 'appearance', 'dark']); await load(make()); await tap('設定', 1500); await shot('set1-dark'); await drag(); await shot('set2-dark'); await drag(); await shot('set3-dark');
  }
  // 2026-11-25：回來卡、回來那一下、停了一陣子、竹籃、提醒退場、時間卡。每個狀態種下的日子不同，自動問才不會被當成問過
  if (want('back')) {
    const two = n => { const id = 'hab-b' + n, d = []; for (let i = n; i > 0; i--) d.push({ id: 'r' + i, habit: id, kind: 'done', day: day(-i), at: day(-i - 1) + `T${i % 6 === 0 ? 11 : 23}:${10 + (i * 7) % 48}:00Z`, tz: 'Asia/Taipei', source: 'hold' });
      return { v: 2, habit: { id, floor: '坐上蒲團', trigger: '刷完牙', planted: day(-n) }, records: d, reviews: [4, 4.5, 5].map((v, i) => ({ id: 'v' + i, habit: id, date: day(-1 - 7 * (2 - i)), scores: [v, v, v, v] })), marks: [], basket: [], queue: [], settings: { reviewDay: 0 } }; };
    const basket = n => { const s = two(n); s.basket = [{ id: 'p1', floor: '打開檔案寫一句', trigger: '起床喝完第一杯水', nodes: 71, ret: 9, days: 84, planted: day(-130), dug: day(-40) }]; return s; };
    const off = n => { const s = two(n); s.settings.check = true; s.marks = [{ id: 'm1', habit: s.habit.id, kind: 'remindAfterMiss', day: day(-20) }]; return s; };
    for (const [i, sfx] of ['', '-dark'].entries()) {
      await simctl(['ui', 'booted', 'appearance', sfx ? 'dark' : 'light']);
      await load(make({ n: 46 + i, skipLast: 1 })); await shot('b-yesterday' + sfx); await dump('b-yesterday' + sfx);
      if (await tap('沒做', 1500)) { await shot('b-yesterday-why' + sfx); await dump('b-yesterday-why' + sfx); }
      await load(make({ n: 48 + i, skipLast: 5 })); await shot('b-back' + sfx); await dump('b-back' + sfx);
      await tap('旅行', 1800); await shot('b-back-after' + sfx); await holdShot('b-hold' + sfx);
      await load(make({ n: 50 + i, skipLast: 16 })); await shot('b-long' + sfx); await dump('b-long' + sfx);
      await holdShot('b-long-hold' + sfx); if (await tap('上次卡在哪？', 1500)) await shot('b-stuck' + sfx);
      await load(basket(52 + i)); await shot('b-basket' + sfx); await dump('b-basket' + sfx);
      await load(off(54 + i)); await shot('b-remind' + sfx);
      await load(two(56 + i)); await tap('田', 1500); await tap('分析', 1200); try { await c.scroll('down', 620); } catch {} await sleep(1000); await shot('b-time' + sfx); await dump('b-time' + sfx);
    }
    await simctl(['ui', 'booted', 'appearance', 'light']);
  }
  // 2026-11-25：跳過、月曆可點、設定瘦身、AI 頁
  if (want('lazy')) {
    const cal = async (off, name) => { const d = new Date(TODAY.getTime() + off * 864e5); const re = new RegExp('^' + (d.getUTCMonth() + 1) + '月' + d.getUTCDate() + '日'); const f = (await nodes()).find(x => re.test(x.AXLabel || '') && x.frame.x >= 0 && x.frame.x < 402 && x.frame.y > 200); if (!f) { log('cal not found', name); return; } log('cal', f.AXLabel); await c.tap(f.frame.x + f.frame.width / 2, f.frame.y + f.frame.height / 2); await sleep(1500); await shot(name); await dump(name); };
    await load(make()); await shot('z-today'); await tap('跳過', 1500); await shot('z-skip'); await dump('z-skip');
    if (await tap('旅行', 1800)) { await shot('z-skipped'); await dump('z-skipped'); }
    await load(make({ skipLast: 1 })); await tap('田', 1500); await shot('z-month'); await cal(-1, 'z-day-yesterday');
    await load(make()); await tap('田', 1500); await cal(-6, 'z-day-past');
    await load(make()); await tap('設定', 1500); await shot('z-set'); await dump('z-set'); await tap('跳過的理由, 4 個', 1500); await shot('z-reasons'); await dump('z-reasons');
    await load(make()); await tap('設定', 1500); await tap('AI', 1500); await shot('z-ai'); await dump('z-ai');
    await load(make()); await tap('設定', 1500); await tap('我的習慣', 1500); await shot('z-habit');
    await simctl(['ui', 'booted', 'appearance', 'dark']); await load(make()); await tap('跳過', 1500); await shot('z-skip-dark'); if (await tap('旅行', 1800)) await shot('z-skipped-dark'); await load(make()); await tap('設定', 1500); await tap('AI', 1500); await shot('z-ai-dark');
  }
  // 2026-11-25：跟地瓜對答。-talkDemo N 只有 DEBUG 建置認得：1 到 4 步，5 離題，6 等待，7 連兩次離題，8 連不到
  if (want('talk')) {
    const none = { logs: {}, weekly: [], queue: [], basket: [], settings: {} };
    await simctl(['ui', 'booted', 'appearance', 'light']);
    for (const sfx of ['', '-dark']) {
      if (sfx) await simctl(['ui', 'booted', 'appearance', 'dark']);
      for (let n = 1; n <= 8; n++) { await load(none, ['-talkDemo', String(n)]); await shot('talk' + n + sfx); if (!sfx) await dump('talk' + n); }
    }
    await simctl(['ui', 'booted', 'appearance', 'light']);
    await load(none, ['-talkDemo', '2']); await tap('都不是，自己打', 2200); await shot('talk2-key'); await dump('talk2-key');
    await load(none, ['-talkDemo', '3']); await tap('都不是，自己打', 2200); await shot('talk3-key');
    await load(none); await c.tap(150, 666); await sleep(2200); await shot('talk1-key');
    await load(none); await shot('talk-first'); await dump('talk-first');
    await tap('自己填', 1500); await shot('talk-manual'); await dump('talk-manual');
    await load(none); await tap('更多', 1200); await shot('talk-more');
    await load(none); await tap('連電腦的 Claude', 1800); await shot('talk-connect');
    await load({ ...none, queue: ['坐上蒲團按計時器'] }); await shot('talk-queue');
    await load(make()); await tap('設定', 1500); await shot('talk-set'); await tap('重新規劃習慣', 1500); await shot('talk-replan'); await dump('talk-replan');
    if (await tap('重新規劃', 1800)) { await shot('talk-replan-open'); await dump('talk-replan-open'); await tap('自己填', 1500); await shot('talk-replan-manual'); }
  }
  log('DONE');
} catch (e) { log('ERROR', e.stack || e); process.exitCode = 1; }
finally {
  try { c?.disconnect(); } catch {}
  if (inst) { try { await lim.iosInstances.delete(inst.metadata.id); log('deleted'); } catch (e) { log('DELETE FAILED', inst.metadata.id, e.message); } }
  process.exit();
}
