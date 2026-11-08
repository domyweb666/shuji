// 把 repo 根目錄 ai/ 底下的知識包與提示詞，原封不動打包成 src/generated/packs.ts。
// ai/ 是唯一的來源：改書的內容就改 ai/，重新部署，伺服器跟著換。這個產物不進 git。
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const AI = join(HERE, '..', '..', 'ai');
const OUT = join(HERE, '..', 'src', 'generated');

const read = (name) => readFileSync(join(AI, name), 'utf8').replace(/\r\n/g, '\n');

const packs = {
  guard: read('知識包-護欄.md'),
  build: read('知識包-搭建.md'),
  obstacle: read('知識包-障礙.md'),
  diagnose: read('知識包-診斷.md'),
  audit: read('知識包-稽核.md'),
};

// 每個任務的「任務指令」：## 任務 N 底下，**任務指令** 後面的第一個 ``` 區塊
const prompts = read('提示詞與輸出格式.md');
const instructions = {};
for (let n = 1; n <= 6; n++) {
  const start = prompts.indexOf(`## 任務 ${n}｜`);
  if (start < 0) throw new Error(`提示詞檔裡找不到「## 任務 ${n}｜」`);
  const end = n < 6 ? prompts.indexOf(`## 任務 ${n + 1}｜`) : prompts.indexOf('## 測試清單');
  const section = prompts.slice(start, end < 0 ? undefined : end);
  const m = section.match(/\*\*任務指令\*\*\s*```[a-z]*\n([\s\S]*?)\n```/);
  if (!m) throw new Error(`任務 ${n} 找不到任務指令區塊`);
  instructions[n] = m[1].trim();
}

// 護欄包第六節的固定轉介文字（> 開頭那段）與 eating 加的那句
const sec6 = packs.guard.slice(packs.guard.indexOf('## 六、'), packs.guard.indexOf('## 七、'));
const quote = sec6.match(/^> (.+)$/m);
const eating = sec6.match(/eating 類型另加一句：「(.+?)」/);
if (!quote || !eating) throw new Error('護欄包第六節的轉介文字格式變了');

// 第四節禁用清單，原樣保留給輸出檢查用
const sec4 = packs.guard.slice(packs.guard.indexOf('## 四、'), packs.guard.indexOf('## 五、'));
const banned = sec4.split('\n').filter((l) => l.startsWith('- ')).map((l) => l.slice(2).trim());
if (banned.length < 8) throw new Error('護欄包第四節禁用清單讀不出來');

mkdirSync(OUT, { recursive: true });
const body = `// 由 scripts/gen-packs.mjs 從 ai/ 產生，不要手改。
export const PACKS = ${JSON.stringify(packs, null, 2)} as const;
export const INSTRUCTIONS: Record<1 | 2 | 3 | 4 | 5 | 6, string> = ${JSON.stringify(instructions, null, 2)};
export const REFERRAL = ${JSON.stringify(quote[1].trim())};
export const REFERRAL_EATING = ${JSON.stringify(eating[1].trim())};
export const BANNED_LINES: string[] = ${JSON.stringify(banned, null, 2)};
`;
writeFileSync(join(OUT, 'packs.ts'), body);
console.log('packs ok', Object.fromEntries(Object.entries(packs).map(([k, v]) => [k, v.length])), 'instructions', Object.keys(instructions).length, 'banned', banned.length);
