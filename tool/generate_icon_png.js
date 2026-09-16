// Generuje pliki PNG ikony aplikacji z pikselowego „R” zaprojektowanego przez autora.
// Współrzędne prostokątów odczytane z projektu logo na płótnie 1932 × 1932 px.
// Uruchom: node tool/generate_icon_png.js, potem: dart run flutter_launcher_icons
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const OUT = path.join(__dirname, '..', 'assets', 'icon');
fs.mkdirSync(OUT, { recursive: true });

const SRC = 1932;
const CENTER = 965.5;
const MARK = [
  [497, 420, 1277, 576],   // górna belka
  [497, 576, 810, 1171],   // pień
  [1277, 576, 1434, 1043], // prawa ściana brzuszka
  [810, 1043, 1277, 1199], // dolna belka brzuszka
  [594, 1171, 810, 1277],  // schodek pnia
  [702, 1277, 810, 1371],  // dół pnia
  [1277, 1199, 1434, 1333], // noga
  [1277, 1333, 1355, 1418],
  [1355, 1418, 1420, 1511],
  [497, 1288, 577, 1365],  // odlatujące piksele
  [613, 1371, 702, 1460],
  [754, 1460, 809, 1511],
];
const TOP = [0x69, 0xba, 0x9f];
const BOTTOM = [0x55, 0x9c, 0x84];

function coverage(size, scale) {
  const cov = new Float32Array(size * size);
  const map = (v) => (v - CENTER) * scale + size / 2;
  for (const [x0s, y0s, x1s, y1s] of MARK) {
    const x0 = map(x0s), y0 = map(y0s), x1 = map(x1s), y1 = map(y1s);
    for (let y = Math.max(0, Math.floor(y0)); y < Math.min(size, Math.ceil(y1)); y++) {
      const oy = Math.min(y + 1, y1) - Math.max(y, y0);
      if (oy <= 0) continue;
      for (let x = Math.max(0, Math.floor(x0)); x < Math.min(size, Math.ceil(x1)); x++) {
        const ox = Math.min(x + 1, x1) - Math.max(x, x0);
        if (ox > 0) cov[y * size + x] = Math.min(1, cov[y * size + x] + ox * oy);
      }
    }
  }
  return cov;
}

const crcTable = new Int32Array(256).map((_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c;
});
function crc32(buf) {
  let c = -1;
  for (const b of buf) c = crcTable[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}
function writePng(file, size, channels, pixel) {
  const raw = Buffer.alloc((size * channels + 1) * size);
  for (let y = 0; y < size; y++) {
    const row = y * (size * channels + 1);
    raw[row] = 0;
    for (let x = 0; x < size; x++) pixel(x, y, raw, row + 1 + x * channels);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0); ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8; ihdr[9] = channels === 4 ? 6 : 2; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  const png = Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
  fs.writeFileSync(path.join(OUT, file), png);
  console.log(`${file}: ${size}×${size}, ${Math.round(png.length / 1024)} KB`);
}
const bg = (y, size, c) => Math.round(TOP[c] + (BOTTOM[c] - TOP[c]) * (y / (size - 1)));

const SIZE = 1024;

// Pełna ikona dla iOS i sklepu: proporcje z projektu, bez przezroczystości i bez zaokrągleń.
const full = coverage(SIZE, SIZE / SRC);
writePng('icon.png', SIZE, 3, (x, y, buf, i) => {
  const a = full[y * SIZE + x];
  for (let c = 0; c < 3; c++) buf[i + c] = Math.round(bg(y, SIZE, c) * (1 - a) + 255 * a);
});

// Tło ikony adaptacyjnej Androida.
writePng('background.png', SIZE, 3, (x, y, buf, i) => {
  for (let c = 0; c < 3; c++) buf[i + c] = bg(y, SIZE, c);
});

// Pierwszy plan i wersja jednokolorowa: znak w strefie bezpiecznej 66 z 108 dp.
const safeRadius = (66 / 108 / 2) * SIZE;
const halfDiagonal = Math.hypot(1434 - CENTER, 1511 - CENTER);
const adaptive = coverage(SIZE, (safeRadius * 0.94) / halfDiagonal);
for (const file of ['foreground.png', 'monochrome.png']) {
  writePng(file, SIZE, 4, (x, y, buf, i) => {
    buf[i] = 255; buf[i + 1] = 255; buf[i + 2] = 255;
    buf[i + 3] = Math.round(adaptive[y * SIZE + x] * 255);
  });
}
