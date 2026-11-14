import { describe, expect, it } from 'vitest';
import { AttestError, verifyAssertion, verifyAttestation, APPLE_APP_ATTEST_ROOT } from '../src/attest/appattest';
import { parseCertificate, pemToDer } from '../src/attest/x509';
import { AAGUID_PROD, FakeApple, strangerIntermediate } from './fakeApple';

const APP = 'ABCDE12345.org.domyweb.shuji';
const apple = new FakeApple();
const opt = { appId: APP, allowEnvs: ['development', 'production'] as const, rootPem: apple.rootPem };

describe('Apple 根憑證', () => {
  it('釘住的根憑證讀得出來、P-384、還在有效期內', () => {
    const c = parseCertificate(pemToDer(APPLE_APP_ATTEST_ROOT));
    expect(c.curve).toBe('P-384');
    expect(c.notAfter.getUTCFullYear()).toBe(2045);
  });
});

describe('attestation（註冊）', () => {
  it('格式正確的註冊會過，記下 development 環境、計數器 0', async () => {
    const d = apple.device(APP);
    const key = await verifyAttestation(d.keyId, d.attest('chal-1'), 'chal-1', { ...opt, allowEnvs: [...opt.allowEnvs] });
    expect(key.keyId).toBe(d.keyId);
    expect(key.env).toBe('development');
    expect(key.counter).toBe(0);
  });

  it('production 的 aaguid 認得出來', async () => {
    const d = apple.device(APP, { aaguid: AAGUID_PROD });
    const key = await verifyAttestation(d.keyId, d.attest('c'), 'c', { ...opt, allowEnvs: ['production'] });
    expect(key.env).toBe('production');
  });

  it('只收 production 時擋下 development', async () => {
    const d = apple.device(APP);
    await expect(verifyAttestation(d.keyId, d.attest('c'), 'c', { ...opt, allowEnvs: ['production'] })).rejects.toThrow(AttestError);
  });

  it('挑戰字串不對 → nonce 對不上', async () => {
    const d = apple.device(APP);
    await expect(verifyAttestation(d.keyId, d.attest('real'), 'other', { ...opt, allowEnvs: [...opt.allowEnvs] })).rejects.toThrow(/nonce/);
  });

  it('別的 app（App ID 不同）擋下', async () => {
    const d = apple.device(APP);
    await expect(verifyAttestation(d.keyId, d.attest('c', { appId: 'X.other.app' }), 'c', { ...opt, allowEnvs: [...opt.allowEnvs] })).rejects.toThrow(/App ID/);
  });

  it('不是 Apple 根簽的中繼憑證擋下', async () => {
    const d = apple.device(APP, { interOverride: strangerIntermediate() });
    await expect(verifyAttestation(d.keyId, d.attest('c'), 'c', { ...opt, allowEnvs: [...opt.allowEnvs] })).rejects.toThrow(/根簽/);
  });

  it('keyId 跟公鑰對不上擋下', async () => {
    const d = apple.device(APP);
    const other = apple.device(APP);
    await expect(verifyAttestation(other.keyId, d.attest('c'), 'c', { ...opt, allowEnvs: [...opt.allowEnvs] })).rejects.toThrow(/keyId/);
  });

  it('註冊時計數器不是 0 擋下', async () => {
    const d = apple.device(APP, { counter: 3 });
    await expect(verifyAttestation(d.keyId, d.attest('c'), 'c', { ...opt, allowEnvs: [...opt.allowEnvs] })).rejects.toThrow(/計數器/);
  });

  it('真的 Apple 根憑證不會信任測試造的鏈', async () => {
    const d = apple.device(APP);
    await expect(verifyAttestation(d.keyId, d.attest('c'), 'c', { appId: APP, allowEnvs: ['development'] })).rejects.toThrow(AttestError);
  });

  it('亂碼的 attestation 擋下，不會丟出非 AttestError', async () => {
    await expect(verifyAttestation('AAAA', 'bm90IGNib3I=', 'c', { ...opt, allowEnvs: [...opt.allowEnvs] })).rejects.toThrow(AttestError);
  });
});

describe('assertion（每個請求）', () => {
  async function registered() {
    const d = apple.device(APP);
    const key = await verifyAttestation(d.keyId, d.attest('c'), 'c', { ...opt, allowEnvs: [...opt.allowEnvs] });
    return { d, key };
  }
  const body = new TextEncoder().encode('{"ts":1,"input":{"goal":"每天運動"}}');

  it('簽對的請求會過，計數器往上', async () => {
    const { d, key } = await registered();
    expect(await verifyAssertion(key, d.assert(body), body, APP)).toBe(1);
    key.counter = 1;
    expect(await verifyAssertion(key, d.assert(body), body, APP)).toBe(2);
  });

  it('同一個 assertion 再送一次（計數器沒往上）擋下', async () => {
    const { d, key } = await registered();
    const a = d.assert(body);
    key.counter = await verifyAssertion(key, a, body, APP);
    await expect(verifyAssertion(key, a, body, APP)).rejects.toThrow(/計數器/);
  });

  it('body 被改過擋下', async () => {
    const { d, key } = await registered();
    const a = d.assert(body);
    const tampered = new TextEncoder().encode('{"ts":1,"input":{"goal":"每天跑馬拉松"}}');
    await expect(verifyAssertion(key, a, tampered, APP)).rejects.toThrow(/簽章/);
  });

  it('別台裝置的簽章擋下', async () => {
    const { key } = await registered();
    const other = apple.device(APP);
    await expect(verifyAssertion(key, other.assert(body), body, APP)).rejects.toThrow(/簽章/);
  });
});
