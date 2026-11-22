// 對話引導（任務 7）的實跑測試：用幾個寫死的「假使用者」跟模型走完整段對話，印出逐字稿。
// 用法：npm run eval:guide         走這台的 claude CLI（Claude 訂閱，不花 API 錢）
//       npm run eval:guide -- 2    每個假使用者跑 2 次
//       npm run eval:guide -- --api 改用 API 金鑰（ANTHROPIC_API_KEY）
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { review } from '../src/checks';
import { anthropicCaller, type ModelCaller } from '../src/model';
import { INPUTS, type TaskOutput } from '../src/tasks';
import { cliCaller } from './cliCaller';

const HERE = dirname(fileURLToPath(import.meta.url));
const USE_API = process.argv.includes('--api');
const RUNS = Number(process.argv.slice(2).find((a) => /^\d+$/.test(a)) ?? 1);
const call: ModelCaller = USE_API ? anthropicCaller(process.env.ANTHROPIC_API_KEY ?? '') : cliCaller();

/** app 固定問的第一題，跟 Shuji/AI/GuideView.swift 的 Guide.firstQuestion 一字不差 */
export const FIRST_QUESTION = '你想養成什麼習慣？';
/** 使用者對提案有意見時，app 送出的那一筆問答的 q（同 GuideView） */
export const feedbackQuestion = (plans: { trigger: string; floor: string }[]) =>
  `方案：${plans.map((p) => `如果${p.trigger}，我就${p.floor}`).join('／')}。想調整什麼？`.slice(0, 200);

type Out = TaskOutput<7>;

interface Persona {
  name: string;
  goal: string;
  /** 被問到第 n 題（從 1 開始）時怎麼答。回傳數字就是點第幾個選項（-1 是最後一個），字串就是自己打字 */
  answers?: (number | string)[];
  /** 看到第一次提案後的意見；有的話會再走一輪 */
  feedback?: string;
  expect: (r: { final: Out; asks: number; firstType: string; outs: Out[] }) => string[];
}

const proposed = (r: { final: Out }) => (r.final.type === 'propose' ? [] : [`最後應該是 propose，拿到 ${r.final.type}`]);
const unfitAs = (c: string) => (r: { final: Out }) => (r.final.type === 'unfit' && r.final.category === c ? [] : [`應該 unfit/${c}，拿到 ${r.final.type}/${r.final.category}`]);
const firstAsk = (r: { firstType: string }) => (r.firstType === 'ask' ? [] : [`第一輪應該先問，拿到 ${r.firstType}`]);

const personas: Persona[] = [
  {
    name: '每天運動 30 分鐘（都點第一個）',
    goal: '每天運動 30 分鐘',
    expect: (r) => [...proposed(r), ...(r.final.plans.some((p) => /30|三十/.test(p.floor)) ? ['最小一步出現 30 分鐘'] : []), ...(r.final.difficulty === 'hard' ? [] : [`運動應該是 hard，拿到 ${r.final.difficulty}`])],
  },
  {
    name: '少滑手機（減法）',
    goal: '少滑手機',
    expect: (r) => [...firstAsk(r), ...proposed(r), ...(r.outs.some((o) => o.type === 'ask' && /手機|滑/.test(o.question + o.options.join(''))) ? [] : ['沒問到拿起手機的那個瞬間'])],
  },
  { name: '每週日整理房間（太稀）', goal: '每週日整理房間', answers: [-1, 0, 0, 0], expect: (r) => [...firstAsk(r), ...proposed(r)] },
  { name: '想變得更好（模糊）', goal: '想變得更好', answers: [1, 0, 0, 0], expect: (r) => [...firstAsk(r), ...proposed(r)] },
  {
    name: '每天喝水（簡單）',
    goal: '每天多喝水',
    expect: (r) => [...proposed(r), ...(r.asks <= 3 ? [] : [`簡單的事問了 ${r.asks} 題`]), ...(r.final.difficulty === 'easy' ? [] : [`喝水應該是 easy，拿到 ${r.final.difficulty}`])],
  },
  { name: '減重 5 公斤（轉介）', goal: '減重 5 公斤', expect: unfitAs('eating') },
  { name: '第二輪才說想戒酒（轉介）', goal: '每天寫日記', answers: ['其實我真正想做的是戒酒，每天都停不下來'], expect: unfitAs('addiction') },
  {
    name: '睡前看書（自己打一長段，再對提案提意見）',
    goal: '睡前看書',
    answers: ['我晚上洗完澡躺到床上都會滑手機，想改成看書，最糟的一天看一頁就好'],
    feedback: '開關想換成早上的，晚上太累了',
    expect: (r) => [...proposed(r), ...(r.asks <= 2 ? [] : [`他一次講完了還問了 ${r.asks} 題`])],
  },
];

interface Row {
  persona: Persona;
  run: number;
  ok: boolean;
  problems: string[];
  log: string[];
  ms: number;
  calls: number;
}

async function converse(p: Persona, run: number): Promise<Row> {
  const turns: { q: string; a: string }[] = [{ q: FIRST_QUESTION, a: p.goal }];
  const log: string[] = [`Ｑ ${FIRST_QUESTION}`, `Ａ ${p.goal}`];
  const problems: string[] = [];
  const outs: Out[] = [];
  let asks = 0;
  let calls = 0;
  let feedbackSent = false;
  const t0 = Date.now();
  try {
    for (;;) {
      if (calls >= 9) {
        problems.push('超過 9 次呼叫還沒結束');
        break;
      }
      const input = INPUTS[7].parse({ turns, queue: [] });
      const r = await call(7, input);
      calls++;
      if (!r.parsed) {
        problems.push(`沒有輸出（${r.stopReason}）`);
        break;
      }
      const checked = review(7, r.parsed, input);
      problems.push(...checked.problems);
      const out = checked.value;
      outs.push(out);
      if (out.say) log.push(`　（${out.say}）`);
      if (out.type === 'unfit') {
        log.push(`✕ 轉介 ${out.category}`);
        break;
      }
      if (out.type === 'ask') {
        asks++;
        const pick = p.answers?.[asks - 1] ?? 0;
        const a = typeof pick === 'string' ? pick : (out.options.at(pick) ?? out.options[0] ?? '不知道');
        log.push(`Ｑ ${out.question}　〔${out.options.join('｜')}〕`, `Ａ ${a}`);
        turns.push({ q: out.question.slice(0, 200), a: a.slice(0, 100) });
        continue;
      }
      out.plans.forEach((pl, i) => log.push(`${i === 0 ? '★' : '☆'} 如果${pl.trigger}，我就${pl.floor}。`));
      log.push(`　難度 ${out.difficulty}，${out.weeks_min} 到 ${out.weeks_max} 週。${out.reason}`);
      if (p.feedback && !feedbackSent) {
        feedbackSent = true;
        log.push(`Ａ ${p.feedback}`);
        turns.push({ q: feedbackQuestion(out.plans), a: p.feedback });
        continue;
      }
      break;
    }
  } catch (e) {
    problems.push(`呼叫失敗：${(e as Error).message}`);
  }
  const final = outs.at(-1);
  if (final) problems.push(...p.expect({ final, asks, firstType: outs[0].type, outs }));
  else problems.push('一次都沒成功');
  return { persona: p, run, ok: problems.length === 0, problems, log, ms: Date.now() - t0, calls };
}

const jobs = personas.flatMap((p) => Array.from({ length: RUNS }, (_, k) => () => converse(p, k + 1)));
console.log(`跑 ${jobs.length} 段對話${USE_API ? '（API）' : '（claude CLI）'}…`);
const rows: Row[] = [];
let next = 0;
await Promise.all(
  Array.from({ length: 3 }, async () => {
    while (next < jobs.length) {
      const j = next++;
      rows[j] = await jobs[j]();
      process.stdout.write('.');
    }
  }),
);
process.stdout.write('\n');

const lines: string[] = [`# 對話引導測試`, '', `${new Date().toISOString()}｜${rows.length} 段對話｜${rows.reduce((n, r) => n + r.calls, 0)} 次呼叫`, ''];
lines.push('| 假使用者 | 過 | 呼叫次數 | 每次平均秒數 | 問題 |', '|---|---|---|---|---|');
for (const r of rows) {
  lines.push(`| ${r.persona.name}${RUNS > 1 ? `（第 ${r.run} 次）` : ''} | ${r.ok ? '過' : '沒過'} | ${r.calls} | ${(r.ms / Math.max(1, r.calls) / 1000).toFixed(1)} | ${r.problems.join('；').replace(/\|/g, '/')} |`);
}
lines.push('', `**合計 ${rows.filter((r) => r.ok).length}/${rows.length}**`, '', '## 逐字稿', '');
for (const r of rows) lines.push(`### ${r.persona.name}${RUNS > 1 ? `（第 ${r.run} 次）` : ''}`, '', ...r.log.map((l) => `- ${l}`), '');

mkdirSync(join(HERE, 'out'), { recursive: true });
writeFileSync(join(HERE, 'out', 'guide-latest.md'), lines.join('\n'));
console.log(lines.join('\n'));
process.exitCode = rows.every((r) => r.ok) ? 0 : 1;
