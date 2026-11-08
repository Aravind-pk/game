// Fast offline port of godot/scripts/sim/battle_sim.gd, used to search for and tune levels.
// It follows the GDScript step by step, including Godot's 32-bit Vector2 arithmetic (hence the
// fround calls), so results should match the game. tests/sim_check.gd re-runs every baked
// solution in the real simulation: that check is the authority, this file is only the search tool.
// If you change battle_sim.gd or defs.gd, change this file too.

const f = Math.fround;

export const SIM_DT = 1.0 / 30.0;
export const CELL = 2.0;
const EMERGE_WARN = 1.6;
const EMERGE_TIME = 0.9;
const RETARGET_INTERVAL = 0.25;
const MAX_BATTLE_TIME = 600.0;
const INF = 1 << 30;
const NEIGHBOURS = [[0, 1], [-1, 1], [1, 1], [-1, 0], [1, 0], [-1, -1], [1, -1], [0, -1]];

export const GUNS = {
  mg: { hp: 120, damage: 7, fire_rate: 6, range: 8, splash: 0, projectile_speed: 0, radius: 0.8, min_range: 0, falloff_start: 3, falloff_floor: 0.35, blast: 0, blast_radius: 0 },
  cannon: { hp: 170, damage: 42, fire_rate: 0.55, range: 11, splash: 2.6, projectile_speed: 16, radius: 1.0, min_range: 4, falloff_start: 11, falloff_floor: 1, blast: 0, blast_radius: 0 },
  decoy: { hp: 220, damage: 0, fire_rate: 1, range: 6, splash: 0, projectile_speed: 0, radius: 0.9, min_range: 0, falloff_start: 6, falloff_floor: 1, blast: 0, blast_radius: 0 },
  rigged: { hp: 90, damage: 0, fire_rate: 1, range: 6, splash: 0, projectile_speed: 0, radius: 0.9, min_range: 0, falloff_start: 6, falloff_floor: 1, blast: 110, blast_radius: 4.5 },
  sniper: { hp: 70, damage: 70, fire_rate: 0.45, range: 20, splash: 0, projectile_speed: 0, radius: 0.7, min_range: 7, falloff_start: 20, falloff_floor: 1, blast: 0, blast_radius: 0 },
};

export const MONSTERS = {
  burrower: { base_level: 1, hp: 32, speed: 2.3, damage: 7, attack_rate: 1.0, detect: 6, attack_range: 1.0, radius: 0.55 },
  stalker: { base_level: 2, hp: 48, speed: 4.4, damage: 9, attack_rate: 1.5, detect: 9, attack_range: 1.0, radius: 0.55 },
  brute: { base_level: 3, hp: 300, speed: 1.25, damage: 32, attack_rate: 0.6, detect: 5, attack_range: 1.6, radius: 1.15 },
};

export function gunStats(type, level) {
  const k = 1 + 0.25 * (level - 1);
  const s = GUNS[type];
  return { ...s, hp: s.hp * k, damage: s.damage * k };
}

export function monsterStats(type, level) {
  const s = MONSTERS[type];
  const k = 1 + 0.3 * (level - s.base_level);
  return { ...s, hp: s.hp * k, damage: s.damage * k };
}

const len = (x, y) => f(Math.sqrt(f(f(x * x) + f(y * y))));
const dist = (ax, ay, bx, by) => {
  const dx = f(ax - bx);
  const dy = f(ay - by);
  return f(Math.sqrt(f(f(dx * dx) + f(dy * dy))));
};
const norm = (x, y) => {
  const l2 = f(f(x * x) + f(y * y));
  if (l2 === 0) return [x, y];
  const l = f(Math.sqrt(l2));
  return [f(x / l), f(y / l)];
};

/** Map data that does not change between battles, shared so repeated runs stay cheap. */
export class Map2D {
  constructor(d) {
    this.d = d;
    this.cols = d.cols;
    this.rows = d.rows;
    this.wallRow = d.rows - 1;
    this.gateCols = d.gate_cols;
    this.view = d.view;
    this.gateHp = d.gate_hp;
    this.hotspots = d.hotspots;
    this.obstacles = d.obstacles ?? [];
    this.noBuild = d.no_build ?? [];
    this.fixed = (d.fixed ?? []).map((g) => ({ ...g, fixed: true }));
    this.base = new Uint8Array(this.cols * this.rows);
    for (let y = 0; y < this.rows; y++) {
      for (let x = 0; x < this.cols; x++) {
        this.base[y * this.cols + x] = y >= this.wallRow || this.isObstacle(x, y) ? 1 : 0;
      }
    }
    this.deployable = [];
    const [vx, vy, vw, vh] = this.view;
    for (let y = vy; y < vy + vh; y++) {
      for (let x = vx; x < vx + vw; x++) {
        if (this.isDeployable(x, y)) this.deployable.push([x, y]);
      }
    }
  }

  isObstacle(x, y) {
    return this.obstacles.some(([ox, oy, w, h]) => x >= ox && y >= oy && x < ox + w && y < oy + h);
  }

  isDeployable(x, y) {
    const [vx, vy, vw, vh] = this.view;
    if (x < vx || y < vy || x >= vx + vw || y >= vy + vh) return false;
    if (y >= this.wallRow || this.isObstacle(x, y)) return false;
    if (this.noBuild.some(([ox, oy, w, h]) => x >= ox && y >= oy && x < ox + w && y < oy + h)) return false;
    if (this.fixed.some((g) => g.cell[0] === x && g.cell[1] === y)) return false;
    return !this.hotspots.some((h) => dist(x, y, h.cell[0], h.cell[1]) < 1.5);
  }

  totalEnemies() {
    let n = 0;
    for (const h of this.hotspots) for (const g of h.groups) n += g.count;
    return n;
  }

  totalEnemyHp() {
    let t = 0;
    for (const h of this.hotspots) for (const g of h.groups) t += g.count * monsterStats(g.type, g.level).hp;
    return t;
  }
}

/** Turrets are numbered by cell so the same layout plays the same whatever order it was placed in. */
export function canonical(deployment) {
  return [...deployment].sort((a, b) => a.cell[1] - b.cell[1] || a.cell[0] - b.cell[0]);
}

export function simulate(map, deployment) {
  const cols = map.cols;
  const rows = map.rows;
  const guns = canonical([...deployment, ...map.fixed]).map((d, id) => {
    const s = gunStats(d.type, d.level);
    return {
      id, type: d.type, cell: d.cell, px: (d.cell[0] + 0.5) * CELL, py: (d.cell[1] + 0.5) * CELL,
      hp: s.hp, damage: s.damage, fireRate: s.fire_rate, range: s.range, splash: s.splash, minRange: s.min_range, falloffStart: s.falloff_start, falloffFloor: s.falloff_floor,
      blast: s.blast, blastRadius: s.blast_radius, fixed: !!d.fixed,
      projSpeed: s.projectile_speed, radius: s.radius, ammo: d.ammo, maxAmmo: d.ammo, cooldown: 0,
      alive: true, dealt: new Float64Array(map.hotspots.length), diedAt: -1,
    };
  });

  const schedule = [];
  map.hotspots.forEach((h, hotspot) => {
    let t = (h.delay ?? 0) + EMERGE_WARN;
    let seq = 0;
    for (const g of h.groups) {
      for (let k = 0; k < g.count; k++) {
        schedule.push({ t, hotspot, type: g.type, level: g.level, seq });
        t += g.interval ?? 1.0;
        seq++;
      }
    }
  });
  schedule.sort((a, b) => a.t - b.t || a.hotspot - b.hotspot || a.seq - b.seq);

  const blocked = new Uint8Array(cols * rows);
  const flow = new Int32Array(cols * rows);
  const gateY = map.wallRow * CELL;
  const gateX0 = map.gateCols[0] * CELL;
  const gateX1 = (map.gateCols[1] + 1) * CELL;
  const cellBlocked = (x, y) => x < 0 || y < 0 || x >= cols || y >= rows || blocked[y * cols + x] !== 0;
  const posBlocked = (x, y) => cellBlocked(Math.floor(x / CELL), Math.floor(y / CELL));

  function rebuild() {
    blocked.set(map.base);
    for (const g of guns) if (g.alive) blocked[g.cell[1] * cols + g.cell[0]] = 1;
    flow.fill(INF);
    const open = [];
    const gy = map.wallRow - 1;
    for (let x = map.gateCols[0]; x <= map.gateCols[1]; x++) {
      if (!cellBlocked(x, gy)) {
        flow[gy * cols + x] = 0;
        open.push(gy * cols + x);
      }
    }
    while (open.length) {
      let bi = 0;
      let bv = INF;
      for (let i = 0; i < open.length; i++) {
        if (flow[open[i]] < bv) {
          bv = flow[open[i]];
          bi = i;
        }
      }
      const c = open[bi];
      open[bi] = open[open.length - 1];
      open.pop();
      const cx = c % cols;
      const cy = (c - cx) / cols;
      for (const [dx, dy] of NEIGHBOURS) {
        const nx = cx + dx;
        const ny = cy + dy;
        if (cellBlocked(nx, ny)) continue;
        if (dx !== 0 && dy !== 0 && (cellBlocked(cx + dx, cy) || cellBlocked(cx, cy + dy))) continue;
        const cost = bv + (dx !== 0 && dy !== 0 ? 14 : 10);
        const idx = ny * cols + nx;
        if (cost < flow[idx]) {
          if (flow[idx] === INF) open.push(idx);
          flow[idx] = cost;
        }
      }
    }
  }

  function flowDir(px, py) {
    const cx = Math.floor(px / CELL);
    const cy = Math.floor(py / CELL);
    let here = INF;
    if (cx >= 0 && cy >= 0 && cx < cols && cy < rows && !cellBlocked(cx, cy)) here = flow[cy * cols + cx];
    if (here === 0) {
      const tx = f(Math.min(Math.max(px, gateX0 + 0.5), gateX1 - 0.5));
      return norm(f(tx - px), f(f(gateY) - py));
    }
    if (here === INF) return norm(f(f((gateX0 + gateX1) * 0.5) - px), f(f(gateY) - py));
    let best = here;
    let bx = cx;
    let by = cy;
    for (const [dx, dy] of NEIGHBOURS) {
      const nx = cx + dx;
      const ny = cy + dy;
      if (cellBlocked(nx, ny)) continue;
      if (dx !== 0 && dy !== 0 && (cellBlocked(cx + dx, cy) || cellBlocked(cx, cy + dy))) continue;
      const v = flow[ny * cols + nx];
      if (v < best) {
        best = v;
        bx = nx;
        by = ny;
      }
    }
    return norm(f((bx + 0.5) * CELL - px), f((by + 0.5) * CELL - py));
  }

  function move(m, dx, dy, d) {
    if (d <= 0) return;
    const s = f(d);
    const px = f(m.x + f(dx * s));
    const py = f(m.y + f(dy * s));
    if (!posBlocked(px, py)) {
      m.x = px;
      m.y = py;
      return;
    }
    const xFree = !posBlocked(px, m.y);
    const yFree = !posBlocked(m.x, py);
    if (Math.abs(dx) >= Math.abs(dy)) {
      if (xFree) m.x = px;
      else if (yFree) m.y = py;
    } else if (yFree) m.y = py;
    else if (xFree) m.x = px;
  }

  rebuild();
  let flowDirty = false;
  const monsters = [];
  const shells = [];
  let alive = 0;
  let kills = 0;
  let time = 0;
  let gateHp = map.gateHp;
  let state = 'running';
  let next = 0;
  let firstGateHit = -1;

  const attack = (m) => {
    m.cooldown -= SIM_DT;
    if (m.cooldown <= 0) {
      m.cooldown += 1 / m.attackRate;
      return true;
    }
    return false;
  };

  while (state === 'running') {
    time += SIM_DT;

    while (next < schedule.length && schedule[next].t <= time) {
      const s = schedule[next++];
      const st = monsterStats(s.type, s.level);
      const h = map.hotspots[s.hotspot];
      const k = s.seq % 9;
      const ang = s.seq * 2.39996;
      const hx = (h.cell[0] + 0.5) * CELL;
      const hy = (h.cell[1] + 0.5) * CELL;
      const sk = f(Math.sqrt(k));
      let x = f(hx + f(f(f(Math.cos(ang)) * 0.75) * sk));
      let y = f(hy + f(f(f(Math.sin(ang)) * 0.75) * sk));
      if (posBlocked(x, y)) {
        x = hx;
        y = hy;
      }
      monsters.push({
        id: monsters.length, x, y, hp: st.hp, speed: st.speed, damage: st.damage, attackRate: st.attack_rate,
        detect: st.detect, attackRange: st.attack_range, radius: st.radius, state: 1, stateT: EMERGE_TIME,
        target: -1, cooldown: 0.5, retarget: 0, hotspot: s.hotspot,
      });
      alive++;
    }

    // monsters
    for (const m of monsters) {
      if (m.state === 0) continue;
      if (m.state === 1) {
        m.stateT -= SIM_DT;
        if (m.stateT <= 0) m.state = 2;
        continue;
      }
      if (m.target >= 0 && !guns[m.target].alive) m.target = -1;
      m.retarget -= SIM_DT;
      if (m.target < 0 && m.retarget <= 0) {
        m.retarget = RETARGET_INTERVAL;
        let best = -1;
        let bestD = INF;
        for (const g of guns) {
          if (!g.alive) continue;
          const d = dist(m.x, m.y, g.px, g.py) - g.radius;
          if (d <= m.detect && d < bestD) {
            bestD = d;
            best = g.id;
          }
        }
        m.target = best;
      }
      if (m.target >= 0) {
        const g = guns[m.target];
        const tx = f(f(g.px) - m.x);
        const ty = f(f(g.py) - m.y);
        const gap = len(tx, ty) - g.radius - m.radius;
        const [fx, fy] = norm(tx, ty);
        if (gap > m.attackRange) {
          move(m, fx, fy, Math.min(m.speed * SIM_DT, gap - m.attackRange * 0.5));
        } else if (attack(m)) {
          g.hp -= m.damage;
          if (g.hp <= 0 && g.alive) {
            g.hp = 0;
            g.alive = false;
            g.diedAt = time;
            flowDirty = true;
            if (g.blast > 0) {
              for (const o of monsters) {
                if (o.state === 2 && o.hp > 0 && dist(f(g.px), f(g.py), o.x, o.y) <= g.blastRadius + o.radius) {
                  o.hp -= g.blast;
                  g.dealt[o.hotspot] += g.blast;
                }
              }
            }
          }
        }
      } else if (m.y >= gateY - m.radius - m.attackRange - 0.2 && m.x > gateX0 && m.x < gateX1) {
        if (attack(m)) {
          gateHp -= m.damage;
          if (firstGateHit < 0) firstGateHit = time;
        }
      } else {
        const [dx, dy] = flowDir(m.x, m.y);
        const lane = f(((m.id * 37) % 7 - 3) * 0.14);
        const [nx, ny] = norm(f(dx + f(f(-dy) * lane)), f(dy + f(dx * lane)));
        move(m, nx, ny, m.speed * SIM_DT);
      }
    }

    // separation
    for (let i = 0; i < monsters.length; i++) {
      const a = monsters[i];
      if (a.state !== 2) continue;
      for (let j = i + 1; j < monsters.length; j++) {
        const b = monsters[j];
        if (b.state !== 2) continue;
        const dx = f(b.x - a.x);
        const dy = f(b.y - a.y);
        const minD = a.radius + b.radius;
        const l2 = f(f(dx * dx) + f(dy * dy));
        if (l2 >= minD * minD) continue;
        const l = Math.sqrt(l2);
        let nx;
        let ny;
        if (l > 0.0001) {
          const fl = f(l);
          nx = f(dx / fl);
          ny = f(dy / fl);
        } else {
          nx = f(Math.cos(i * 7 + j));
          ny = f(Math.sin(i * 7 + j));
        }
        const push = f((minD - l) * 0.5);
        const ax = f(a.x - f(nx * push));
        const ay = f(a.y - f(ny * push));
        const bx = f(b.x + f(nx * push));
        const by = f(b.y + f(ny * push));
        if (!posBlocked(ax, ay)) {
          a.x = ax;
          a.y = ay;
        }
        if (!posBlocked(bx, by)) {
          b.x = bx;
          b.y = by;
        }
      }
    }

    // guns
    for (const g of guns) {
      if (!g.alive) continue;
      g.cooldown = Math.max(g.cooldown - SIM_DT, -SIM_DT);
      let t = -1;
      let bestD = INF;
      for (const m of monsters) {
        if (m.state !== 2 || m.hp <= 0) continue;
        const d = dist(g.px, g.py, m.x, m.y) - m.radius;
        if (d <= g.range && d >= g.minRange && d < bestD) {
          bestD = d;
          t = m.id;
        }
      }
      if (t < 0 || g.ammo <= 0 || g.cooldown > 0) continue;
      const m = monsters[t];
      g.ammo--;
      g.cooldown += 1 / g.fireRate;
      if (g.projSpeed > 0) {
        const d = dist(g.px, g.py, m.x, m.y);
        shells.push({ x: m.x, y: m.y, t: d / g.projSpeed, damage: g.damage, splash: g.splash, gun: g });
      } else {
        const d = dist(g.px, g.py, m.x, m.y) - m.radius;
        const fade = Math.min(Math.max((d - g.falloffStart) / Math.max(g.range - g.falloffStart, 0.001), 0), 1);
        const dmg = g.damage * (1 - fade * (1 - g.falloffFloor));
        m.hp -= dmg;
        g.dealt[m.hotspot] += dmg;
      }
    }

    // shells
    for (let i = 0; i < shells.length;) {
      const s = shells[i];
      s.t -= SIM_DT;
      if (s.t > 0) {
        i++;
        continue;
      }
      for (const m of monsters) {
        if (m.state === 2 && m.hp > 0 && dist(m.x, m.y, s.x, s.y) <= s.splash + m.radius) {
          m.hp -= s.damage;
          s.gun.dealt[m.hotspot] += s.damage;
        }
      }
      shells.splice(i, 1);
    }

    for (const m of monsters) {
      if (m.state !== 0 && m.hp <= 0) {
        m.state = 0;
        m.hp = 0;
        alive--;
        kills++;
      }
    }

    if (flowDirty) {
      rebuild();
      flowDirty = false;
    }
    if (gateHp <= 0) {
      gateHp = 0;
      state = 'defeat';
    } else if (next >= schedule.length && alive === 0) {
      state = 'victory';
    } else if (time > MAX_BATTLE_TIME) {
      state = 'defeat';
    }
  }

  return {
    win: state === 'victory', time, gateHp, kills, firstGateHit, total: schedule.length, guns,
    gunsLeft: guns.filter((g) => g.alive).length,
    ammoLeft: guns.reduce((n, g) => n + g.ammo, 0),
  };
}
