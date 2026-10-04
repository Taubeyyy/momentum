/* Erzeugt public/icons/icon-192.png + icon-512.png (Fokus-Ring auf dunklem Grund) — ohne Abhängigkeiten. */
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const OUT = path.join(__dirname, '..', 'public', 'icons');
fs.mkdirSync(OUT, { recursive: true });

function pixel(x, y, size) {
  const c = size / 2;
  const dx = x - c + 0.5, dy = y - c + 0.5;
  const d = Math.hypot(dx, dy) / c;               // 0 = Mitte, 1 = Rand
  const bg = [14, 16, 20];
  const accent = [124, 156, 255];
  const accent2 = [167, 139, 250];

  // Ring (offen oben rechts, wie ein laufender Timer)
  const ringR = 0.72, w = 0.085;
  const ang = Math.atan2(dy, dx);                  // -PI..PI
  const t = (ang + Math.PI) / (2 * Math.PI);       // 0..1
  const ringVis = t < 0.78;
  if (ringVis && Math.abs(d - ringR) < w) {
    const mix = t;
    return [
      Math.round(accent[0] * (1 - mix) + accent2[0] * mix),
      Math.round(accent[1] * (1 - mix) + accent2[1] * mix),
      Math.round(accent[2] * (1 - mix) + accent2[2] * mix)
    ];
  }
  // Punkt in der Mitte
  if (d < 0.2) return accent;
  // sanfter Glow
  const glow = Math.max(0, 1 - Math.abs(d - ringR) / 0.35) * 0.16;
  return [
    Math.round(bg[0] + accent[0] * glow),
    Math.round(bg[1] + accent[1] * glow),
    Math.round(bg[2] + accent[2] * glow)
  ];
}

function crc32(buf) {
  let c, crc = 0xffffffff;
  for (let n = 0; n < buf.length; n++) {
    c = (crc ^ buf[n]) & 0xff;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    crc = c ^ (crc >>> 8);
  }
  return (crc ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}
function png(size) {
  const raw = Buffer.alloc((size * 3 + 1) * size);
  let o = 0;
  for (let y = 0; y < size; y++) {
    raw[o++] = 0; // filter none
    for (let x = 0; x < size; x++) {
      const [r, g, b] = pixel(x, y, size);
      raw[o++] = r; raw[o++] = g; raw[o++] = b;
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0); ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8; ihdr[9] = 2; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0))
  ]);
}

for (const size of [192, 512]) {
  fs.writeFileSync(path.join(OUT, `icon-${size}.png`), png(size));
  console.log('icon-' + size + '.png geschrieben');
}

fs.writeFileSync(path.join(OUT, 'icon.svg'), `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <rect width="100" height="100" rx="22" fill="#0e1014"/>
  <circle cx="50" cy="50" r="34" fill="none" stroke="#7c9cff" stroke-width="8"
          stroke-linecap="round" stroke-dasharray="167 214" transform="rotate(-90 50 50)"/>
  <circle cx="50" cy="50" r="9" fill="#a78bfa"/>
</svg>`);
console.log('icon.svg geschrieben');
