// Top-lit layered smoke volumes use the technique in PixelFX spawn/poof,
// adapted from Sprite Fusion explosion (https://www.spritefusion.com/pixel-art-vfx/explosion), MIT, Copyright (c) 2026 Hugo Duprez.
import { Rng, fit, clamp, TAU } from '../../pixelfx/src/core/index.js';
export const meta = {
  name: 'Player death smoke',
  desc: 'A body-sized white smoke cloud blooms, curls upward and separates into thinning lavender-gray wisps.',
  tags: ['death', 'smoke', 'despawn', 'one-shot'],
  size: [96, 96], origin: [48, 48], duration: 0.6, fps: 30, loop: false, bg: 'ground',
  options: { seed: 47, palette: ['#8b839d', '#b8afc8', '#e4deec', '#fff9f4'] },
};
export function draw(p, t, o) {
  if (t < 0 || t >= meta.duration) return;
  const C = fit(o.palette, 4), rng = new Rng(o.seed);
  const q = t / meta.duration;
  const spread = 1 - (1 - clamp(t / 0.27)) ** 3;
  const lobes = [];
  for (let i = 0; i < 16; i++) {
    const angle = i * TAU / 11 + rng.range(-0.2, 0.2);
    const central = i >= 11;
    const distance = central ? rng.range(2, 8) : rng.range(12, 22);
    const life = rng.range(0.42, 0.59);
    const radius = central ? rng.range(10, 13) : rng.range(7, 10);
    const k = clamp(t / life);
    if (k >= 1) continue;
    const grow = 0.75 + 0.25 * Math.sin(Math.min(1, t / 0.14) * Math.PI / 2);
    const decay = (1 - clamp((k - 0.52) / 0.48)) ** 0.8;
    lobes.push({
      x: Math.cos(angle) * (4 + distance * spread) + Math.sin(q * 5 + angle) * 3 * q,
      y: Math.sin(angle) * ((central ? 4 : 10) + distance * spread * 0.55) - 17 * q,
      r: radius * grow * decay,
      alpha: 1 - clamp((k - 0.70) / 0.30),
    });
  }
  // The first dense vertical plume covers the body before opening into separate curls.
  if (t < 0.18) {
    const k = t / 0.18;
    for (const y of [-15, 0, 15]) {
      lobes.unshift({ x: Math.sin(y) * k * 3, y: y - 8 * k,
        r: 13 * (1 - k * 0.45), alpha: 1 - k * k });
    }
  }
  for (const layer of ['shade', 'body', 'cap']) {
    for (const b of lobes) {
      if (layer === 'shade') p.disc(b.x, b.y, b.r, C[0], b.alpha * 0.75);
      if (layer === 'body') p.disc(b.x - b.r * 0.1, b.y - b.r * 0.15, b.r * 0.89, b.y > 2 ? C[1] : C[2], b.alpha * 0.95);
      if (layer === 'cap') p.disc(b.x - b.r * 0.27, b.y - b.r * 0.38, b.r * 0.49, C[3], b.alpha * 0.85);
    }
  }
}
