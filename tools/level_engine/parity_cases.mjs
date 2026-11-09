// Writes battles simulated by the Node port so tests/port_parity.gd can replay them in Godot.
//   node tools/level_engine/parity_cases.mjs out.json [per_level]
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Map2D, canonical, simulate } from './sim.mjs';

const levelsDir = join(dirname(fileURLToPath(import.meta.url)), '../../godot/levels');
const out = process.argv[2];
const perLevel = Number(process.argv[3] ?? 25);

let seed = 987654321;
const rnd = () => {
  seed = (seed * 1664525 + 1013904223) >>> 0;
  return seed / 4294967296;
};

const cases = [];
for (const file of readdirSync(levelsDir).filter((n) => /^level_\d+\.json$/.test(n)).sort()) {
  const d = JSON.parse(readFileSync(join(levelsDir, file), 'utf8'));
  const map = new Map2D(d);
  const roster = d.guns.flatMap((g) => Array(g.count ?? 1).fill(g));
  for (let i = 0; i < perLevel; i++) {
    const used = new Set();
    const dep = canonical(roster.map((g) => {
      let c;
      do c = map.deployable[Math.floor(rnd() * map.deployable.length)]; while (used.has(c));
      used.add(c);
      // every other case gives each Cannon and Sniper its order, so orders stay in step too
      const order = i % 2 === 1 ? ({ sniper: 'heavy' })[g.type] : undefined;
      return order ? { type: g.type, level: g.level, ammo: g.ammo, cell: c, order } : { type: g.type, level: g.level, ammo: g.ammo, cell: c };
    }));
    const r = simulate(map, dep);
    cases.push({
      file, deployment: canonical([...dep, ...(d.fixed ?? [])]), win: r.win, steps: Math.round(r.time * 30), gate_hp: r.gateHp, kills: r.kills,
      guns_left: r.gunsLeft, ammo_left: r.ammoLeft,
    });
  }
}
writeFileSync(out, JSON.stringify(cases));
console.log(`${cases.length} cases written to ${out}`);
