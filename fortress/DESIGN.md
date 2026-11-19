# Fortress — gameplay design (prototype)

A one-screen, portrait defense-and-build game. You are a worker **outside** your fortress wall.
Monsters march straight down three lanes toward the wall. You gather materials in the field,
carry them to build pads, turn wood into ammo, and keep the fixed turrets loaded. Every wave you
survive, the fortress grows.

Everything is drawn with basic shapes until the gameplay is right.

## The one-sentence loop

**Gather → carry → build or craft → load turrets → monsters drop scrap → gather again.**

## Controls

- Drag anywhere to move (a virtual joystick appears under your thumb). WASD or arrows on desktop.
- There are no buttons in play. Everything happens by **standing near things**:
  - next to a tree or rock: you harvest it, one item at a time, onto the stack on your back;
  - on a build pad: the materials it still needs fly off your stack into it;
  - at the ammo machine: your wood goes in; at its output pile: ammo boxes come onto your stack;
  - next to a turret: your ammo boxes load into it;
  - over scrap on the ground: you pick it up.
- A small arrow next to you always points at the most useful thing to do next.

## Materials

| Item | Shape | Where it comes from | What it is for |
|---|---|---|---|
| Wood | brown square | Trees on the left edge (5 per tree, regrow in 7 s) | Ammo, turrets, backpack, woodcutter |
| Stone | grey square | Rocks on the right edge (5 per rock, regrow in 7 s) | Turrets, gate upgrade, rapid fire, **gate repair** |
| Scrap | blue square | Dropped by monsters when they die (1, or 4 from a brute); fades after 30 s | Helpers and upgrades |
| Ammo box | yellow square | The ammo machine: 1 wood → 2 boxes (1 s per wood) | Loaded into turrets: 1 box = 10 shots |

You carry one mixed stack, **10 items** to start. You only pick up what something currently
needs, so your stack never fills with junk.

## The fortress (build pads, in unlock order)

Two pads are open at a time. Finish one and the next appears, so there is always a choice of two.

| # | Pad | Cost | Effect |
|---|---|---|---|
| — | Centre turret | already built, 2 boxes loaded | Covers the middle lane |
| 1 | Ammo machine | 8 wood | Turns wood into ammo boxes |
| 2 | Left turret | 5 wood, 5 stone | Covers the left lane |
| 3 | Right turret | 5 wood, 5 stone | Covers the right lane |
| 4 | Gate +5 | 10 stone | Gate takes 5 more monsters |
| 5 | Ammo runner (helper) | 8 scrap | Carries boxes from the machine to the emptiest turret |
| 6 | Rapid fire | 10 scrap, 6 stone | All turrets fire 1.8× faster |
| 7 | Bigger pack | 10 wood | Carry 18 items |
| 8 | Woodcutter (helper) | 12 scrap, 6 wood | Chops trees and feeds the ammo machine |

Built things also appear as houses inside the wall, so the fortress visibly grows.

## Turrets

- Fixed in place, one per lane. They never move and **monsters never attack them**.
- Fire at the nearest monster within 230 px (about one lane each side), 2 shots/s, 1 damage per shot.
- Hold up to 5 boxes (50 shots). An empty turret shows a pulsing red ring: go and feed it.

## Monsters

They walk straight down their lane and ignore you and the turrets.

| Monster | Shape | HP | Speed | Gate damage | Scrap | From wave |
|---|---|---:|---:|---:|---:|---:|
| Grunt | red circle | 3 | slow | 1 | 1 | 1 |
| Runner | orange triangle | 2 | fast | 1 | 1 | 3 |
| Brute | dark red square | 14 | very slow | 3 | 4 | 5 |

## The gate

- Reaching the wall does not lose the game. Each monster that gets there **cracks the gate**
  by its gate damage. The gate starts able to take **12** cracks (shown as pips in the top bar).
- When the cracks reach the limit, the gate breaks and the run is over.
- Repair: when the gate is cracked, a repair pad appears in front of it. **3 stone mends 1 crack.**

## Waves

- 10 waves. The first comes after 30 s, giving you time to build the ammo machine.
- Monsters get 8% more HP every wave. Wave *n* brings 3 + 2n grunts, runners from wave 3, brutes from wave 5, one every 1.1 s, each
  in a random lane.
- A 16 s break follows each wave. The top bar counts down to the next one.
- Survive wave 10 and the fortress holds. That is the win for this prototype.

## Why it should feel good

- There is always one obvious next job (the arrow), but the two open pads, the gate repair and
  hungry turrets compete for your time. That tension is the game.
- Every action gives instant feedback: items fly from you into what you are building.
- Kills feed the economy (scrap), so defending well makes building faster.
- Helpers take over the boring trips, so the game shifts from running errands to managing.

## Out of scope for the first prototype

Art, sound, more lanes, upgrades per turret, multiple maps, saving progress.

## Balance check

`godot --headless --path fortress -- sim=bot pace=1` runs the built-in bot (the same logic as the
guide arrow) through all 10 waves and prints a log. `pace` slows it down to stand in for a human;
`sim=idle` never moves. Current results:

| Player | Result |
|---|---|
| Bot, full speed | Wins, gate untouched, builds all 8 pads |
| Bot, 70% speed | Wins with 3 of 12 cracks left |
| Bot, 50% speed | Gate breaks in wave 8 |
| Does nothing | Gate breaks in wave 4 |

The levers that mattered most: turret range (one turret covering every lane made building
pointless), boxes per wood (ammo used to eat all the wood) and per-wave HP growth.
