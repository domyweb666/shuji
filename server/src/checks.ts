import { BANNED_LINES, REFERRAL, REFERRAL_EATING } from './generated/packs';
import type { TaskId, TaskInput, TaskOutput } from './tasks';

// 模型輸出的第二道關：結構化輸出保證 JSON 合法、欄位都在；這裡管內容。
// 檢查不過 → 伺服器重問一次 → 再不過就回 bad_output，app 回手動流程。

/**
 * 護欄包第四節禁用清單，一行對一組 pattern。
 * 行數跟 BANNED_LINES 對不上時，測試會失敗，逼人回來補。
 */
export const BANNED_PATTERNS: RegExp[][] = [
  // 21 天、66 天、X 天養成習慣、連續 X 天
  [/(21|66|二十一|六十六)\s*天/, /[0-9０-９一二三四五六七八九十百]+\s*天(就能|就會|可以)?養成/, /連續\s*[0-9０-９一二三四五六七八九十百]+\s*天/],
  // 不要斷、別破壞紀錄、streak、保持連勝
  [/不要斷/, /別破壞紀錄/, /streak/i, /連勝/],
  // 前功盡棄、白費、歸零、重新開始
  [/前功盡棄/, /白費/, /歸零/, /重新開始/],
  // 意志力、自律、毅力、靠決心、撐下去
  [/意志力/, /自律/, /毅力/, /靠決心/, /撐下去/],
  // 「我是＿＿的人」這類身分宣告
  [/我是[^，。、！？\s]{1,10}的人/],
  // 每天進步 1%、複利
  [/進步\s*1\s*[%％]/, /複利/],
  // 戒掉、刪除壞習慣、根除
  [/戒掉/, /刪除壞習慣/, /根除/],
  // 多巴胺、大腦獎勵你
  [/多巴胺/, /大腦獎勵/],
  // 新年新開始、星期一重新出發、從今天開始改變
  [/新年新開始/, /星期一重新出發/, /從今天開始改變/],
  // 保證、一定會、科學證實會讓你
  // 「一定會」擋的是保證成效（一定會成功、一定會養成）。描述開關的寫法要放行：
  // 「躺下之前一定會發生的動作」「住處一定會經過的事」是書要的挑法，實跑約每 40 次出現 1 次。
  // 只放行後面接這幾個描述事件的詞，其他一律照擋。
  [/保證/, /一定會(?!發生|經過|出現|碰到|遇到|用到|走過|路過|看到|做的)/, /科學證實/],
];

/** 搭建知識包第六節的否定句硬規則（不、別、戒、少、停止、避免、減少） */
// 「別」只算勸阻的用法（別滑手機）；「別的事」「別人」「特別」「分別」這些不是否定，實跑被誤擋過
export const NEGATION = /不|(?<![特分個類區性])別(?![的人處])|戒|停止|避免|減少|少(?:做|吃|喝|滑|看|用|玩|買|碰|抽)/;

/** 週回顧 summary 不准有數字（測試清單第 7 條）。
 *  診斷知識包第七節明文允許「週末那兩天開關好像沒出現」，所以中文數字不擋，只擋阿拉伯數字與百分比 */
const DIGITS = /[0-9０-９%％]/;
/** 三問診斷不准提停了幾天 */
const GAP_DAYS = /[0-9０-９一二三四五六七八九十兩]+\s*天/;

export const DIAGNOSE_CLOSING = '不是你的問題，是設計有洞，改好了就從這一節接上。';
export const DIAGNOSE_NOTHING = '設計看起來沒問題，可能只是那陣子生活變了。從這一節接上就好。';
/** 對話引導估的週數：模型沒給或給得不合理時，照難度用這張表 */
export const GUIDE_WEEKS: Record<'easy' | 'medium' | 'hard', [number, number]> = { easy: [4, 8], medium: [8, 12], hard: [10, 20] };
const QUANTITY = /[0-9０-９]+\s*(分鐘|次|字|頁|下|公里|小時)/;

export const AUDIT_WARNS = ['時機和環境留著，只拆記錄', '加量和加新習慣不要同一季', '有些結果要好幾季才看得到'];

// ---------- 任務 8、9：離題與注入的最後一道 ----------

/** 使用者打得到字的任務，輸出裡不准出現的東西 */
const UNSAFE: [RegExp, string][] = [
  [/[\r\n\t]/, '換行'],
  [/[<>{}`]/, '半形符號'],
  [/https?:|www\.|[a-z0-9-]+\.(com|tw|org|net|io|dev|ai|me|cn)(?![a-z])/i, '網址'],
  [/\b(import|def|print|console|function|const|return|select|lambda)\b|==|=>|\(\)|;|\\/i, '程式碼'],
  [/系統提示|提示詞|提示內容|system\s*prompt|語言模型|人工智慧|claude|anthropic|chat\s*gpt|\bgpt|openai|gemini/i, '提到 AI 或系統提示'],
  // 只擋講自己：「打開 AI 課程」這種習慣要放行
  [/(我是|我只是|身為|作為|本)\s*(一個|一款|個)?\s*(AI|助理|機器人|顧問|模型)|AI\s*(助理|助手|模型)/i, '提到 AI 自己'],
];

export function unsafeHits(text: string): string[] {
  return UNSAFE.filter(([re]) => re.test(text)).map(([, name]) => `${name}：${text.slice(0, 40)}`);
}

/** 天數、週數由程式填，AI 一律不講。「每天」「一天」放行 */
const DURATION = /[0-9０-９二兩三四五六七八九十百幾]\s*多?\s*(天|週|周(?!末)|個?星期|個?禮拜|個月)|一\s*(週|周(?!末)|個?星期(?![一二三四五六日天])|個?禮拜|個月)/;
/** 最小一步不帶量。QUANTITY 只管阿拉伯數字，這裡連中文數字的時間長度一起擋 */
const TIME_SPAN = /[0-9０-９一二兩三四五六七八九十半幾]\s*(分鐘|小時|公里)/;
/** 時機要是一個瞬間：不是時段、不是鐘點、不在手機裡 */
const NOT_A_MOMENT = /有空|空檔|[0-9０-９]|[一二兩三四五六七八九十]點|鬧鐘|通知|提醒|^(早上|中午|下午|晚上|睡前)$/;

/** 畫面上看到的字數（一個中文字、一個表情都算一個） */
const len = (s: string) => [...s].length;
/** 比對「是不是同一個選項」：不看空白和標點 */
const same = (s: string) => s.replace(/[\s，。、,.！!？?「」]/g, '');
/** 時機寫成已完成的瞬間：「刷完牙之後」「闔上筆電時」都收成「刷完牙」「闔上筆電」 */
const tidyTrigger = (s: string) =>
  s
    .trim()
    .replace(/^如果/, '')
    .replace(/[，,。.]$/, '')
    .replace(/，?我就$/, '')
    .replace(/(?<=.{2})(的時候|的?那一刻|之後|以後|(?<!最)後|(?<!小)時)$/, '');
const tidyFloor = (s: string) => s.trim().replace(/^我就/, '').replace(/[。.]$/, '');
const tidyLine = (s: string) => s.trim().replace(/請假/g, '跳過');

/** pattern=none 時不准講的：任何聽起來像規律的字 */
const PATTERN_WORDS = /週末|周末|平日|六日|假日|上班日|總是|常常|每次|老是|通常|往往|容易|規律|多半|大多|比較|比[^比]{0,6}(少|多)|習慣性/;
/** usual_time 只拿來挑時機，時間不寫出來。「漏了一點」這種不是鐘點，放行 */
const CLOCK = /[0-9０-９二兩三四五六七八九十]\s*點|十一點|一點[多半鐘]/;
const TIME_OF_DAY = /清晨|凌晨|早上|上午|中午|下午|傍晚|晚上|半夜/;
const CAUSE = /因為|所以|由於|導致|害你|害得|原因|太累|太忙/;

function cnNumber(s: string): number {
  const d: Record<string, number> = { 零: 0, 一: 1, 二: 2, 兩: 2, 三: 3, 四: 4, 五: 5, 六: 6, 七: 7, 八: 8, 九: 9 };
  if (/^[0-9]+$/.test(s)) return Number(s);
  const m = s.match(/^([一二三四五六七八九])?十([一二三四五六七八九])?$/);
  if (m) return (m[1] ? d[m[1]] : 1) * 10 + (m[2] ? d[m[2]] : 0);
  return d[s] ?? -1;
}

/** 發現裡每一個「N 天」「N 次」都要是輸入裡有的數字；講「這週」就只能用這週的，漏、做、跳過各自對 */
function wrongNumbers(finding: string, i: TaskInput<9>): string[] {
  const w = i.week;
  const known = [w.done, w.possible, w.missed.length, w.skipped.length];
  if (!finding.includes('這週')) {
    known.push(i.weekday.done, i.weekday.days, i.weekday.days - i.weekday.done, i.weekend.done, i.weekend.days, i.weekend.days - i.weekend.done, ...i.reasons.map((r) => r.count));
  }
  const bad: string[] = [];
  for (const m of finding.matchAll(/(漏了?|做了?|跳過了?)?([0-9]+|[一二兩三四五六七八九十]+)s*(天|次)/g)) {
    const n = cnNumber(m[2]);
    const verb = finding.includes('這週') ? m[1]?.[0] : undefined;
    const want = verb === '漏' ? w.missed.length : verb === '做' ? w.done : verb === '跳' ? w.skipped.length : null;
    if (want === null ? !known.includes(n) : n !== want) bad.push(`數字對不上：${m[0]}`);
  }
  return bad;
}

export interface CheckResult<T> {
  ok: boolean;
  problems: string[];
  value: T;
}

/** 物件裡所有給人看的字串（type、category、field 這類代碼除外） */
function visibleStrings(v: unknown, key = ''): string[] {
  const codeKeys = new Set(['type', 'category', 'field', 'rival_type', 'verdict', 'path', 'difficulty']);
  if (typeof v === 'string') return codeKeys.has(key) ? [] : [v];
  if (Array.isArray(v)) return v.flatMap((x) => visibleStrings(x, key));
  if (v && typeof v === 'object') return Object.entries(v).flatMap(([k, x]) => visibleStrings(x, k));
  return [];
}

export function bannedHits(text: string): string[] {
  const hits: string[] = [];
  BANNED_PATTERNS.forEach((group, i) => {
    for (const re of group) if (re.test(text)) hits.push(`禁用詞（${BANNED_LINES[i] ?? i}）：${re}`);
  });
  return hits;
}

/** 給使用者看的字不講「開關」（WORDING_RULE 的第二道）。電燈開關、按下開關這種真的東西不換 */
export function plainWording(s: string): string {
  return s.replace(/開關句/g, '習慣').replace(/(?<![燈源扇器電按下打離])開關(?![燈門機])/g, '時機');
}

/** 整份輸出裡給人看的字串都換一遍 */
function plainDeep(v: unknown): unknown {
  if (typeof v === 'string') return plainWording(v);
  if (Array.isArray(v)) return v.map(plainDeep);
  if (v && typeof v === 'object') return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, plainDeep(x)]));
  return v;
}

const negated = (s: string) => NEGATION.test(s);

/**
 * 整理並檢查一份輸出。會改的東西：
 * - 給人看的字裡的「開關」換成「時機」
 * - 任務 1 的 example 用 floors[0]、triggers[0] 重組（保證跟候選一致）
 * - 任務 4 的 closing 換成固定句；layer 0 時換成固定建議
 * - 任務 6 的 warn 不在三句之內就清空
 * - 非 ok 的時候把候選陣列清空
 * - 任務 7 的選項去重、週數夾在合理範圍；ask 與 propose 各自用不到的欄位清空
 * - 任務 8、9 只留那一種 type 用得到的欄位；off_topic、unfit 的字整個丟掉
 * input 給任務 7（題數用完還在問）、8（步驟、換一批）、9（數字對不對）用
 */
export function review<T extends TaskId>(task: T, raw: TaskOutput<T>, input?: unknown): CheckResult<TaskOutput<T>> {
  const problems: string[] = [];
  const out = plainDeep(structuredClone(raw)) as any;

  if (out.type === 'unfit') {
    if (!out.category) problems.push('unfit 沒有 category');
    if ((task as TaskId) === 8) Object.assign(out, { lead: '', options: [], difficulty: null, message: null });
    if ((task as TaskId) === 9) Object.assign(out, { finding: '', change: null, message: null });
    return { ok: problems.length === 0, problems, value: out };
  }

  switch (task) {
    case 1: {
      if (out.type === 'ok') {
        out.floors = out.floors.map((s: string) => s.trim()).filter(Boolean).slice(0, 3);
        out.triggers = out.triggers.map((s: string) => s.trim()).filter(Boolean).slice(0, 6);
        if (out.floors.length === 0) problems.push('沒有最小一步候選');
        if (out.triggers.length === 0) problems.push('沒有開關候選');
        out.floors.forEach((f: string) => negated(f) && problems.push(`最小一步有否定詞：${f}`));
        if (out.floors[0] && out.triggers[0]) out.example = `如果${out.triggers[0]}，我就${out.floors[0]}。`;
        if (/[0-9０-９]+\s*(分鐘|次|字|頁)/.test(out.floors[0] ?? '')) problems.push('最小一步帶了量');
      } else {
        out.floors = [];
        out.triggers = [];
        out.example = '';
        if (!out.message) problems.push(`${out.type} 沒有 message`);
      }
      break;
    }
    case 2: {
      out.obstacles = out.obstacles.slice(0, 2);
      out.obstacles.forEach((o: { then: string }) => negated(o.then) && problems.push(`障礙版替代動作有否定詞：${o.then}`));
      if (out.backup && negated(out.backup.split('就').pop() ?? '')) problems.push('備用開關有否定詞');
      break;
    }
    case 4: {
      out.closing = DIAGNOSE_CLOSING;
      if (out.layer === 0) {
        out.field = null;
        out.suggestion = DIAGNOSE_NOTHING;
      } else {
        if (!out.field) problems.push('有 layer 卻沒有 field');
        if (negated(out.suggestion)) problems.push(`建議有否定詞：${out.suggestion}`);
      }
      if (GAP_DAYS.test(out.suggestion) || GAP_DAYS.test(out.why)) problems.push('提到停了幾天');
      break;
    }
    case 5: {
      if (DIGITS.test(out.summary)) problems.push(`週回顧 summary 有數字：${out.summary}`);
      if (/完成率|比上週|漏了/.test(out.summary)) problems.push('週回顧 summary 有統計句');
      if (out.verdict === 'fine') out.fix = null;
      if (out.verdict === 'fix' && !out.fix) problems.push('verdict fix 卻沒有 fix');
      break;
    }
    case 6: {
      if (out.warn && !AUDIT_WARNS.includes(out.warn.replace(/[。.]$/, ''))) out.warn = '';
      if (/再加一個習慣|加一個新習慣|同時養/.test(out.change)) problems.push('季稽核建議加習慣');
      break;
    }
    case 7: {
      out.say = out.say.trim();
      if (out.type === 'ask') {
        out.question = out.question.trim();
        out.options = [...new Set(out.options.map((s: string) => s.trim()).filter(Boolean))].slice(0, 4);
        if (!out.question) problems.push('ask 沒有問題');
        if (out.options.length < 2) problems.push('ask 的選項不到兩個');
        out.options.forEach((o: string) => o.length > 24 && problems.push(`選項太長：${o}`));
        if ((input as { questions_left?: number } | undefined)?.questions_left === 0) problems.push('題數用完了還在問');
        out.plans = [];
        out.difficulty = null;
        out.weeks_min = 0;
        out.weeks_max = 0;
        out.reason = '';
      } else {
        out.plans = out.plans
          .map((p: { trigger: string; floor: string }) => ({ trigger: p.trigger.trim().replace(/^如果/, '').replace(/[，,。]$/, ''), floor: p.floor.trim().replace(/^我就/, '').replace(/[。.]$/, '') }))
          .filter((p: { trigger: string; floor: string }) => p.trigger && p.floor)
          .slice(0, 3);
        if (out.plans.length === 0) problems.push('propose 沒有方案');
        for (const p of out.plans as { trigger: string; floor: string }[]) {
          if (negated(p.floor)) problems.push(`最小一步有否定詞：${p.floor}`);
          if (QUANTITY.test(p.floor)) problems.push(`最小一步帶了量：${p.floor}`);
          if (p.trigger.length > 30 || p.floor.length > 40) problems.push(`方案太長：${p.trigger}／${p.floor}`);
        }
        const level: 'easy' | 'medium' | 'hard' = out.difficulty ?? 'medium';
        out.difficulty = level;
        let lo = Math.round(out.weeks_min);
        let hi = Math.round(out.weeks_max);
        if (!(lo >= 3 && hi > lo && hi <= 30)) [lo, hi] = GUIDE_WEEKS[level];
        out.weeks_min = lo;
        out.weeks_max = hi;
        out.question = '';
        out.options = [];
      }
      break;
    }
    case 8: {
      const i = input as TaskInput<8> | undefined;
      out.category = null;
      out.message = null;
      if (out.type === 'off_topic') {
        // 模型的字整個丟掉，畫面上那句由 app 寫死
        out.lead = '';
        out.options = [];
        out.difficulty = null;
        break;
      }
      const wanted = i?.step === 'estimate' ? 'estimate' : 'options';
      if (i && out.type !== wanted) problems.push(`這一步要 ${wanted}，拿到 ${out.type}`);
      out.lead = out.lead.trim();
      if (!out.lead) problems.push('沒有 lead');
      if (len(out.lead) > 24) problems.push(`lead 太長：${out.lead}`);
      if (out.type === 'estimate') {
        out.options = [];
        if (!out.difficulty) problems.push('estimate 沒有 difficulty');
      } else {
        out.difficulty = null;
        const tidy = i?.step === 'trigger' ? tidyTrigger : tidyFloor;
        // 模型偶爾多給一個。第一個是最推薦的，留前三個
        out.options = out.options.map(tidy).filter(Boolean).slice(0, 3);
        const seen = new Set(out.options.map(same));
        if (out.options.length !== 3) problems.push(`選項要 3 個，拿到 ${out.options.length} 個`);
        else if (seen.size !== 3) problems.push('選項重複');
        for (const x of i?.exclude ?? []) if (x && seen.has(same(x))) problems.push(`選項是換掉的那個：${x}`);
        for (const o of out.options as string[]) {
          if (len(o) > 16) problems.push(`選項太長：${o}`);
          if (i?.step === 'trigger') {
            if (NOT_A_MOMENT.test(o)) problems.push(`時機不是一個瞬間：${o}`);
          } else {
            if (negated(o)) problems.push(`最小一步有否定詞：${o}`);
            if (QUANTITY.test(o) || TIME_SPAN.test(o)) problems.push(`最小一步帶了量：${o}`);
          }
        }
      }
      for (const s of [out.lead, ...out.options]) {
        if (DURATION.test(s)) problems.push(`講了天數：${s}`);
        problems.push(...unsafeHits(s));
      }
      break;
    }
    case 9: {
      const i = input as TaskInput<9> | undefined;
      out.category = null;
      out.message = null;
      out.finding = tidyLine(out.finding);
      if (!out.finding) problems.push('沒有 finding');
      if (len(out.finding) > 16) problems.push(`finding 太長：${out.finding}`);
      if (CAUSE.test(out.finding)) problems.push(`finding 講了原因：${out.finding}`);
      if (/[%％]|完成率|比上週|上週/.test(out.finding)) problems.push(`finding 有統計句：${out.finding}`);
      // 這週沒漏就沒有東西好改，不管模型給什麼
      if (i && i.week.missed.length === 0) out.change = null;
      const c = out.change as { field: string; label: string; text: string } | null;
      if (c) {
        c.label = tidyLine(c.label);
        c.text = c.field === 'floor' ? tidyFloor(tidyLine(c.text)) : tidyTrigger(tidyLine(c.text));
        if (!c.label || len(c.label) > 10) problems.push(`label 長度不對：${c.label}`);
        if (!c.text || len(c.text) > 16) problems.push(`text 長度不對：${c.text}`);
        if (negated(c.text)) problems.push(`改法有否定詞：${c.text}`);
        if (QUANTITY.test(c.text) || TIME_SPAN.test(c.text)) problems.push(`改法帶了量：${c.text}`);
        if (c.field !== 'floor' && NOT_A_MOMENT.test(c.text)) problems.push(`改的時機不是一個瞬間：${c.text}`);
        if (i && [i.floor, i.trigger].some((x) => same(x) === same(c.text))) problems.push('改法跟現在的一樣');
      }
      if (i) {
        problems.push(...wrongNumbers(out.finding, i));
        if (i.week.done < i.week.possible && /這週(每天|全|都)|七天都/.test(out.finding)) problems.push(`finding 說全做到：${out.finding}`);
        for (const s of [...i.reasons, ...i.week.skipped, ...(i.gap_reasons ?? [])].map((r) => r.reason)) {
          if (len(s) >= 2 && out.finding.includes(s)) problems.push('finding 講了跳過或漏掉的理由');
        }
        if (i.usual_time) {
          if (CLOCK.test(out.finding) || TIME_OF_DAY.test(out.finding)) problems.push(`finding 講了時間：${out.finding}`);
          for (const s of [c?.label ?? '', c?.text ?? '']) if (CLOCK.test(s)) problems.push(`改法寫了幾點：${s}`);
        }
        if (i.pattern === 'none') {
          for (const s of [out.finding, c?.label ?? '']) {
            const days = s.match(/(星期|週|周|禮拜)[一二三四五六日天]/g) ?? [];
            if (PATTERN_WORDS.test(s) || days.length > 1) problems.push(`沒有規律卻講規律：${s}`);
          }
        }
      }
      for (const s of [out.finding, c?.label ?? '', c?.text ?? '']) problems.push(...unsafeHits(s));
      break;
    }
  }

  for (const s of visibleStrings(out)) problems.push(...bannedHits(s));
  return { ok: problems.length === 0, problems, value: out };
}

/** unfit 時 app 要顯示的固定轉介文字（護欄包第六節，原文不改） */
export function referralFor(category: string | null | undefined): string {
  return category === 'eating' ? `${REFERRAL}\n\n${REFERRAL_EATING}` : REFERRAL;
}
