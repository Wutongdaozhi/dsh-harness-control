// 生成 DeepSeek 鲸鱼托盘图标（多尺寸 .ico）
// 用法: node make-tray-icon.cjs [输出路径] [颜色]
// 默认: dsh-tray.ico, 品牌蓝 #4D6BFE
// 素材来源: 已安装的 @deepseek-ai/dsh-web-frontend 包内 favicon.svg（MIT 许可）
const fs = require('fs');
const path = require('path');

const OUT = path.resolve(process.argv[2] || path.join(__dirname, 'dsh-tray.ico'));
const COLOR = process.argv[3] || '#4D6BFE';
const SIZES = [16, 24, 32, 48, 64, 128, 256];

// --- 定位 sharp -------------------------------------------------------------
function findSharp() {
  const candidates = [
    () => require('sharp'),                       // 当前目录可解析（已 npm install）
    () => require(path.join(__dirname, 'node_modules', 'sharp')),
    () => require(path.join(process.env.DSH_HOME || '', 'profiles', 'node_modules', 'sharp')),
    () => require(require('child_process').execSync('npm root -g').toString().trim() + '/sharp'),
  ];
  for (const c of candidates) {
    try { return c(); } catch (e) { /* try next */ }
  }
  throw new Error('sharp not found; install it (npm i sharp) or place this script inside a dsh profile/deployment');
}

// --- 定位 favicon.svg ---------------------------------------------------------
function findSvg() {
  const candidates = [
    () => require.resolve('@deepseek-ai/dsh-web-frontend/dist/favicon.svg'),
    () => path.join(__dirname, 'node_modules', '@deepseek-ai', 'dsh-web-frontend', 'dist', 'favicon.svg'),
    () => path.join(process.env.DSH_HOME || '', 'profiles', 'node_modules', '@deepseek-ai', 'dsh-web-frontend', 'dist', 'favicon.svg'),
  ];
  for (const c of candidates) {
    try { const p = c(); if (fs.existsSync(p)) return p; } catch (e) { /* try next */ }
  }
  throw new Error('DeepSeek favicon.svg not found; install @deepseek-ai/dsh-web-frontend or point DSH_HOME at a dsh profile');
}

(async () => {
  const sharp = findSharp();
  let svg = fs.readFileSync(findSvg(), 'utf8');
  // 统一染色：去掉自适应深色的白色覆盖
  svg = svg.replace('fill="#000"', `fill="${COLOR}"`);
  svg = svg.replace(/<style>[\s\S]*?<\/style>/, '');

  const pngs = [];
  for (const s of SIZES) {
    pngs.push({ size: s, data: await sharp(Buffer.from(svg)).resize(s, s).png().toBuffer() });
  }

  const header = Buffer.alloc(6);
  header.writeUInt16LE(0, 0);
  header.writeUInt16LE(1, 2);
  header.writeUInt16LE(pngs.length, 4);
  const entries = [];
  let offset = 6 + pngs.length * 16;
  for (const { size, data } of pngs) {
    const e = Buffer.alloc(16);
    e.writeUInt8(size >= 256 ? 0 : size, 0);
    e.writeUInt8(size >= 256 ? 0 : size, 1);
    e.writeUInt8(0, 2);
    e.writeUInt8(0, 3);
    e.writeUInt16LE(1, 4);
    e.writeUInt16LE(32, 6);
    e.writeUInt32LE(data.length, 8);
    e.writeUInt32LE(offset, 12);
    offset += data.length;
    entries.push(e);
  }
  fs.writeFileSync(OUT, Buffer.concat([header, ...entries, ...pngs.map(p => p.data)]));
  console.log('written', OUT, fs.statSync(OUT).size, 'bytes');
})().catch((err) => { console.error(err.message); process.exit(1); });
