// 薯記 iOS 版：在 Limrun 雲端 iPhone 模擬器走一遍主流程，截圖存到 shots/。
// 準備：npm install（這個資料夾）；~/.lim/config.yaml 要有 api-key；Limrun 帳號要有點數或訂閱。
// 用法：node test.mjs <Shuji-simulator.app.zip>
//   zip 從 GitHub Actions 的 artifact「Shuji-simulator-app」下載（gh run download <run id> -n Shuji-simulator-app）。
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import Limrun, { Ios } from '@limrun/api';

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = join(HERE, 'shots');
mkdirSync(OUT, { recursive: true });

const home = process.env.USERPROFILE ?? process.env.HOME;
const cfg = readFileSync(join(home, '.lim', 'config.yaml'), 'utf8');
const apiKey = process.env.LIM_API_KEY ?? (cfg.match(/api-key:\s*(\S+)/) ?? [])[1];
if (!apiKey) { console.error('no api key in ~/.lim/config.yaml'); process.exit(2); }

const ZIP = process.argv[2];
if (!ZIP) { console.error('usage: node test.mjs <app.zip>'); process.exit(2); }
const BUNDLE = 'org.domyweb.shuji';
const HOLD = '按住一秒半，記一節';
const lim = new Limrun({ apiKey });
const t0 = Date.now();
const log = (...a) => console.log(((Date.now() - t0) / 1000).toFixed(1).padStart(6) + 's', ...a);
const sleep = ms => new Promise(r => setTimeout(r, ms));
const results = [];
const check = (name, ok, note = '') => { results.push({ name, ok, note }); log(ok ? 'PASS' : 'FAIL', name, note); };

let inst = null;
let c = null;

function flat(n, out = []) {
  if (Array.isArray(n)) { for (const x of n) flat(x, out); return out; }
  if (!n || typeof n !== 'object') return out;
  out.push(n);
  for (const ch of n.children ?? []) flat(ch, out);
  return out;
}
async function nodes() { return flat(await c.elementTree()); }
async function labels() { return (await nodes()).filter(n => n.AXLabel).map(n => n.AXLabel); }
async function dump(name) {
  try {
    const ls = await labels();
    log('labels@' + name + ' (' + ls.length + '):', JSON.stringify(ls.slice(0, 60)));
  } catch (e) { log('dump failed', e?.message); }
}
async function shot(name) {
  try {
    const s = await c.screenshot({ format: 'jpeg', size: 'scaled' });
    writeFileSync(join(OUT, name + '.jpg'), Buffer.from(s.base64, 'base64'));
    log('shot', name, s.width + 'x' + s.height);
  } catch (e) { log('shot failed', name, e?.message); }
}
async function tapLabel(l, { contains = false, wait = 500 } = {}) {
  try {
    await c.tapElement(contains ? { AXLabelContains: l } : { AXLabel: l });
    log('tap', JSON.stringify(l));
    await sleep(wait);
    return true;
  } catch (e) {
    log('tap FAILED', JSON.stringify(l), (e?.message ?? String(e)).slice(0, 160));
    return false;
  }
}
async function tapField(placeholder) {
  // SwiftUI 的 TextField 在無障礙樹裡通常用 placeholder 當 label；找不到就點第一個 TextField
  if (await tapLabel(placeholder, { wait: 400 })) return true;
  const tf = (await nodes()).find(n => /textfield/i.test(n.type) || /text field/i.test(n.role_description ?? ''));
  if (!tf) { log('no textfield found'); return false; }
  const f = tf.frame;
  await c.tap(f.x + f.width / 2, f.y + f.height / 2);
  log('tap textfield by frame', JSON.stringify(f));
  await sleep(400);
  return true;
}
async function type(text) {
  try { await c.typeText(text); log('typed', JSON.stringify(text)); await sleep(300); }
  catch (e) { log('type FAILED', e?.message); }
}
async function has(l, { exact = false } = {}) {
  try { return (await labels()).some(x => exact ? x === l : (x === l || x.includes(l))); } catch { return false; }
}
async function frameOf(label) {
  const n = (await nodes()).find(x => x.AXLabel === label);
  return n?.frame ?? null;
}
/// 按住：touchDown → 等 → touchUp。drift 是按住期間手指滑開幾點（原型容許 40 點內）。
async function hold(ms, drift = 0) {
  const f = await frameOf(HOLD);
  if (!f) { log('hold button not found'); return false; }
  const x = f.x + f.width / 2, y = f.y + f.height / 2;
  const acts = [{ type: 'touchDown', x, y }];
  if (drift) {
    acts.push({ type: 'wait', durationMs: 150 });
    acts.push({ type: 'touchMove', x: x + drift, y: y + drift / 2 });
  }
  acts.push({ type: 'wait', durationMs: ms });
  acts.push({ type: 'touchUp', x: x + drift, y: y + (drift ? drift / 2 : 0) });
  try { await c.performActions(acts); log('hold', ms + 'ms', 'drift', drift, 'at', Math.round(x) + ',' + Math.round(y)); return true; }
  catch (e) { log('hold FAILED', e?.message); return false; }
}
async function allowIfAsked() {
  for (const l of ['Allow', '允許', 'OK']) {
    if (await has(l, { exact: true })) { await tapLabel(l, { wait: 800 }); log('permission alert answered', l); return true; }
  }
  return false;
}
async function relaunch() {
  try { await c.terminateApp(BUNDLE); } catch (e) { log('terminate failed', e?.message); }
  await sleep(800);
  try { await c.simctl(['launch', 'booted', BUNDLE]); } catch (e) { log('relaunch failed', e?.message); }
  await sleep(3000);
}
async function goPage(name) { // 田 / 今天 / 設定：上面那排小點
  if (!(await tapLabel(name, { wait: 900 }))) {
    const dir = name === '田' ? 'right' : 'left';
    try { await c.scroll(dir, 600); } catch {}
    await sleep(900);
  }
}

try {
  log('uploading', ZIP);
  const asset = await lim.assets.getOrUpload({ path: ZIP, name: 'shuji-sim-' + Date.now() + '.zip', platform: 'ios', kind: 'App', ttl: '2h' });
  log('asset', asset.name, asset.id);

  log('creating instance');
  inst = await lim.iosInstances.create({
    wait: true,
    spec: {
      model: 'iphone',
      inactivityTimeout: '5m',
      hardTimeout: '25m',
      initialAssets: [{ kind: 'App', source: 'AssetName', assetName: asset.name, launchMode: 'RelaunchIfRunning' }],
    },
  });
  log('instance', inst.metadata?.id, inst.status?.state);

  c = await Ios.createInstanceClient({ apiUrl: inst.status.apiUrl, token: inst.status.token, logLevel: 'none' });
  log('connected');
  await sleep(4000);
  await shot('01-launch');
  await dump('launch');
  if (!(await has('種一個習慣'))) {
    log('app not in front, launching via simctl');
    try { await c.simctl(['launch', 'booted', BUNDLE]); } catch (e) { log('simctl launch failed', e?.message); }
    await sleep(3000);
    await shot('01b-launch');
    await dump('launch2');
  }
  check('首次打開停在「種一個習慣」', await has('種一個習慣'));

  // 首次設定兩步
  await tapField('打開檔案寫一句');
  await type('打開檔案寫一句');
  await shot('02-ob1-typed');
  await tapLabel('下一步', { wait: 900 });
  await shot('03-ob2');
  check('第二步出現「掛在哪裡」', await has('掛在哪裡'));
  await tapField('起床喝完第一杯水');
  await type('起床喝完第一杯水');
  await shot('04-ob2-typed');
  await tapLabel('種下去', { wait: 1500 });
  await allowIfAsked();
  await shot('05-main-empty');
  await dump('main');
  check('種下去後進主畫面，有按住鈕', await has(HOLD));
  check('主畫面顯示第 0 節', await has('第 0 節'));

  // 短按不該記；按住一秒半才記
  const f = await frameOf(HOLD);
  if (f) { await c.tap(f.x + f.width / 2, f.y + f.height / 2); await sleep(900); }
  check('短按一下不會記', !(await has('今天記好了')));
  await hold(1800);
  await sleep(1400);
  await shot('06-after-hold');
  await dump('after-hold');
  check('按住一秒半後變成「今天記好了」', await has('今天記好了'));
  check('節數變 1', await has('第 1 節'));

  // 更多選項：撤銷今天，再按住時手指滑開 15 點也要算
  await tapLabel('今天記好了，更多選項', { wait: 900 });
  await shot('07-more-sheet');
  await dump('more');
  await tapLabel('撤銷今天', { wait: 1200 });
  await shot('08-undone');
  check('撤銷後回到按住', await has(HOLD));
  await hold(1800, 15);
  await sleep(1400);
  await shot('09-hold-with-drift');
  check('按住時手指滑開 15 點仍記得到', await has('今天記好了'));

  // 三頁橫排：點小點與滑頁
  await goPage('田');
  await shot('10-field');
  await dump('field');
  check('田頁有「根」的數字', await has('根'));
  await goPage('設定');
  await shot('11-settings');
  check('設定頁有「開關句」', await has('開關句'));
  // 收工檢查：開了會問通知權限
  if (await tapLabel('收工檢查', { wait: 1200 })) {
    const asked = await allowIfAsked();
    await shot('11b-check-on');
    await dump('check-on');
    check('開收工檢查會問通知權限', asked, asked ? '' : '沒看到系統彈窗（可能已授權或被略過）');
  }
  check('正式版區塊沒有全部清除在資料區（Debug 建置會在測試區）', (await labels()).filter(l => l === '全部清除').length <= 1);
  try { await c.scroll('down', 1500); } catch {}
  await sleep(700);
  await shot('12-settings-bottom');
  await dump('settings-bottom');
  check('Debug 建置有測試區', await has('測試區'));

  // 載入示範資料 → 今天與田
  await tapLabel('載入示範資料', { contains: true, wait: 1800 });
  await shot('13-demo-loaded');
  await dump('demo-main');
  check('示範資料載入後在今天頁', await has('今天'));
  await goPage('田');
  await shot('14-demo-field');
  await dump('demo-field');
  try { await c.scroll('down', 900); } catch {}
  await sleep(700);
  await shot('15-demo-field-bottom');
  await dump('demo-field-bottom');

  // 往後一天再按住：今天沒記 → 按住 → 記好
  await goPage('設定');
  try { await c.scroll('down', 1500); } catch {}
  await sleep(600);
  await tapLabel('往後一天', { wait: 1200 });
  await goPage('今天');
  await shot('16-next-day');
  await dump('next-day');
  if (await has(HOLD)) {
    await hold(1800);
    await sleep(1400);
    await shot('17-next-day-done');
    check('往後一天按住記得到', await has('今天記好了'));
  } else {
    check('往後一天後主畫面有按住鈕', false, '沒看到按住鈕，看 16-next-day.jpg');
  }

  // 開始四問（田頁或今天頁的連結）
  await goPage('田');
  if (await tapLabel('做這週的開始四問', { contains: true, wait: 1000 })) {
    await shot('18-review');
    await dump('review');
    await tapLabel('記下這週', { wait: 1200 });
    await shot('19-review-done');
    check('開始四問記完後關掉', !(await has('記下這週')));
  } else {
    log('田頁沒有開始四問按鈕（可能這週已做）');
  }

  // 關掉重開，資料還在
  await relaunch();
  await shot('20-relaunch');
  await dump('relaunch');
  check('重開後不回首次設定', !(await has('種一個習慣')));

  // 深色模式
  try {
    await c.simctl(['ui', 'booted', 'appearance', 'dark']);
    await sleep(1200);
    await shot('21-dark-today');
    await goPage('田');
    await shot('22-dark-field');
    await goPage('設定');
    await shot('23-dark-settings');
    await c.simctl(['ui', 'booted', 'appearance', 'light']);
  } catch (e) { log('appearance failed', e?.message); }

  // 全部清除（只有 Debug 測試區有）→ 回到首次設定
  await goPage('設定');
  try { await c.scroll('down', 1500); } catch {}
  await sleep(600);
  if (await tapLabel('全部清除', { wait: 1000 })) {
    await shot('24-wipe-confirm');
    await dump('wipe-confirm');
    await tapLabel('清除全部，不可復原', { wait: 1500 });
    await shot('25-after-wipe');
    check('全部清除後回到「種一個習慣」', await has('種一個習慣'));
  } else {
    check('測試區有全部清除', false);
  }

  log('DONE');
} catch (e) {
  log('ERROR', e?.message ?? String(e));
  if (e?.status) log('http', e.status, JSON.stringify(e.error ?? e.body ?? e.cause ?? '').slice(0, 500));
  process.exitCode = 1;
} finally {
  if (c) { try { c.disconnect(); } catch {} }
  if (inst?.metadata?.id) {
    try { await lim.iosInstances.delete(inst.metadata.id); log('instance deleted', inst.metadata.id); }
    catch (e) { log('DELETE FAILED (clean up manually!)', inst.metadata.id, e?.message); }
  }
  const fails = results.filter(r => !r.ok);
  log('結果：' + (results.length - fails.length) + ' 過，' + fails.length + ' 沒過');
  for (const r of fails) log('  FAIL', r.name, r.note);
  writeFileSync(join(OUT, 'results.json'), JSON.stringify(results, null, 2));
  log('total', ((Date.now() - t0) / 1000).toFixed(0) + 's');
}
