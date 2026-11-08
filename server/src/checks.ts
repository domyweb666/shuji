import { BANNED_LINES, REFERRAL, REFERRAL_EATING } from './generated/packs';
import type { TaskId, TaskOutput } from './tasks';

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
  [/保證/, /一定會/, /科學證實/],
];

/** 搭建知識包第六節的否定句硬規則（不、別、戒、少、停止、避免、減少） */
export const NEGATION = /不|別|戒|停止|避免|減少|少(?:做|吃|喝|滑|看|用|玩|買|碰|抽)/;

/** 週回顧 summary 不准有數字（測試清單第 7 條）。
 *  診斷知識包第七節明文允許「週末那兩天開關好像沒出現」，所以中文數字不擋，只擋阿拉伯數字與百分比 */
const DIGITS = /[0-9０-９%％]/;
/** 三問診斷不准提停了幾天 */
const GAP_DAYS = /[0-9０-９一二三四五六七八九十兩]+\s*天/;

export const DIAGNOSE_CLOSING = '不是你的問題，是設計有洞，改好了就從這一節接上。';
export const DIAGNOSE_NOTHING = '設計看起來沒問題，可能只是那陣子生活變了。從這一節接上就好。';
export const AUDIT_WARNS = ['開關和環境留著，只拆記錄', '加量和加新習慣不要同一季', '有些結果要好幾季才看得到'];

export interface CheckResult<T> {
  ok: boolean;
  problems: string[];
  value: T;
}

/** 物件裡所有給人看的字串（type、category、field 這類代碼除外） */
function visibleStrings(v: unknown, key = ''): string[] {
  const codeKeys = new Set(['type', 'category', 'field', 'rival_type', 'verdict', 'path']);
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

const negated = (s: string) => NEGATION.test(s);

/**
 * 整理並檢查一份輸出。會改的東西：
 * - 任務 1 的 example 用 floors[0]、triggers[0] 重組（保證跟候選一致）
 * - 任務 4 的 closing 換成固定句；layer 0 時換成固定建議
 * - 任務 6 的 warn 不在三句之內就清空
 * - 非 ok 的時候把候選陣列清空
 */
export function review<T extends TaskId>(task: T, raw: TaskOutput<T>): CheckResult<TaskOutput<T>> {
  const problems: string[] = [];
  const out = structuredClone(raw) as any;

  if (out.type === 'unfit') {
    if (!out.category) problems.push('unfit 沒有 category');
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
  }

  for (const s of visibleStrings(out)) problems.push(...bannedHits(s));
  return { ok: problems.length === 0, problems, value: out };
}

/** unfit 時 app 要顯示的固定轉介文字（護欄包第六節，原文不改） */
export function referralFor(category: string | null | undefined): string {
  return category === 'eating' ? `${REFERRAL}\n\n${REFERRAL_EATING}` : REFERRAL;
}
