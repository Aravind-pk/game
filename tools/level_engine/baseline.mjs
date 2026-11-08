// Measures how winnable the levels in godot/levels are, using uniformly random deployments.
//   node tools/level_engine/baseline.mjs [trials]
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Map2D, simulate } from './sim.mjs';

const levelsDir = join(dirname(fileURLToPath(import.meta.url)), '../../godot/levels');
const trials = Number(process.argv[2] ?? 2000);

let seed = 12345;
const rnd = () => {
  seed = (seed * 1664525 + 1013904223) >>> 0;
  return seed / 4294967296;
};

for (const file of readdirSync(levelsDir).filter((n) => /^level_\d+\.json$/.test(n)).sort()) {
  const d = JSON.parse(readFileSync(join(levelsDir, file), 'utf8'));
  const map = new Map2D(d);
  const roster = d.guns.flatMap((g) => Array(g.count ?? 1).fill(g));
  const empty = simulate(map, []);
  let wins = 0;
  const t0 = performance.now();
  for (let i = 0; i < trials; i++) {
    const used = new Set();
    const dep = roster.map((g) => {
      let c;
      do c = map.deployable[Math.floor(rnd() * map.deployable.length)]; while (used.has(c));
      used.add(c);
      return { type: g.type, level: g.level, ammo: g.ammo, cell: c };
    });
    if (simulate(map, dep).win) wins++;
  }
  const ms = (performance.now() - t0) / trials;
  console.log(`L${d.id} ${d.title.padEnd(20)} cells=${map.deployable.length} undefended=${empty.win ? 'WIN?!' : `lost@${empty.time.toFixed(0)}s`} `
    + `randomWin=${(100 * wins / trials).toFixed(1)}%  ${ms.toFixed(2)}ms/run`);
}
