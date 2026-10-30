# The battle on aityx

Everything that happens in a battle is computed by aityx; the app only
draws the frames it returns.

## The world model

[assets/models/world.json](../roborules_app/assets/models/world.json), an
asset of the app, written by
[tool/build_world.py](../roborules_app/tool/build_world.py). Its types:
`Bot` (`id`, `x`, `y`, `heading`, `v`, `gun`, `energy`, `heat`, `alive`,
`rule`, `hit`, `damage`, `fired`, `died`), `Bullet` (`owner`, `x`, `y`,
`heading`, `power`), `World` (`tick`, `bots`, `bullets`), `Sense` (the 12
sensors) and `Act` (`drive`, `turn`, `gun`, `fire`, `rule`). Its inputs are
`world`, the battlefield to play from, and `turns`, 1 to 50. Its decision,
`frames`, is the world after each turn: `run(step(world), turns)`.

Each turn (`step`):

1. **Sensing** (`sense`, `sense_with`): the nearest living enemy's distance
   and bearings from the body and the gun (compass degrees, -180 to 180),
   whether it's within 10° of the gun, energies, a wall within 80 px
   ahead, the distance to the nearest wall, the gun ready (heat 0), being
   hit last turn, speed, enemies left.
2. **Deciding** (`brain_of`): each robot's own rules, `brain_r1`,
   `brain_r2`..., added per battle by the app
   ([lib/aityx/battle.dart](../roborules_app/lib/aityx/battle.dart)) from each robot's
   model, with a `rule` output: the number of the row that fired.
3. **Moving** (`move`, `place`, `walled`), as Robocode does: speed +1 a turn
   ahead (to 8), braking 2; turning at most 10 − 0.75·|v| degrees; the gun
   20° a turn; firing power p (0.1 to 3) when the gun is cool, costing p
   energy and heating the gun by 1 + p/5 (cooling 0.1 a turn); a wall stops
   the robot 18 px from it and costs |v|/2 − 1.
4. **Bullets** (`fly`, `spawn`): 20 − 3p px a turn from the gun's tip; a
   bullet within 18 px of another robot hits it for 4p + 2·max(0, p − 1),
   and gives its shooter 3p energy; it leaves the battlefield otherwise.
5. **Settling** (`resolve`, `settle`, `finish`): damage, gains, rams (two
   robots closer than 36 px stay put, stop, and lose 0.6 each), losses (0
   energy, `died` set to the turn), each robot's bullet damage dealt.

The battlefield is 800 × 600 px; robots start 120 px apart, 60 px from the
walls, facing anywhere, with a hot gun (heat 3) as in Robocode.

## FEEL, the hard parts

aityx's expressions are DMN FEEL, without trigonometry: `sin_r` is a Taylor
series (reduced to 0..π/2), `atan_r` a rational approximation good to 0.1°,
and `atan2_r` and `angle_to` build compass bearings from them. `sum` of an
empty list is null in FEEL, so `total` returns 0 for none. A field in a
context literal sees the fields before it, so functions name their
parameters apart from the fields they build (`nx`, `ny`, `nv` in `walled`).
Functions have no local variables, so steps pass computed values down to
the next function.

## The call

The app calls aityx itself ([AityxBattleApi](../roborules_app/lib/battle/api.dart),
on the shared [aityx_web](../../packages/aityx_web) package's
`AityxClient`). For a batch of turns it takes the robots (2 to 10 robot
models, in order: r1, r2...), the world (its bots' ids r1, r2... in the
same order) and the turns (1 to 50), checks the robots (known sensors, the
four commands, each command's values, a fire power 0 to 3) before calling
aityx, builds the battle's model and sends one call to aityx's
`/v1/systemone`, with a 90 s deadline. It reads the frames, and keeps the
call (the request's body and aityx's answer, never the headers, which
carry the key) for the [viewer](window.md), unless aityx's answer holds
the user's key: then the call isn't kept. A failed call says why:
"aityx is not set up: set your key on the index page" (no key; nothing is
sent), "aityx rejected the key" (401, 403), "aityx did not answer" (no
answer, or not in time), or "aityx answered HTTP n: …" with aityx's
`detail` and `errors`, its reasons for a model it can't run; "the battle
failed: …" for a decision error.

The app asks for 20 turns a call and fetches the next batch while it
shows this one; a round ends with one robot left, or after 1,500 turns.
Each battle has a number, and a reply that comes back after a Restart or
Stop belongs to an earlier one and is dropped.

### Verified

`bash scripts/model-test.sh` plays scripted battles on aityx: a power-3
bullet does 16 and gives its shooter 9; a robot dies on the turn it reaches
0, with `died` set; a wall stops a robot and costs 3 at speed 8; a ram
stops both robots where they were, 0.6 each; turning is 10° standing and 4°
at full speed; speed climbs by 1 to 8 and brakes by 2. aityx plays about 40
turns a second for two robots and 12 for four.

## Known limitations

- No radar scanning: robots always know the nearest enemy.
- Turns come in batches of 20; a rules change applies from the next batch.
