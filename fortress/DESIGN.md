# Fortress — gameplay design (prototype)

A portrait defense-and-build game in low-poly 3D. You live behind a **fence you can climb anywhere
except at its towers**; monsters can't climb it. Outside are the trees (left flank), the rocks
(right flank) and three **winding paths** that come in from off the map; inside is everything you
build. Monsters follow their paths to the fence and wait there. Step out to gather and they come for you.

The world is 30 m wide (1200 design px); the camera follows you. Style: a Victorian British
frontier fort in Kingshot-like low poly. Green field with cone trees, beige paths and faceted rocks;
a thin whitewashed wall with red coping; round red-banded bastions with pennants and period guns
(brass swivel gun, brass Gatling, iron cannon); a brick powder works; cottages in the sand yard.
You are a chibi redcoat (white pith helmet, cross-belts, musket) who carries his load in his arms;
the woodcutter is a redcoat pioneer (forage cap, leather apron, axe).

## The loop

**Climb out → gather (and fight) → climb back in → build or craft → feed the turrets → repeat.**

## Controls

- Drag anywhere to move (a virtual joystick appears under your thumb). WASD or arrows on desktop.
- Walk into the fence (away from a tower) to **vault over it**: a 0.6 s crouch-and-hop either way.
- No buttons. Things happen by **standing near them**:
  - next to a tree or rock (outside): you harvest one item at a time onto the stack on your back;
  - on a build pad: the materials it still needs fly off your stack into it;
  - at the ammo machine: your wood goes in; at its output pile, boxes come out to you;
  - next to a turret (from inside): your ammo boxes load into it;
  - over monster coins on the ground: they go straight into your wallet (no stack space).
- Your own gun fires by itself at the nearest monster in close range (130 px) while your bag has shots.
- A small arrow at your feet points at the most useful thing to do, routed over the fence at a spot
  clear of the towers and, if possible, of monsters waiting there.
- Red markers on the screen edge show monsters that are still off screen.

## What you carry

| | Holds | Filled at | Used for |
|---|---|---|---|
| **Stack** (on your back) | 10 items (18 with Bigger pack) | Trees, rocks, machine output | Building, feeding the machine, carrying boxes to turrets |
| **Ammo bag** (your gun) | 30 shots, separate from the stack | Machine output: the bag fills first, 1 box = 10 shots | Your gun |
| **Wallet** | unlimited, separate from the stack | Monster coins you walk over | Launchers, woodcutter, turret upgrades |

## Materials

| Item | Shape | From | For |
|---|---|---|---|
| Wood | brown square | Trees on the left, outside (5 per tree, regrow in 7 s) | Ammo, turrets, pack, woodcutter |
| Stone | grey square | Rocks on the right, outside | Turrets, launchers, fence |
| Monster coin | gold circle | Dropped by monsters in the lanes (1, or 4 from a brute); fades after 30 s | Wallet: launchers and woodcutter. Every coin also charges the power meter |
| Ammo box | yellow square | The ammo machine: 1 wood → 2 boxes | Turrets (1 box = 10 shots), your bag |

You only pick up what something currently needs.

## The fortress

- **Fence** across the whole map. The worker and the woodcutter climb it anywhere but at a tower;
  monsters never get over it.
- **Turrets are towers in the fence**, one per lane, loaded from the inside. Monsters never attack
  them. Range 230 px, 2 shots/s, up to 5 boxes.
- **Inside**: the ammo machine, its output pile, launchers, other pads, and houses that grow with
  every building.

Build pads, two open at a time:

| # | Pad | Cost | Effect |
|---|---|---|---|
| — | Centre turret | already built | Covers the middle lane |
| 1 | Ammo machine | 8 wood | Wood in, boxes out onto its pile. You still have to distribute them |
| 2 | Left turret | 5 wood, 5 stone | Tower in the fence on the left lane |
| 3 | Right turret | 5 wood, 5 stone | Tower on the right lane |
| 4 | Launcher (left) | 6 stone, 3 coins | Takes boxes from the machine pile and lobs them to turrets in its reach (left and centre) |
| 5 | Fence +4 | 8 stone | Four more monsters can wait at the fence |
| 6 | Bigger pack | 10 wood | Stack holds 18 |
| 7 | Launcher (right) | 6 stone, 4 coins | Reaches the centre and right turrets |
| 8 | Woodcutter | 5 coins, 6 wood | Helper: climbs out over the fence, chops trees, feeds the machine. Monsters ignore it |

## Powers

Every monster coin you pick up also adds one **energy** (up to 24; coins are not spent). The powers
sit in a column on the right edge, always visible: a lit button can be tapped now, a ring and a
number show the time left on one that is running.

| Group | Power | Energy | Effect |
|---|---|---:|---|
| Hero | Heal | 6 | All hearts back |
| Hero | Sprint | 6 | You move 60% faster for 10 s |
| Hero | Fury | 8 | Your musket fires 3× as fast for double damage for 10 s (and the bag is at least half full) |
| Fort | Rapid | 14 | All turrets fire twice as fast for 12 s |
| Fort | Freeze | 14 | Every monster moves at 35% speed for 8 s |
| Fort | Bomb | 20 | 6 damage to every monster on the field |
| Fort | Supply | 12 | +2 boxes in every turret and a full ammo bag |

## Turret upgrades and evolutions

Small round pads appear just inside the fence under each built turret. **Stand still on one for
0.6 s** to buy it with coins (a gold ring fills while you wait, so walking past never buys anything).
Names show when you are close.

| Step | Cost | Effect |
|---|---|---|
| Level 2 | 8 coins | 1.5 damage per shot (from 1) |
| Evolve: **Gatling** (orange, twin barrels) | 15 coins | 1 damage, twice the fire rate: shreds swarms, eats ammo |
| Evolve: **Cannon** (grey, fat barrel) | 15 coins | 3 damage to everything within 55 px of the target, slow fire |
| Evolve: **Frost** (blue) | 15 coins | 1.5 damage and halves the target's speed for 2 s |

Each turret evolves once, so the three lanes can be built differently. Level pips sit on top of
each turret.

## Monsters

They come in from off the map and follow their winding path to the fence, then **wait there**
(they don't die on it). Turrets and your gun can still shoot them while they wait.

| Monster | Shape | HP | Speed | Notices you within | Hit | Coins | From wave |
|---|---|---:|---:|---:|---:|---:|---:|
| Grunt | round red blob with horns | 3 | 56 | 90 px | 1 heart | 1 coin | 1 |
| Runner | tall orange cyclops | 2 | 112 | 130 px | 1 heart | 1 | 3 |
| Brute | big dark red block with tusks | 14 | 40 | 70 px | 2 hearts | 4 | 5 |

A monster that notices you (a red "!" over it) chases you until you are more than 260 px away or
back over the fence; then it returns to its path. Waiting monsters chase you if you climb out next
to them. Monsters get 23% more HP every wave.

## How you lose

Only one way: **the fence gives way**, when the number of monsters waiting at it reaches its
capacity (10, 14 with the upgrade). Shown as the FENCE pips in the top bar.

## Getting hurt

A monster that reaches you lunges and knocks you back a step, taking a heart (two for a brute).
Hearts come back while you are inside (one every 4 s). Lose the last one and you are **knocked
out**: you drop everything you carry, monsters lose interest, and after 6 s you are back inside
with full hearts. It costs time and your load, not the game.

Survive wave 12 with the field cleared and the fortress holds.

## Waves

12 waves. The first comes after 30 s; 16 s breaks between waves. Wave *n* brings 4 + 3n grunts,
runners from wave 3 and brutes from wave 5, one every 1.1 s in a random lane.

## The tension this creates

- Everything you need is outside, and outside is where the monsters are. Each trip is a choice:
  how full is your bag, are monsters waiting along the fence, are the coins on a path worth the risk?
- Ammo has to be shuttled by hand until launchers take over, and launchers cost coins, which
  means going into the lanes. Coins also charge the power-up: save it for the heavy waves.
- A chaser on your tail costs hearts while you climb: shoot it first, or hop the fence where it is clear.
- Monsters piling up at the fence are a slow clock: feed the turrets or the fence gives.

## Balance check

`godot --headless --path fortress -- sim=bot pace=1 seed=1` runs the built-in bot (the same logic
as the guide arrow) and prints a log. `pace` slows it down to stand in for a human; `sim=idle`
never moves; `seed` changes the lanes monsters spawn in. Four seeds each:

| Player | Wins |
|---|---|
| Bot, full speed | 4 of 4 |
| Bot, 70% speed | 2 of 4 |
| Bot, 50% speed | 0 of 4 |
| Does nothing | 0 of 4 (fence gives in wave 2–3) |

The bot evolves its turrets Gatling (left), Cannon (centre), Frost (right) and heals when it is low
outside, and picks Bomb when the field is crowded, Supply when the turrets are low, Rapid otherwise.

The bot sees the whole map and never dodges; a person only sees the camera's window, so the bot
runs a little easier than a person at the same pace. The bot (and the guide arrow) fights a close
chaser if it has shots and otherwise climbs back over the fence, where it can't follow.

## Code layout

- `main.gd` (node `Game`): all rules and the simulation, plus the HUD drawn in screen space.
- `view3d.gd` (node `View`): the 3D view. It reads the game state every frame, pools a node per
  entity by `uid`, and draws the labels over the world (costs, ammo, HP, ranges) on a 2D canvas.
