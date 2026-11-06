// Every sound in the game, made from nothing but maths, so there is nothing to license. Mono 22 kHz WAV, written to
// game/assets/audio. Seeded: the same run makes the same files.  node tools/make_audio.js
const fs = require("fs");
const path = require("path");
const OUT = path.join(__dirname, "..", "game", "assets", "audio");
const RATE = 22050;
fs.mkdirSync(OUT, { recursive: true });

let seed = 20261105;
const rnd = () => { seed = (seed * 1664525 + 1013904223) >>> 0; return seed / 4294967296; };
const buf = (s) => new Float32Array(Math.ceil(s * RATE));
const TAU = Math.PI * 2;

function save(name, x, peak = 0.9) {
  let m = 0;
  for (const v of x) m = Math.max(m, Math.abs(v));
  const k = m > 0 ? peak / m : 1;
  const b = Buffer.alloc(44 + x.length * 2);
  b.write("RIFF", 0); b.writeUInt32LE(36 + x.length * 2, 4); b.write("WAVEfmt ", 8); b.writeUInt32LE(16, 16);
  b.writeUInt16LE(1, 20); b.writeUInt16LE(1, 22); b.writeUInt32LE(RATE, 24); b.writeUInt32LE(RATE * 2, 28); b.writeUInt16LE(2, 32); b.writeUInt16LE(16, 34);
  b.write("data", 36); b.writeUInt32LE(x.length * 2, 40);
  x.forEach((v, i) => b.writeInt16LE(Math.round(Math.max(-1, Math.min(1, v * k)) * 32767), 44 + i * 2));
  fs.writeFileSync(path.join(OUT, name + ".wav"), b);
  console.log(name, (x.length / RATE).toFixed(1) + " s");
}

// a struck thing: partials [Hz, loudness, seconds to fade]
function tones(x, at, parts, gain = 1) {
  const i0 = Math.floor(at * RATE);
  for (const [hz, amp, fade] of parts) {
    for (let i = i0; i < x.length; i++) {
      const t = (i - i0) / RATE;
      const e = Math.exp(-t * 5 / fade);
      if (e < 0.0005) break;
      x[i] += Math.sin(TAU * hz * t) * amp * e * gain * Math.min(1, t * 2000);
    }
  }
}

// one-pole filters over noise
function noise(n, lowHz, highHz) {
  const x = new Float32Array(n);
  const lo = 1 - Math.exp(-TAU * lowHz / RATE), hi = 1 - Math.exp(-TAU * highHz / RATE);
  let a = 0, b = 0;
  for (let i = 0; i < n; i++) {
    const w = rnd() * 2 - 1;
    a += hi * (w - a);   // keep below highHz
    b += lo * (a - b);   // take away below lowHz
    x[i] = a - b;
  }
  return x;
}

// an end that runs into its own start, for a loop
function loopable(x, overlap) {
  const n = Math.floor(overlap * RATE);
  const out = x.slice(0, x.length - n);
  for (let i = 0; i < n; i++) {
    const k = i / n;
    out[i] = out[i] * Math.sqrt(k) + x[x.length - n + i] * Math.sqrt(1 - k);
  }
  return out;
}

// a plucked string (Karplus-Strong), added into x at a time
function pluck(x, at, hz, seconds, gain, bright = 0.5) {
  const n = Math.round(RATE / hz);
  const line = new Float32Array(n);
  for (let i = 0; i < n; i++) line[i] = rnd() * 2 - 1;
  const i0 = Math.floor(at * RATE), len = Math.floor(seconds * RATE);
  let p = 0, last = 0;
  const damp = 0.996;
  for (let i = 0; i < len && i0 + i < x.length; i++) {
    const v = line[p];
    const f = (bright * v + (1 - bright) * last) * damp;
    last = v;
    line[p] = f;
    p = (p + 1) % n;
    x[i0 + i] += v * gain * Math.min(1, i / 40);
  }
}

// --- things that happen ------------------------------------------------------------------------------------------------
{ const x = buf(0.7); tones(x, 0, [[3520, 0.6, 0.35], [5280, 0.35, 0.22], [7100, 0.2, 0.14], [2640, 0.2, 0.5]]); tones(x, 0.06, [[4100, 0.25, 0.25], [6150, 0.14, 0.14]]); save("coin", x, 0.6); }

{ const x = buf(4.2); tones(x, 0, [[523.25, 1, 2.6], [1046.5, 0.55, 1.7], [1244.5, 0.3, 1.2], [1568, 0.2, 0.8], [261.6, 0.35, 3.4]]); save("bell", x, 0.8); }

{ // paper: a soft rustle in a few quick gestures
  const x = buf(0.55), n = noise(x.length, 900, 6000);
  for (let i = 0; i < x.length; i++) {
    const t = i / RATE;
    const env = Math.exp(-Math.pow((t - 0.08) / 0.05, 2)) + 0.7 * Math.exp(-Math.pow((t - 0.22) / 0.07, 2)) + 0.35 * Math.exp(-Math.pow((t - 0.38) / 0.06, 2));
    x[i] = n[i] * env;
  }
  save("paper", x, 0.5);
}

{ // door: a low thud with a little latch on top
  const x = buf(0.6), n = noise(x.length, 60, 500);
  for (let i = 0; i < x.length; i++) x[i] = n[i] * Math.exp(-i / RATE * 16) * 1.4;
  tones(x, 0, [[92, 1.0, 0.3], [140, 0.5, 0.2]]);
  tones(x, 0.05, [[1900, 0.1, 0.05], [2700, 0.06, 0.04]]);
  save("door", x, 0.6);
}

{ // the ferry's horn: two reedy notes a third apart
  const x = buf(3.0);
  for (let i = 0; i < x.length; i++) {
    const t = i / RATE, e = Math.min(1, t * 6) * Math.min(1, (3.0 - t) * 2.5);
    let v = 0;
    for (const f of [147, 185]) for (let h = 1; h <= 6; h++) v += Math.sin(TAU * f * h * t + h) / h;
    x[i] = v * e;
  }
  save("ferry_horn", x, 0.45);
}

{ // a stamp coming down on paper
  const x = buf(0.35), n = noise(x.length, 120, 1800);
  for (let i = 0; i < x.length; i++) x[i] = n[i] * Math.exp(-i / RATE * 40) * 1.1;
  tones(x, 0, [[110, 1.2, 0.12], [240, 0.5, 0.06]]);
  save("stamp", x, 0.8);
}

// footsteps: a soft thud and a surface. Three of each, so no two are the same
for (const [name, lo, hi, thud, length] of [["stone", 600, 5000, 0.5, 0.12], ["grass", 1500, 7000, 0.15, 0.17], ["wood", 200, 2200, 1.0, 0.13]]) {
  for (let v = 1; v <= 3; v++) {
    const x = buf(length + 0.08), n = noise(x.length, lo * (0.85 + rnd() * 0.3), hi);
    for (let i = 0; i < x.length; i++) {
      const t = i / RATE;
      x[i] = n[i] * Math.exp(-t * 34 / (length / 0.1)) * Math.min(1, t * 900);
      x[i] += Math.sin(TAU * (name === "wood" ? 150 + rnd() * 3 : 92) * t) * Math.exp(-t * 55) * thud;
    }
    save(`step_${name}_${v}`, x, 0.7);
  }
}

// --- places, as loops ------------------------------------------------------------------------------------------------------
{ // water against a bank: slow swells of soft noise
  const s = 13, n = noise(Math.ceil(s * RATE), 90, 1400), m = noise(Math.ceil(s * RATE), 900, 4200), x = buf(s);
  for (let i = 0; i < x.length; i++) {
    const t = i / RATE;
    const swell = 0.6 + 0.25 * Math.sin(t * 1.1) + 0.2 * Math.sin(t * 2.7 + 1) + 0.12 * Math.sin(t * 5.3);
    x[i] = n[i] * swell + m[i] * 0.25 * Math.max(0, swell - 0.6);
  }
  save("amb_water", loopable(x, 1.0), 0.5);
}

// people talking far off: speech-shaped noise, many voices
function murmur(s, voices, lo, hi) {
  const x = buf(s);
  for (let v = 0; v < voices; v++) {
    const n = noise(x.length, lo + rnd() * 200, hi);
    let t = rnd() * 1.5;
    while (t < s - 0.3) {
      const syll = 0.09 + rnd() * 0.16, amp = 0.5 + rnd() * 0.6;
      const i0 = Math.floor(t * RATE), len = Math.floor(syll * RATE);
      for (let i = 0; i < len && i0 + i < x.length; i++) x[i0 + i] += n[i0 + i] * amp * Math.sin(Math.PI * i / len);
      t += syll * (1 + rnd() * 0.5);
      if (rnd() < 0.14) t += 0.4 + rnd() * 1.2;   // a breath
    }
  }
  return x;
}

{ // birds over the town
  const s = 17, x = murmur(s, 3, 300, 1500);
  for (let i = 0; i < x.length; i++) x[i] *= 0.1;
  for (let k = 0; k < 22; k++) {
    const at = rnd() * (s - 2), base = 2200 + rnd() * 2200, notes = 1 + Math.floor(rnd() * 5);
    for (let c = 0; c < notes; c++) {
      const t0 = at + c * (0.09 + rnd() * 0.06), dur = 0.05 + rnd() * 0.07, sweep = (rnd() - 0.4) * 900;
      const i0 = Math.floor(t0 * RATE), len = Math.floor(dur * RATE);
      let ph = 0;
      for (let i = 0; i < len && i0 + i < x.length; i++) {
        const u = i / len;
        ph += TAU * (base + sweep * u) / RATE;
        x[i0 + i] += Math.sin(ph) * Math.sin(Math.PI * u) * 0.09;
      }
    }
  }
  save("amb_town", loopable(x, 1.0), 0.32);
}

{ // the market: a crowd under a roof, a crate, a coin now and then
  const s = 16, x = murmur(s, 14, 260, 1900);
  for (let k = 0; k < 7; k++) tones(x, rnd() * (s - 1), [[3000 + rnd() * 1800, 0.7, 0.2], [5200, 0.3, 0.12]], 0.5);
  for (let k = 0; k < 5; k++) tones(x, rnd() * (s - 1), [[120 + rnd() * 70, 1.3, 0.18]], 0.8);
  save("amb_market", loopable(x, 1.0), 0.42);
}

{ // the Common Table: fewer voices, closer, cups and plates
  const s = 15, x = murmur(s, 7, 300, 2300);
  for (let k = 0; k < 16; k++) tones(x, rnd() * (s - 1), [[1700 + rnd() * 2600, 0.5, 0.12], [3500 + rnd() * 2000, 0.25, 0.07]], 0.8);
  save("amb_table", loopable(x, 1.0), 0.38);
}

{ // the bank: a hushed room, a clock, a far-off stamp
  const s = 16, x = noise(Math.ceil(s * RATE), 50, 420);
  for (let i = 0; i < x.length; i++) x[i] *= 0.1;
  for (let k = 0; k < s; k++) tones(x, k + 0.25, [[1900, 0.1, 0.03], [3100, 0.05, 0.02]]);
  for (let k = 0; k < 3; k++) tones(x, rnd() * (s - 1), [[150, 0.5, 0.12], [420, 0.15, 0.07]]);
  save("amb_bank", loopable(x, 0.5), 0.26);
}

// --- music: a drone and a plucked line in a major pentatonic (Bhupali), unhurried. Quiet under everything ----------------------------
function music(name, seconds, rootHz, beat, restChance, bright, gain) {
  const scale = [1, 9 / 8, 5 / 4, 3 / 2, 5 / 3, 2, 9 / 4, 5 / 2, 3, 10 / 3];
  const x = buf(seconds + 6);
  // the drone: root and fifth, plucked again and again like a tanpura
  for (let t = 0; t < seconds + 2; t += beat * 4) {
    pluck(x, t, rootHz, beat * 7, 0.26, 0.42);
    pluck(x, t + beat, rootHz * 1.5, beat * 6, 0.18, 0.42);
    pluck(x, t + beat * 2, rootHz * 2, beat * 6, 0.18, 0.42);
    pluck(x, t + beat * 3, rootHz * 2, beat * 6, 0.14, 0.42);
  }
  // the line walks up and down the scale, resting often, always coming home
  let at = 4, step = 3, phrase = 0;
  while (at < seconds - 3) {
    if (rnd() < restChance) { at += beat * (2 + Math.floor(rnd() * 3)); continue; }
    pluck(x, at, rootHz * 2 * scale[step], beat * 5, gain * (0.8 + rnd() * 0.3), bright);
    if (rnd() < 0.18) pluck(x, at + beat * 0.25, rootHz * 2 * scale[Math.min(step + 1, scale.length - 1)], beat * 3, gain * 0.55, bright);
    step = Math.max(0, Math.min(scale.length - 1, step + [-2, -1, -1, 1, 1, 2][Math.floor(rnd() * 6)]));
    if (++phrase % 8 === 0) { step = [0, 3, 5][Math.floor(rnd() * 3)]; at += beat * 2; }
    at += beat * (rnd() < 0.3 ? 2 : 1);
  }
  save(name, loopable(x, 6), 0.5);
}
music("music_dawn", 54, 110, 0.82, 0.3, 0.55, 0.8);
music("music_day", 72, 98, 0.62, 0.42, 0.5, 0.62);
music("music_night", 60, 82.4, 0.95, 0.5, 0.42, 0.6);
