import { describe, expect, it } from 'vitest';
import { BANNED_PATTERNS, DIAGNOSE_CLOSING, DIAGNOSE_NOTHING, bannedHits, referralFor, review } from '../src/checks';
import { BANNED_LINES, INSTRUCTIONS, PACKS } from '../src/generated/packs';
import { systemBlocks } from '../src/model';
import { OUTPUTS } from '../src/tasks';

describe('從 ai/ 打包進來的內容', () => {
  it('五份知識包、六段任務指令都在', () => {
    for (const k of ['guard', 'build', 'obstacle', 'diagnose', 'audit'] as const) expect(PACKS[k].length).toBeGreaterThan(1000);
    for (const n of [1, 2, 3, 4, 5, 6] as const) expect(INSTRUCTIONS[n]).toMatch(/JSON/);
  });

  it('禁用清單每一行都有對應的 pattern（書加了一行，這裡會失敗）', () => {
    expect(BANNED_PATTERNS.length).toBe(BANNED_LINES.length);
  });

  it('系統提示順序：護欄 → 知識包（快取點）→ 任務指令', () => {
    const b = systemBlocks(1);
    expect(b[0].text).toBe(PACKS.guard);
    expect(b[1].text).toBe(PACKS.build);
    expect(b[1].cache_control).toEqual({ type: 'ephemeral' });
    expect(b[2].text).toContain(INSTRUCTIONS[1]);
    expect(systemBlocks(6)[1].text).toBe(PACKS.audit);
    expect(systemBlocks(3)[1].text).toBe(PACKS.obstacle);
  });

  it('轉介文字原文；飲食類多一句', () => {
    expect(referralFor('addiction')).toContain('安心專線 1925');
    expect(referralFor('addiction')).not.toContain('飲食');
    expect(referralFor('eating')).toContain('跟飲食、體重有關的目標');
  });
});

describe('禁用詞', () => {
  const samples = ['21 天就會養成', '不要斷掉紀錄', '前功盡棄', '靠意志力撐', '我是早起的人', '每天進步 1%', '戒掉手機', '多巴胺分泌', '從今天開始改變', '保證有效'];
  it('清單每一行的典型句都抓得到', () => {
    samples.forEach((s, i) => {
      expect(bannedHits(s).length, s).toBeGreaterThan(0);
      expect(BANNED_PATTERNS[i].some((re) => re.test(s)), `第 ${i} 行：${s}`).toBe(true);
    });
  });
  it('正常的句子不誤殺', () => {
    for (const s of ['換上球鞋出門', '如果起床喝完第一杯水，我就打開檔案寫一句。', '先坐三個呼吸再去躺', '開關和環境留著，只拆記錄', '一次只裝一個']) {
      expect(bannedHits(s), s).toEqual([]);
    }
  });
});

const ok1 = {
  type: 'ok' as const,
  floors: ['換上球鞋出門', '走到巷口', '慢跑一圈'],
  triggers: ['起床喝完水', '刷完牙', '闔上筆電', '進家門', '洗完澡', '上床前'],
  example: '隨便寫的',
  note: '',
  category: null,
  message: null,
};

describe('任務 1 種下去助手', () => {
  it('正常輸出通過，example 用第一個開關與最小一步重組', () => {
    const r = review(1, ok1);
    expect(r.ok).toBe(true);
    expect(r.value.example).toBe('如果起床喝完水，我就換上球鞋出門。');
  });
  it('最小一步有否定詞 → 不過', () => {
    const r = review(1, { ...ok1, floors: ['不滑手機', '走到巷口', '慢跑'] });
    expect(r.ok).toBe(false);
  });
  it('最小一步帶了量 → 不過', () => {
    expect(review(1, { ...ok1, floors: ['跑 30 分鐘', 'b', 'c'] }).ok).toBe(false);
  });
  it('needs_rewrite 清空候選、要有 message', () => {
    const r = review(1, { ...ok1, type: 'needs_rewrite', message: '那個時刻你想改做什麼？' });
    expect(r.ok).toBe(true);
    expect(r.value.floors).toEqual([]);
    expect(review(1, { ...ok1, type: 'too_rare', message: null }).ok).toBe(false);
  });
  it('unfit 要有 category', () => {
    expect(review(1, { ...ok1, type: 'unfit', category: 'eating', message: 'x' }).ok).toBe(true);
    expect(review(1, { ...ok1, type: 'unfit', category: null, message: 'x' }).ok).toBe(false);
  });
  it('note 有禁用詞 → 不過', () => {
    expect(review(1, { ...ok1, note: '靠意志力就好' }).ok).toBe(false);
  });
});

describe('任務 2 障礙版', () => {
  const base = { type: 'ok' as const, obstacles: [{ if: '早上要趕出門', then: '在捷運上用手機寫三行' }], backup: null, travel: null, note: '', category: null, message: null };
  it('正常通過；超過兩條砍到兩條', () => {
    const r = review(2, { ...base, obstacles: [...base.obstacles, ...base.obstacles, ...base.obstacles] });
    expect(r.ok).toBe(true);
    expect(r.value.obstacles.length).toBe(2);
  });
  it('替代動作有否定詞 → 不過', () => {
    expect(review(2, { ...base, obstacles: [{ if: '想滑手機', then: '就不滑' }] }).ok).toBe(false);
  });
});

describe('任務 4 三問診斷', () => {
  const base = { type: 'ok' as const, layer: 4 as const, field: 'floor' as const, suggestion: '先坐三個呼吸', why: '最小一步要小到累的日子也做得到。', closing: '隨便', category: null, message: null };
  it('closing 一律換成固定句', () => {
    expect(review(4, base).value.closing).toBe(DIAGNOSE_CLOSING);
  });
  it('layer 0 → field null、固定建議', () => {
    const r = review(4, { ...base, layer: 0, field: 'trigger' });
    expect(r.value.field).toBeNull();
    expect(r.value.suggestion).toBe(DIAGNOSE_NOTHING);
    expect(r.ok).toBe(true);
  });
  it('提到停了幾天 → 不過', () => {
    expect(review(4, { ...base, why: '你停了 18 天' }).ok).toBe(false);
  });
});

describe('任務 5 週回顧', () => {
  const base = { type: 'ok' as const, verdict: 'fine' as const, summary: '這週不用改什麼，開關每天都有出現。', fix: { field: 'floor' as const, suggestion: 'x' }, note: '', category: null, message: null };
  it('fine 時 fix 清成 null', () => {
    const r = review(5, base);
    expect(r.ok).toBe(true);
    expect(r.value.fix).toBeNull();
  });
  it('summary 有數字 → 不過', () => {
    expect(review(5, { ...base, summary: '這週漏了 3 天' }).ok).toBe(false);
    expect(review(5, { ...base, summary: '完成率很高' }).ok).toBe(false);
  });
  it('書裡的原句「週末那兩天開關好像沒出現」要能過', () => {
    expect(review(5, { ...base, verdict: 'fix', summary: '週末那兩天開關好像沒出現。', fix: { field: 'backup', suggestion: '如果中午前還沒打開檔案，就在第一餐吃完時做。' } }).ok).toBe(true);
  });
});

describe('任務 6 季稽核', () => {
  const base = { type: 'ok' as const, path: 'keep' as const, change: '把每天寫的那一句，改成寫給一個讀者看的開頭。', why: '有在做但沒用，是目標層的問題。', warn: '有些結果要好幾季才看得到。', category: null, message: null };
  it('warn 在三句之內保留，不在就清空', () => {
    expect(review(6, base).value.warn).toBe('有些結果要好幾季才看得到。');
    expect(review(6, { ...base, warn: '加油' }).value.warn).toBe('');
  });
  it('建議加習慣 → 不過', () => {
    expect(review(6, { ...base, change: '再加一個習慣' }).ok).toBe(false);
  });
});

describe('輸出 schema', () => {
  it('六個 schema 都收得下合法範例', () => {
    expect(OUTPUTS[1].safeParse(ok1).success).toBe(true);
    expect(OUTPUTS[4].safeParse({ type: 'ok', layer: 1, field: 'backup', suggestion: 's', why: 'w', closing: 'c', category: null, message: null }).success).toBe(true);
    expect(OUTPUTS[4].safeParse({ type: 'ok', layer: 2, field: 'backup', suggestion: 's', why: 'w', closing: 'c', category: null, message: null }).success).toBe(false);
  });
});
