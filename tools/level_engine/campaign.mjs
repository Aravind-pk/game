// Writes the design for campaign levels 6-50. Each chapter introduces one idea and its difficulty
// target starts easier and climbs, so a new mechanic gets room to be learned. The forge then tunes
// every spec, and re-rolls `variant` if a layout can't reach its target.

const TITLES = [
  'Dust Line', 'The Long Ditch', 'Night Shift', 'Broken Causeway', 'Last Light', // 6-10
  'False Colours', 'Bait and Hold', 'The Scarecrow Line', 'Empty Barrels', 'Drawn Fire',
  'Sacrifice Play', 'Hollow Guard', 'The Lure', 'Dead Reckoning', 'Red Herring', // 11-20
  'Soft Ground', 'Sinkhole Row', 'The Crumbling Mile', 'Fault Lines', 'Shifting Sands',
  'No Footing', 'Undermined', 'Collapse Point', 'Thin Crust', 'The Pit Road', // 21-30
  'Short Fuse', 'Powder Keg', 'Tripwire', 'Blast Radius', 'Chain Reaction',
  'Killing Ground', 'Deadfall', 'Slow Burn', 'Detonation Alley', 'The Big Bang', // 31-40
  'Dug In', 'Old Guard', 'Stand Fast', 'The Forgotten Post', 'Iron Will',
  'Holdout Ridge', 'No Retreat', 'Siege of Embers', 'The Final Watch', 'North Gate Stands', // 41-50
];

const CHAPTERS = [
  { from: 6, to: 10, easy: 0.06, hard: 0.012, minZone: 6 },
  { from: 11, to: 20, easy: 0.12, hard: 0.01, minZone: 5, note: "New: Decoys. They can't fire, but monsters stop to attack them. Hold the swarm inside your guns' range." },
  { from: 21, to: 30, easy: 0.09, hard: 0.006, minZone: 5, note: 'New: Unstable ground. Red tiles will not hold a turret, so the easy spots are gone.' },
  { from: 31, to: 40, easy: 0.08, hard: 0.005, minZone: 4, note: 'New: Rigged Decoys explode when destroyed, damaging every monster around them.' },
  { from: 41, to: 50, easy: 0.05, hard: 0.003, minZone: 4, note: 'New: Holdouts. Some turrets are already dug in. Build your plan around them.' },
];

const VIEW = [3, 13, 14, 21];
const REGIONS = {
  North: () => [3, 16, 3, 9],
  Northwest: () => [1, 4, 4, 10],
  Northeast: () => [15, 18, 4, 10],
  West: () => [0, 1, 14, 24],
  East: () => [18, 19, 14, 24],
};
const MONSTER_HP = { burrower: 32, stalker: 48, brute: 300 };
const SHAPES = [[1, 1], [2, 1], [1, 2], [3, 1], [1, 3], [2, 2]];

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

const overlaps = (a, b) => a[0] < b[0] + b[2] && b[0] < a[0] + a[2] && a[1] < b[1] + b[3] && b[1] < a[1] + a[3];

export function campaignRange() {
  return { from: CHAPTERS[0].from, to: CHAPTERS[CHAPTERS.length - 1].to };
}

export function buildSpec(id, variant) {
  const ch = CHAPTERS.findIndex((c) => id >= c.from && id <= c.to);
  const chapter = CHAPTERS[ch];
  const r = rng(id * 1009 + variant * 7919);
  const int = (lo, hi) => lo + Math.floor(r() * (hi - lo + 1));
  const pick = (list) => list[Math.floor(r() * list.length)];
  const progress = (id - chapter.from) / (chapter.to - chapter.from);

  // ---- enemies: more fronts and tougher types as the campaign goes on
  const fronts = progress < 0.3 && ch === 0 ? 1 : progress > 0.65 || ch >= 3 ? 3 : 2;
  const regions = Object.keys(REGIONS).sort(() => r() - 0.5).slice(0, fronts);
  let budget = 380 + id * 14;
  const burrowerLv = id >= 25 ? 2 : 1;
  const stalkerLv = id >= 35 ? 3 : 2;
  const bruteLv = id >= 45 ? 4 : 3;
  const hotspots = regions.map((name, i) => {
    const [x0, x1, y0, y1] = REGIONS[name]();
    const groups = [];
    let share = budget / (fronts - i);
    budget -= share;
    if (id >= 12 && r() < 0.28 + ch * 0.08) {
      groups.push({ type: 'brute', level: bruteLv, count: 1, interval: int(30, 40) / 10 });
      share -= MONSTER_HP.brute;
    }
    const type = id >= 7 && r() < 0.45 ? 'stalker' : 'burrower';
    const level = type === 'stalker' ? stalkerLv : burrowerLv;
    const hp = MONSTER_HP[type] * (1 + 0.3 * (level - (type === 'stalker' ? 2 : 1)));
    groups.unshift({
      type, level, count: Math.max(4, Math.round(Math.max(share, hp * 4) / hp)),
      interval: type === 'stalker' ? int(100, 140) / 100 : int(70, 100) / 100,
    });
    return { name, cell: [int(x0, x1), int(y0, y1)], delay: i === 0 ? 0 : int(2, 9), groups };
  });

  // ---- roster: three live turrets at most, with decoys alongside
  const gunLevel = id >= 36 ? 2 : 1;
  const live = [{ type: 'mg', level: id >= 26 ? 2 : 1, count: 2 }];
  if (id % 2 === 0 || ch >= 2) live.push({ type: 'cannon', level: gunLevel, count: 1 });
  else live.push({ type: 'sniper', level: gunLevel, count: 1 });
  const totalHp = hotspots.reduce((sum, h) => sum + h.groups.reduce((s, g) => s + g.count * MONSTER_HP[g.type], 0), 0);
  const ammoFor = { mg: Math.ceil(totalHp * 0.6 / 5), cannon: Math.ceil(totalHp * 0.5 / 42) + 3, sniper: Math.ceil(totalHp * 0.4 / 70) + 3 };
  const guns = live.map((g) => ({ ...g, ammo: ammoFor[g.type] }));
  const addDecoy = (type, count) => { if (count > 0) guns.push({ type, level: 1, ammo: 0, count }); };
  if (ch === 1) addDecoy('decoy', progress > 0.55 ? 2 : 1);
  if (ch === 2) addDecoy('decoy', int(0, 1));
  if (ch === 3) {
    addDecoy('rigged', progress > 0.5 ? 2 : 1);
    if (progress > 0.3) addDecoy('decoy', int(0, 1));
  }
  if (ch === 4) {
    addDecoy('decoy', int(0, 1));
    addDecoy('rigged', int(0, 1));
  }

  // ---- ground
  const obstacles = [];
  for (let tries = 0, want = int(4, 7); obstacles.length < want && tries < 200; tries++) {
    const [w, h] = pick(SHAPES);
    const o = [int(VIEW[0], VIEW[0] + VIEW[2] - w), int(14, 29), w, h];
    if (o[1] + h > 29 && o[0] < 12 && o[0] + w > 7) continue; // keep the gate approach open
    if (!obstacles.some((p) => overlaps(p, [o[0] - 1, o[1] - 1, w + 2, h + 2]))) obstacles.push(o);
  }
  const noBuild = [];
  if (ch === 2 || (ch === 4 && r() < 0.5)) {
    let area = 0;
    for (let tries = 0, want = int(3, 5); noBuild.length < want && tries < 200; tries++) {
      const w = int(2, 5);
      const h = int(2, 4);
      const o = [int(VIEW[0], VIEW[0] + VIEW[2] - w), int(14, 32 - h), w, h];
      if (area + w * h > 85 || noBuild.some((p) => overlaps(p, o))) continue;
      noBuild.push(o);
      area += w * h;
    }
  }
  const fixed = [];
  if (ch === 4) {
    for (let tries = 0, want = progress > 0.5 ? 2 : 1; fixed.length < want && tries < 200; tries++) {
      const c = [int(5, 14), int(17, 28)];
      const blocked = [...obstacles, ...noBuild].some((p) => overlaps(p, [c[0], c[1], 1, 1]));
      if (blocked || fixed.some((f) => Math.abs(f.cell[0] - c[0]) + Math.abs(f.cell[1] - c[1]) < 5)) continue;
      const type = r() < 0.65 ? 'mg' : 'cannon';
      fixed.push({ type, level: 1, ammo: type === 'mg' ? Math.ceil(ammoFor.mg * 0.3) : 3, cell: c });
    }
  }

  return {
    id: String(id).padStart(2, '0'),
    title: TITLES[id - 6],
    map: String(((id - 1) % 5) + 1).padStart(2, '0'),
    cols: 20,
    rows: 34,
    view: VIEW,
    gate_hp: 500,
    gate_cols: [8, 11],
    obstacles,
    ...(noBuild.length ? { no_build: noBuild } : {}),
    ...(fixed.length ? { fixed } : {}),
    ...(id === chapter.from && chapter.note ? { note: chapter.note } : {}),
    hotspots,
    guns,
    design: {
      target_win: Math.round(chapter.easy * Math.pow(chapter.hard / chapter.easy, progress) * 10000) / 10000,
      min_zone: chapter.minZone,
      gate_margin: 0.12,
    },
  };
}
