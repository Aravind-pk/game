# Fortress — gameplay design (prototype)

A one-screen, portrait defense-and-build game. You live behind a **fence with one small door**.
Outside are the trees, the rocks and three monster lanes; inside is everything you build. Monsters
march straight down the lanes and wait at the fence. Step out to gather and they come for you.

Everything is drawn with basic shapes until the gameplay is right.

## The loop

**Go out → gather (and fight) → come back in → build or craft → feed the turrets → repeat.**

## Controls

- Drag anywhere to move (a virtual joystick appears under your thumb). WASD or arrows on desktop.
- No buttons. Things happen by **standing near them**:
  - next to a tree or rock (outside): you harvest one item at a time onto the stack on your back;
  - on a build pad: the materials it still needs fly off your stack into it;
  - at the ammo machine: your wood goes in; at its output pile, boxes come out to you;
  - next to a turret (from inside): your ammo boxes load into it;
  - over monster coins on the ground: they go straight into your wallet (no stack space).
- Your own gun fires by itself at the nearest monster in close range (130 px) while your bag has shots.
- A small arrow next to you points at the most useful thing to do, routed through the door, and it
  won't send you out while monsters are gathered at the door.

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

- **Fence** across the screen with a **door** the worker (and the woodcutter) can walk through.
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
| 8 | Woodcutter | 5 coins, 6 wood | Helper: walks out through the door, chops trees, feeds the machine. Monsters ignore it |

## Powers

The **power meter** in the top-right corner fills by one for every monster coin you pick up (12 to
charge; coins are not spent). When it is full it pulses: **tap it** and four powers open below it.
Tap one:

| Power | Effect |
|---|---|
| Rapid | All turrets fire twice as fast for 12 s |
| Freeze | Every monster moves at 35% speed for 8 s |
| Bomb | 8 damage to every monster on the field |
| Supply | +2 boxes in every turret and a full ammo bag |

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

They walk straight down their lane, stop at the fence and **wait there** (they don't die on it).
Turrets and your gun can still shoot them while they wait.

| Monster | Shape | HP | Speed | Notices you within | Hit | Scrap | From wave |
|---|---|---:|---:|---:|---:|---:|---:|
| Grunt | red circle | 3 | slow | 90 px | 1 heart | 1 coin | 1 |
| Runner | orange triangle | 2 | fast | 130 px | 1 heart | 1 | 3 |
| Brute | dark red square | 14 | very slow | 70 px | 2 hearts | 4 | 5 |

A monster that notices you (red ring) chases you until you are more than 260 px away. Waiting
monsters keep the doorway clear but will chase you if you step out next to them. Monsters get 16%
more HP every wave.

## How you lose

1. **The fence gives way**: the number of monsters waiting at it reaches its capacity (10, 14 with
   the upgrade). Shown as the FENCE pips in the top bar.
2. **You are overrun**: you lose all 6 hearts to touches. Hearts come back while you are inside
   (one every 4 s).
3. **A monster follows you in**: a chasing monster gets through the door.

Survive wave 12 with the field cleared and the fortress holds.

## Waves

12 waves. The first comes after 30 s; 16 s breaks between waves. Wave *n* brings 4 + 3n grunts,
runners from wave 3 and brutes from wave 5, one every 1.1 s in a random lane.

## The tension this creates

- Everything you need is outside, and outside is where the monsters are. Each trip is a choice:
  how full is your bag, are monsters waiting by the door, is the scrap in a lane worth the risk?
- Ammo has to be shuttled by hand until launchers take over, and launchers cost coins, which
  means going into the lanes. Coins also charge the power-up: save it for the heavy waves.
- A chaser on your tail means you can't go home: shoot it, or lead it away until it gives up.
- Monsters piling up at the fence are a slow clock: feed the turrets or the fence gives.

## Balance check

`godot --headless --path fortress -- sim=bot pace=1 seed=1` runs the built-in bot (the same logic
as the guide arrow) and prints a log. `pace` slows it down to stand in for a human; `sim=idle`
never moves; `seed` changes the lanes monsters spawn in. Four seeds each:

| Player | Wins |
|---|---|
| Bot, full speed | 3 of 4 |
| Bot, 70% speed | 2 of 4 |
| Bot, 50% speed | 1 of 4 |
| Does nothing | 0 of 4 (fence gives in wave 2–3) |

The bot evolves its turrets Gatling (left), Cannon (centre), Frost (right) and picks Bomb when
the field is crowded, Supply when the turrets are low, Rapid otherwise.

The bot never dodges, so a person should do better than its pace suggests. The bot (and the guide
arrow) fights a close chaser if it has shots and otherwise leads it away before heading for the
door, so it never loses by being followed in.
