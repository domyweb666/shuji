import { describe, expect, it } from 'vitest';
import { parseCliResult } from '../eval/cliCaller';

const t3 = { type: 'ok', rival_type: 'temptation', block: '手機放客廳', clear: '檔案留在桌面', note: '', category: null, message: null };
const usage = { input_tokens: 10, output_tokens: 20, cache_read_input_tokens: 3, cache_creation_input_tokens: 4 };

describe('parseCliResult', () => {
  it('讀 structured_output', () => {
    const r = parseCliResult(3, JSON.stringify({ is_error: false, structured_output: t3, stop_reason: 'end_turn', usage }));
    expect(r.parsed).toEqual(t3);
    expect(r.stopReason).toBe('end_turn');
    expect(r.usage).toEqual({ input: 10, output: 20, cacheRead: 3, cacheWrite: 4 });
  });

  it('沒有 structured_output 時從 result 字串解，包在程式碼區塊也行', () => {
    const r = parseCliResult(3, JSON.stringify({ result: '```json\n' + JSON.stringify(t3) + '\n```' }));
    expect(r.parsed).toEqual(t3);
  });

  it('可以是 null 的欄位被省略時補 null', () => {
    const { category, message, ...rest } = t3;
    const r = parseCliResult(3, JSON.stringify({ result: JSON.stringify(rest) }));
    expect(r.parsed).toEqual(t3);
  });

  it('不能是 null 的欄位被省略時不補', () => {
    const { block, ...rest } = t3;
    expect(parseCliResult(3, JSON.stringify({ result: JSON.stringify(rest) })).parsed).toBeNull();
  });

  it('欄位不合 schema 回 null，不丟例外', () => {
    const r = parseCliResult(3, JSON.stringify({ structured_output: { ...t3, rival_type: 'other' } }));
    expect(r.parsed).toBeNull();
    expect(r.stopReason).toBe('schema_mismatch');
  });

  it('result 不是 JSON 回 null', () => {
    expect(parseCliResult(3, JSON.stringify({ result: '好的，我來想想' })).parsed).toBeNull();
  });

  it('登入過期給看得懂的訊息', () => {
    const out = JSON.stringify({ is_error: true, result: 'Failed to authenticate. API Error: 401 OAuth access token has expired.' });
    expect(() => parseCliResult(3, out)).toThrow(/登入過期/);
  });

  it('其他錯誤照轉', () => {
    expect(() => parseCliResult(3, JSON.stringify({ is_error: true, result: 'rate limit' }))).toThrow(/rate limit/);
  });

  it('不是 JSON 的輸出', () => {
    expect(() => parseCliResult(3, 'Error: boom')).toThrow(/不是 JSON/);
  });
});
