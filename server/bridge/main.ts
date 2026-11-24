// npm run bridge：開起來，印 QR code。用法見 README.md
import os from 'node:os';
import qrcode from 'qrcode-terminal';
import { cliVersion, createBridge } from './bridge';

const PORT = Number(process.env.PORT) || 8791;

const VIRTUAL =
  /vethernet|virtualbox|vmware|vbox|hyper-v|wsl|docker|loopback|tailscale|zerotier|hamachi|vpn|tap|tun|utun|veth|br-|bridge|npcap/i;

function privateRank(ip: string) {
  if (ip.startsWith('192.168.')) return 0;
  if (ip.startsWith('10.')) return 1;
  const m = ip.match(/^172\.(\d+)\./);
  return m && Number(m[1]) >= 16 && Number(m[1]) <= 31 ? 2 : 9;
}

function lanIps() {
  const all: { name: string; ip: string; rank: number; virtual: boolean }[] = [];
  for (const [name, list] of Object.entries(os.networkInterfaces())) {
    for (const a of list ?? []) {
      if (a.family !== 'IPv4' || a.internal || a.address.startsWith('169.254.')) continue;
      all.push({ name, ip: a.address, rank: privateRank(a.address), virtual: VIRTUAL.test(name) });
    }
  }
  let pick = all.filter((x) => !x.virtual && x.rank < 9);
  if (!pick.length) pick = all.filter((x) => x.rank < 9);
  return pick.sort((a, b) => a.rank - b.rank);
}

async function main() {
  const cli = await cliVersion();
  const { server, token, dispose } = createBridge({ cli });

  let closing = false;
  function shutdown() {
    if (closing) return;
    closing = true;
    console.log('\n關掉中…');
    dispose();
    server.close(() => process.exit(0));
    server.closeAllConnections();
    setTimeout(() => process.exit(0), 3000).unref();
  }
  process.on('exit', dispose);
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
  process.on('SIGHUP', shutdown);

  server.on('error', (e: NodeJS.ErrnoException) => {
    if (e.code === 'EADDRINUSE') console.error(`埠號 ${PORT} 已經有人在用。關掉另一個，或換一個埠號（看 README）`);
    else console.error(`開不起來：${e.message}`);
    process.exit(1);
  });

  server.listen(PORT, '0.0.0.0', () => {
    const urls = lanIps().map((x) => ({ url: `http://${x.ip}:${PORT}/shuji?t=${token}`, name: x.name }));
    console.log('\n薯記 × 電腦的 Claude');
    console.log(`Claude CLI：${cli || '取不到版本，確認 claude 有裝好、有登入'}\n`);
    if (!urls.length) {
      console.log(`找不到區網 IP，這台電腦有連上 Wi-Fi 嗎？埠號 ${PORT}，密碼 ${token}`);
      return;
    }
    console.log('在薯記的「設定 → AI → 連電腦的 Claude」掃這個：');
    qrcode.generate(urls[0].url, { small: true }, (q) => console.log(q));
    for (const u of urls) console.log(`${u.url}   （${u.name}）`);
    console.log('\n手機跟電腦要連同一個 Wi-Fi。按 Ctrl+C 結束。\n');
  });
}

void main();
