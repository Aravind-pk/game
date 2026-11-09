// North Gate level forge. Turns a level spec into a tuned level with baked solutions and hints.
//   node tools/level_engine/forge.mjs [level ids...]
//
// A spec (tools/level_engine/specs/level_NN.json) holds the map, the wave and the roster, plus a
// `design` block with the difficulty target. For each spec the forge:
//   1. searches for the most efficient winning deployment,
//   2. cuts ammo and gate HP down to what that deployment needs, plus a little slack,
//   3. measures how many random deployments still win, and raises enemy pressure until the share
//      is at or below the target while each turret still has a findable winning area,
//   4. writes godot/levels/level_NN.json with the solutions and the data hints need.
import { Worker, isMainThread, parentPort } from 'node:worker_threads';
import { existsSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { availableParallelism } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Map2D, canonical, simulate } from './sim.mjs';
import { buildSpec, campaignRange } from './campaign.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const SPECS = join(here, 'specs');
const OUTPUT = join(here, '../../godot/levels');

// Two search depths: the hand-specced levels get the thorough one, the campaign batch the quick one.
let PRESSURES = [1, 1.15, 1.3, 1.45, 1.6, 1.8, 2.0];
let SLACKS = [0.35, 0.25, 0.18]; // ammo above what the best plan uses: a near-miss layout should still be able to win
let TUNE_SAMPLES = 3000;
let FINAL_SAMPLES = 40000;
let CLIMB_ITERS = 250;
let TIGHTEN_ROUNDS = 4;
function useQuickSearch() {
  PRESSURES = [1, 1.25, 1.5, 1.8, 2.2];
  SLACKS = [0.35, 0.25, 0.18];
  TUNE_SAMPLES = 2000;
  FINAL_SAMPLES = 12000;
  CLIMB_ITERS = 130;
  TIGHTEN_ROUNDS = 2;
}
const HINT_RADIUS = 3;
const MAX_SOLUTIONS = 3;
const MIN_SHARE = 0.1; // a solution is rejected if any turret deals less than this share of the damage

function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const rosterOf = (d) => d.guns.flatMap((g) => Array.from({ length: g.count ?? 1 }, () => ({ type: g.type, level: g.level, ammo: g.ammo })));

function randomDeployment(map, roster, r) {
  const used = new Set();
  return roster.map((g) => {
    let c;
    do c = map.deployable[Math.floor(r() * map.deployable.length)]; while (used.has(c));
    used.add(c);
    return { ...g, cell: c };
  });
}

/** Turrets the player places that are meant to shoot (not decoys, not pre-placed holdouts). */
const isLive = (g) => g.maxAmmo > 0 && !g.fixed;

/** A decoy has to earn its slot: take it away from a winning plan and the plan must lose. */
function decoysMatter(map, dep) {
  return dep.every((g, i) => g.ammo > 0 || !simulate(map, dep.filter((_, k) => k !== i)).win);
}

/** The smallest share of total damage dealt by any one turret: low means a turret is along for the ride. */
function minShare(res) {
  const dealt = res.guns.filter(isLive).map((g) => g.dealt.reduce((a, b) => a + b, 0));
  const total = dealt.reduce((a, b) => a + b, 0);
  return total > 0 ? Math.min(...dealt) / total : 0;
}

function score(map, res) {
  const gate = res.gateHp / map.gateHp;
  if (!res.win) return 1000 * (res.kills / res.total) + 200 * gate;
  // Ammo is set per turret type from the busiest turret, so reward plans that share the work:
  // tightening around a balanced plan means no single turret can carry the wave.
  const types = [...new Set(res.guns.filter(isLive).map((g) => g.type))];
  const peak = types.reduce((sum, type) => {
    const same = res.guns.filter((g) => g.type === type && isLive(g));
    return sum + Math.max(...same.map((g) => (g.maxAmmo - g.ammo) / g.maxAmmo));
  }, 0) / types.length;
  return 2000 + 300 * gate + 800 * (1 - peak) + 40 * res.gunsLeft + 1200 * Math.min(1, minShare(res) / (MIN_SHARE * 2));
}

function runTask(t) {
  const map = new Map2D(t.level);
  const roster = rosterOf(t.level);
  const r = rng(t.seed);
  if (t.kind === 'sample') {
    let wins = 0;
    const top = [];
    for (let i = 0; i < t.n; i++) {
      const dep = randomDeployment(map, roster, r);
      const res = simulate(map, dep);
      if (res.win) wins++;
      top.push({ dep, s: score(map, res) });
      if (top.length > 64) {
        top.sort((a, b) => b.s - a.s);
        top.length = 8;
      }
    }
    top.sort((a, b) => b.s - a.s);
    return { wins, n: t.n, top: top.slice(0, 8) };
  }
  if (t.kind === 'climb') {
    let cur = t.start.map((g, i) => ({ ...roster[i], ...g, ammo: roster.find((x) => x.type === g.type).ammo }));
    const full = (dep) => {
      const res = simulate(map, dep);
      const s = score(map, res);
      return res.win && !decoysMatter(map, dep) ? s - 1500 : s;
    };
    let curS = full(cur);
    for (let it = 0; it < t.iters; it++) {
      const gi = Math.floor(r() * cur.length);
      let c;
      if (r() < 0.65) {
        c = [cur[gi].cell[0] + Math.floor(r() * 5) - 2, cur[gi].cell[1] + Math.floor(r() * 5) - 2];
      } else {
        c = map.deployable[Math.floor(r() * map.deployable.length)];
      }
      if (!map.isDeployable(c[0], c[1]) || cur.some((g) => g.cell[0] === c[0] && g.cell[1] === c[1])) continue;
      const cand = cur.map((g, i) => (i === gi ? { ...g, cell: c } : g));
      const s = full(cand);
      if (s >= curS) {
        cur = cand;
        curS = s;
      }
    }
    return { dep: cur, s: curS };
  }
  if (t.kind === 'zone') {
    const wins = [];
    const occupied = new Set(t.dep.filter((_, i) => i !== t.gun).map((g) => `${g.cell[0]},${g.cell[1]}`));
    for (const c of map.deployable) {
      if (occupied.has(`${c[0]},${c[1]}`)) continue;
      const cand = t.dep.map((g, i) => (i === t.gun ? { ...g, cell: c } : g));
      if (simulate(map, cand).win) wins.push(c);
    }
    return { gun: t.gun, wins };
  }
  throw new Error(`unknown task ${t.kind}`);
}

function makePool(size) {
  const workers = Array.from({ length: size }, () => new Worker(fileURLToPath(import.meta.url)));
  const run = (tasks) => new Promise((resolve, reject) => {
    const results = new Array(tasks.length);
    let next = 0;
    let done = 0;
    if (!tasks.length) resolve(results);
    const feed = (w) => {
      if (next < tasks.length) {
        const id = next++;
        w.postMessage({ id, task: tasks[id] });
      }
    };
    for (const w of workers) {
      w.removeAllListeners('message');
      w.removeAllListeners('error');
      w.on('error', reject);
      w.on('message', ({ id, result }) => {
        results[id] = result;
        if (++done === tasks.length) resolve(results);
        else feed(w);
      });
      feed(w);
    }
  });
  return { run, size, close: () => Promise.all(workers.map((w) => w.terminate())) };
}

function applyPressure(spec, pressure) {
  const d = structuredClone(spec);
  delete d.design;
  for (const h of d.hotspots) {
    for (const g of h.groups) {
      g.count = Math.max(1, Math.round(g.count * pressure));
      g.interval = Math.round(((g.interval ?? 1) / Math.sqrt(pressure)) * 100) / 100;
    }
  }
  for (const g of d.guns) g.ammo = Math.ceil(g.ammo * 1.6 * pressure);
  return d;
}

async function sampleLevel(pool, level, n, seed) {
  const per = Math.ceil(n / pool.size);
  const out = await pool.run(Array.from({ length: pool.size }, (_, i) => ({ kind: 'sample', level, n: per, seed: seed + i })));
  return {
    wins: out.reduce((a, b) => a + b.wins, 0),
    n: per * pool.size,
    top: out.flatMap((o) => o.top).sort((a, b) => b.s - a.s),
  };
}

async function climb(pool, level, starts, seed, iters = CLIMB_ITERS) {
  const tasks = starts.map((start, i) => ({ kind: 'climb', level, start, iters, seed: seed + i * 17 }));
  return (await pool.run(tasks)).sort((a, b) => b.s - a.s);
}

/** Cuts ammo and gate HP down to what `dep` actually needs, plus slack. */
function tighten(level, dep, slack, gateMargin, baseGate) {
  const map = new Map2D(level);
  const res = simulate(map, dep);
  if (!res.win) return null;
  const out = structuredClone(level);
  for (const g of out.guns) {
    if (g.ammo <= 0) continue;
    const used = Math.max(...res.guns.filter((x) => x.type === g.type && !x.fixed).map((x) => x.maxAmmo - x.ammo), 1);
    g.ammo = Math.max(used + 1, Math.ceil(used * (1 + slack)));
  }
  const taken = map.gateHp - res.gateHp;
  out.gate_hp = Math.max(60, Math.ceil((taken + baseGate * gateMargin) / 10) * 10);
  return out;
}

const refit = (level, dep) => dep.map((g) => ({ ...g, ammo: level.guns.find((x) => x.type === g.type).ammo }));

async function zonesOf(pool, level, dep) {
  const res = await pool.run(dep.map((_, gun) => ({ kind: 'zone', level, dep, gun, seed: 0 })));
  return dep.map((g, i) => {
    // keep only the connected area around the solution cell: what the player actually sees as one spot
    const set = new Set(res[i].wins.map(([x, y]) => `${x},${y}`));
    const seen = new Set([`${g.cell[0]},${g.cell[1]}`]);
    const stack = [g.cell];
    const cells = [g.cell];
    while (stack.length) {
      const [x, y] = stack.pop();
      for (let dx = -1; dx <= 1; dx++) {
        for (let dy = -1; dy <= 1; dy++) {
          const k = `${x + dx},${y + dy}`;
          if (set.has(k) && !seen.has(k)) {
            seen.add(k);
            stack.push([x + dx, y + dy]);
            cells.push([x + dx, y + dy]);
          }
        }
      }
    }
    return { all: res[i].wins.length, cells };
  });
}

/** Same layout (turrets of a type are interchangeable) within `tol` cells of another? */
function sameLayout(a, b, tol = 3) {
  const used = new Set();
  return a.every((g) => {
    const j = b.findIndex((h, k) => !used.has(k) && h.type === g.type
      && Math.max(Math.abs(h.cell[0] - g.cell[0]), Math.abs(h.cell[1] - g.cell[1])) <= tol);
    if (j < 0) return false;
    used.add(j);
    return true;
  });
}

async function tune(pool, spec, log) {
  const design = spec.design;
  const seedBase = Number(spec.id) * 100000;
  let best = null;
  let tooHard = false;
  for (const [pi, pressure] of PRESSURES.entries()) {
    const loose = applyPressure(spec, pressure);
    loose.gate_hp = spec.gate_hp;
    const seed = seedBase + pi * 1000;
    const scouts = await sampleLevel(pool, loose, 2500, seed);
    const starts = scouts.top.slice(0, pool.size * 2).map((t) => t.dep);
    let wins = (await climb(pool, loose, starts, seed + 500)).filter((c) => simulate(new Map2D(loose), c.dep).win);
    if (!wins.length) {
      log(`  pressure ${pressure}: no winning deployment found, stopping`);
      break;
    }
    let anyViable = false;
    for (const slack of SLACKS) {
      let level = structuredClone(loose);
      let dep = wins[0].dep;
      for (let round = 0; round < TIGHTEN_ROUNDS; round++) {
        const t = tighten(level, dep, slack, design.gate_margin, spec.gate_hp);
        if (!t) break;
        level = t;
        dep = refit(level, dep);
        const again = await climb(pool, level, Array.from({ length: pool.size }, () => dep), seed + 2000 + round * 97);
        if (simulate(new Map2D(level), again[0].dep).win) dep = again[0].dep;
      }
      const final = tighten(level, dep, slack, design.gate_margin, spec.gate_hp);
      if (!final) continue;
      level = final;
      dep = refit(level, dep);
      const zones = await zonesOf(pool, level, dep);
      const minZone = Math.min(...zones.map((z) => z.cells.length));
      const s = await sampleLevel(pool, level, TUNE_SAMPLES, seed + 3000);
      const rate = s.wins / s.n;
      const share = minShare(simulate(new Map2D(level), dep));
      const viable = minZone >= design.min_zone && share >= MIN_SHARE && decoysMatter(new Map2D(level), dep);
      log(`  pressure ${pressure} slack ${slack}: random win ${(rate * 100).toFixed(2)}%, zones [${zones.map((z) => z.cells.length)}], `
        + `gate ${level.gate_hp}, ammo [${level.guns.map((g) => g.ammo)}], min share ${(share * 100).toFixed(0)}%${viable ? '' : ' (rejected)'}`);
      if (!viable) continue;
      anyViable = true;
      // Settings are tried from easiest to hardest. Keep whichever lands closest to the target (on a
      // log scale, so 2x too hard counts the same as 2x too easy) and stop once inside the band, or
      // once a setting is already too hard, since everything after it is harder still.
      const meets = inBand(rate, design.target_win);
      const miss = missOf(rate, design.target_win);
      if (!best || miss < best.miss) best = { level, dep, rate, pressure, slack, meets, miss, seed };
      if (rate < design.target_win / BAND) tooHard = true;
      if (meets || tooHard) break;
    }
    if (best?.meets || tooHard) break;
    if (!anyViable && best) break;
  }
  return best;
}

const REGION_X = (x, view) => {
  const t = (x + 0.5 - view[0]) / view[2];
  return t < 0.36 ? 'left' : t > 0.64 ? 'right' : 'centre';
};
const REGION_Y = (y, view) => {
  const t = (y + 0.5 - view[1]) / view[3];
  return t < 0.36 ? 'far forward' : t > 0.68 ? 'close to the gate' : 'mid-field';
};
const article = (name) => (/^[AEIOUM]/.test(name) && !/^Mu/.test(name) ? 'an' : 'a');
const GUN_NAMES = { mg: 'MG Turret', cannon: 'Cannon', sniper: 'Sniper', decoy: 'Decoy', rigged: 'Rigged Decoy' };

/** Plain-language clues worked out from how the best solution actually plays. */
function intel(level, dep) {
  const map = new Map2D(level);
  const res = simulate(map, dep);
  const lines = [];
  const multi = level.hotspots.length > 1;
  for (const g of res.guns) {
    if (g.fixed) continue;
    if (g.maxAmmo <= 0) {
      lines.push(`Set ${article(GUN_NAMES[g.type])} ${GUN_NAMES[g.type]} ${REGION_Y(g.cell[1], level.view)}, ${REGION_X(g.cell[0], level.view)}: monsters will stop there.`);
      continue;
    }
    const total = g.dealt.reduce((a, b) => a + b, 0);
    let top = 0;
    g.dealt.forEach((v, i) => { if (v > g.dealt[top]) top = i; });
    const name = GUN_NAMES[g.type];
    const where = `${REGION_Y(g.cell[1], level.view)}, ${REGION_X(g.cell[0], level.view)}`;
    if (multi && total > 0 && g.dealt[top] / total > 0.6) {
      lines.push(`Point ${article(name)} ${name} at the ${level.hotspots[top].name} fissure: it works best ${where}.`);
    } else {
      const a = article(name);
      lines.push(`${a[0].toUpperCase()}${a.slice(1)} ${name} earns its ammo ${where}.`);
    }
  }
  const used = res.guns.filter(isLive).reduce((n, g) => n + g.maxAmmo - g.ammo, 0);
  const total = res.guns.filter(isLive).reduce((n, g) => n + g.maxAmmo, 0);
  const spare = 1 - used / total;
  lines.unshift(spare < 0.3
    ? `Ammo is tight: a winning plan spends about ${Math.round(100 * (1 - spare))}% of it, so every turret must stay busy.`
    : 'You have some spare ammo. Keep your turrets alive and covering the routes.');
  return [...new Set(lines)];
}

function formatLevel(obj) {
  return `${JSON.stringify(obj, null, 1)
    .replace(/\[\s+(-?\d+(?:\.\d+)?)(?:,\s+(-?\d+(?:\.\d+)?))(?:,\s+(-?\d+(?:\.\d+)?))?(?:,\s+(-?\d+(?:\.\d+)?))?\s+\]/g, (m, ...g) => `[${g.slice(0, 4).filter((v) => typeof v === 'string' && v !== '').join(', ')}]`)}\n`;
}

async function finalize(pool, spec, best, log) {
  const { level, dep } = best;
  const map = new Map2D(level);
  const seed = Number(spec.id) * 7001;
  const scouts = await sampleLevel(pool, level, FINAL_SAMPLES, seed);
  const seeds = [dep, ...scouts.top.slice(0, pool.size * 3 - 1).map((t) => t.dep)];
  const climbed = await climb(pool, level, seeds, seed + 50, CLIMB_ITERS * 2);
  const candidates = [{ dep, s: score(map, simulate(map, dep)) }, ...climbed].filter((c) => simulate(map, c.dep).win);
  const distinct = [];
  for (const c of candidates) {
    if (distinct.length < MAX_SOLUTIONS * 3 && !distinct.some((x) => sameLayout(x.dep, c.dep))) distinct.push(c);
  }
  const solutions = [];
  for (const c of distinct) {
    if (solutions.length >= MAX_SOLUTIONS) break;
    const zones = await zonesOf(pool, level, c.dep);
    if (Math.min(...zones.map((z) => z.cells.length)) < spec.design.min_zone) continue;
    const res = simulate(map, c.dep);
    if (minShare(res) < MIN_SHARE || !decoysMatter(map, c.dep)) continue;
    const sorted = canonical(c.dep);
    const order = sorted.map((g) => c.dep.indexOf(g));
    solutions.push({
      gate_left: Math.round(res.gateHp),
      ammo_left: res.ammoLeft,
      guns: sorted.map((g, i) => ({
        type: g.type,
        cell: g.cell,
        zone: zones[order[i]].cells
          .filter(([x, y]) => Math.max(Math.abs(x - g.cell[0]), Math.abs(y - g.cell[1])) <= HINT_RADIUS)
          .sort((a, b) => a[1] - b[1] || a[0] - b[0]),
      })),
    });
  }
  const rate = scouts.wins / scouts.n;
  const out = {
    ...level,
    design: {
      pressure: best.pressure,
      ammo_slack: best.slack,
      random_win_pct: Math.round(rate * 10000) / 100,
      random_samples: scouts.n,
      target_win_pct: Math.round(spec.design.target_win * 10000) / 100,
    },
    intel: intel(level, solutions.length ? solutions[0].guns.map((g) => ({ ...g, level: level.guns.find((x) => x.type === g.type).level, ammo: level.guns.find((x) => x.type === g.type).ammo })) : dep),
    solutions,
  };
  writeFileSync(join(OUTPUT, `level_${spec.id}.json`), formatLevel(out));
  log(`  => L${spec.id}: random win ${(rate * 100).toFixed(2)}% of ${scouts.n}, pressure ${best.pressure}, slack ${best.slack}, `
    + `gate ${level.gate_hp}, ammo [${level.guns.map((g) => g.ammo)}], enemies ${map.totalEnemies()}, solutions ${solutions.length}, `
    + `zones [${solutions.map((s) => s.guns.map((g) => g.zone.length).join('/')).join(' | ')}]`);
}

/** A tuned level is accepted when its random-win rate is within BAND times its target, either way. */
const BAND = 2;
const inBand = (rate, target) => rate <= target * BAND && rate >= target / BAND;

/** How far a random-win rate is from its target, on a log scale (1 = on target, 2 = twice or half). */
const missOf = (rate, target) => Math.exp(Math.abs(Math.log(Math.max(rate, 1e-5) / target)));

/** Forges generated levels, re-rolling a layout (up to 5 tries) if it can't get near its target. */
async function forgeCampaign(pool, from, to, log) {
  useQuickSearch();
  const failed = [];
  for (let id = from; id <= to; id++) {
    const name = `level_${String(id).padStart(2, '0')}.json`;
    if (existsSync(join(OUTPUT, name))) continue; // finished in an earlier run
    const t0 = performance.now();
    let chosen = null;
    // FORGE_VARIANT_OFFSET tries fresh layouts when re-forging a level whose first five missed.
    const first = Number(process.env.FORGE_VARIANT_OFFSET) || 0;
    for (let variant = first; variant < first + 5; variant++) {
      const spec = buildSpec(id, variant);
      log(`L${spec.id} ${spec.title} v${variant}: target ${(spec.design.target_win * 100).toFixed(2)}%`);
      const best = await tune(pool, spec, log);
      if (!best) continue;
      // Two-sided: a layout far harder than its target is as much an outlier as one far easier.
      const miss = missOf(best.rate, spec.design.target_win);
      if (!chosen || miss < chosen.miss) chosen = { spec, best, miss };
      if (inBand(best.rate, spec.design.target_win)) break;
    }
    if (!chosen) {
      log(`  !! L${id}: no viable layout found`);
      failed.push(id);
      continue;
    }
    writeFileSync(join(SPECS, name), `${JSON.stringify(chosen.spec, null, 1)}\n`);
    await finalize(pool, chosen.spec, chosen.best, log);
    log(`  (${((performance.now() - t0) / 1000).toFixed(0)}s)`);
  }
  log(failed.length ? `FAILED LEVELS: ${failed.join(', ')}` : 'CAMPAIGN COMPLETE');
}

async function main() {
  const only = new Set(process.argv.slice(2));
  const pool = makePool(Number(process.env.FORGE_WORKERS) || Math.max(1, availableParallelism() - 1));
  const log = (m) => console.log(m);
  if (process.env.FORGE_QUICK) useQuickSearch();
  if (only.has('--campaign')) {
    const range = campaignRange();
    const nums = process.argv.slice(2).filter((a) => /^\d+$/.test(a)).map(Number);
    await forgeCampaign(pool, nums[0] ?? range.from, nums[1] ?? nums[0] ?? range.to, log);
    await pool.close();
    return;
  }
  for (const file of readdirSync(SPECS).filter((n) => /^level_\d+\.json$/.test(n)).sort()) {
    const spec = JSON.parse(readFileSync(join(SPECS, file), 'utf8'));
    if (only.size && !only.has(spec.id)) continue;
    const t0 = performance.now();
    log(`L${spec.id} ${spec.title}: target ${(spec.design.target_win * 100).toFixed(1)}%, min zone ${spec.design.min_zone}`);
    const best = await tune(pool, spec, log);
    if (!best) {
      log(`  !! no viable tuning found for L${spec.id}, level left unchanged`);
      continue;
    }
    if (!best.meets) log(`  note: target not reached, closest was ${(best.rate * 100).toFixed(2)}%`);
    await finalize(pool, spec, best, log);
    log(`  (${((performance.now() - t0) / 1000).toFixed(0)}s)`);
  }
  await pool.close();
}

if (!isMainThread) {
  parentPort.on('message', ({ id, task }) => parentPort.postMessage({ id, result: runTask(task) }));
} else {
  await main();
}
