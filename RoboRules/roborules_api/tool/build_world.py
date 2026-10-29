"""Writes models/world.json, the battle's world model: everything but the
robots' brains, which the API adds per battle (lib/battle.dart).

The model is in aityx's format (DMN FEEL underneath). Its expressions have
no trigonometry, so sine, cosine and atan2 are functions built from a series
and a rational approximation. A field in a context literal can see the
fields before it, so functions name their parameters apart from the fields
they build (nx, ny, nv in walled).

Usage, from roborules_api/:  python3 tool/build_world.py models/world.json
Then run bash ../scripts/model-test.sh, which plays scripted battles on
aityx and checks the physics.
"""
import json
import sys


SENSES = ["enemy_distance", "enemy_bearing", "gun_bearing", "enemy_in_sight",
          "my_energy", "enemy_energy", "near_wall", "wall_distance",
          "gun_ready", "was_hit", "speed", "enemies_left"]

F = {}
def fn(name, params, returns, body):
    F[name] = {"params": params, "returns": returns, "body": body}

PI = "3.141592653589793"
fn("rad", {"d": "number"}, "number", f"d * {PI} / 180")
fn("sin_r", {"r": "number"}, "number",
   f"if r > 1.5707963267948966 then sin_r({PI} - r) else r - r**3/6 + r**5/120 - r**7/5040 + r**9/362880 - r**11/39916800")
fn("sin_d", {"d": "number"}, "number",
   "if modulo(d, 360) > 180 then -sin_r(rad(modulo(d, 360) - 180)) else sin_r(rad(modulo(d, 360)))")
fn("cos_d", {"d": "number"}, "number", "sin_d(d + 90)")
# atan for |z| <= 1, error under 0.1 degrees
fn("atan_r", {"z": "number"}, "number", f"{PI} / 4 * z - z * (abs(z) - 1) * (0.2447 + 0.0663 * abs(z))")
fn("atan2_r", {"a": "number", "b": "number"}, "number",
   f"if a = 0 and b = 0 then 0 "
   f"else if abs(b) >= abs(a) then (if b > 0 then atan_r(a / b) else if a >= 0 then atan_r(a / b) + {PI} else atan_r(a / b) - {PI}) "
   f"else (if a > 0 then {PI} / 2 - atan_r(b / a) else -{PI} / 2 - atan_r(b / a))")
# Compass degrees (0 up, clockwise) of the vector (dx, dy), screen y down.
fn("angle_to", {"dx": "number", "dy": "number"}, "number", f"modulo(atan2_r(dx, -dy) * 180 / {PI}, 360)")
fn("norm180", {"d": "number"}, "number", "modulo(d + 180, 360) - 180")
fn("clamp", {"v": "number", "lo": "number", "hi": "number"}, "number", "min(max(v, lo), hi)")
fn("dist", {"x1": "number", "y1": "number", "x2": "number", "y2": "number"}, "number", "sqrt((x2 - x1)**2 + (y2 - y1)**2)")
fn("total", {"xs": ["number"]}, "number", "if count(xs) = 0 then 0 else sum(xs)")
fn("arena_w", {}, "number", "800")
fn("arena_h", {}, "number", "600")

# Robocode's numbers
fn("bullet_speed", {"p": "number"}, "number", "20 - 3 * p")
fn("bullet_damage", {"p": "number"}, "number", "4 * p + max(0, 2 * (p - 1))")
fn("max_turn", {"v": "number"}, "number", "10 - 0.75 * abs(v)")
fn("next_speed", {"v": "number", "drive": "string"}, "number",
   "if drive = \"ahead\" then (if v < 0 then min(v + 2, 0) else min(v + 1, 8)) "
   "else if drive = \"back\" then (if v > 0 then max(v - 2, 0) else max(v - 1, -8)) "
   "else (if v > 0 then max(v - 2, 0) else min(v + 2, 0))")
fn("perp", {"bearing": "number"}, "number",
   "if abs(norm180(bearing - 90)) < abs(norm180(bearing + 90)) then norm180(bearing - 90) else norm180(bearing + 90)")
fn("turn_by", {"turn": "string", "s": "Sense", "m": "number"}, "number",
   "if turn = \"left\" then -m else if turn = \"right\" then m "
   "else if turn = \"toward_enemy\" then clamp(s.enemy_bearing, -m, m) "
   "else if turn = \"away_from_enemy\" then clamp(norm180(s.enemy_bearing + 180), -m, m) "
   "else if turn = \"perpendicular\" then clamp(perp(s.enemy_bearing), -m, m) else 0")
fn("gun_by", {"gun": "string", "s": "Sense"}, "number",
   "if gun = \"aim\" then clamp(s.gun_bearing, -20, 20) else if gun = \"sweep_left\" then -20 "
   "else if gun = \"sweep_right\" then 20 else 0")

# Sensing
fn("enemies", {"b": "Bot", "bots": ["Bot"]}, ["Bot"], "bots[item.alive and item.id != b.id]")
fn("nearest", {"b": "Bot", "es": ["Bot"]}, "Bot",
   "if count(es) = 0 then null else es[dist(b.x, b.y, item.x, item.y) = min(for e in es return dist(b.x, b.y, e.x, e.y))][1]")
fn("sense", {"b": "Bot", "bots": ["Bot"]}, "Sense", "sense_with(b, nearest(b, enemies(b, bots)), count(enemies(b, bots)))")
fn("sense_with", {"b": "Bot", "e": "Bot", "n": "number"}, "Sense",
   "{id: b.id, "
   "enemy_distance: if e = null then 9999 else decimal(dist(b.x, b.y, e.x, e.y), 1), "
   "enemy_bearing: if e = null then 0 else decimal(norm180(angle_to(e.x - b.x, e.y - b.y) - b.heading), 1), "
   "gun_bearing: if e = null then 0 else decimal(norm180(angle_to(e.x - b.x, e.y - b.y) - b.gun), 1), "
   "enemy_in_sight: if e = null then false else abs(norm180(angle_to(e.x - b.x, e.y - b.y) - b.gun)) <= 10, "
   "my_energy: decimal(b.energy, 1), "
   "enemy_energy: if e = null then 0 else decimal(e.energy, 1), "
   "near_wall: b.x + 80 * sin_d(b.heading) < 18 or b.x + 80 * sin_d(b.heading) > arena_w() - 18 "
   "or b.y - 80 * cos_d(b.heading) < 18 or b.y - 80 * cos_d(b.heading) > arena_h() - 18, "
   "wall_distance: decimal(min(b.x, b.y, arena_w() - b.x, arena_h() - b.y) - 18, 1), "
   "gun_ready: b.heat <= 0, was_hit: b.hit, speed: b.v, enemies_left: n}")

# Moving one robot by its action
fn("advance", {"b": "Bot", "s": "Sense"}, "Bot", "move(b, s, brain_of(s))")
fn("move", {"b": "Bot", "s": "Sense", "a": "Act"}, "Bot",
   "place(b, a, modulo(b.heading + turn_by(a.turn, s, max_turn(b.v)), 360), next_speed(b.v, a.drive), "
   "modulo(b.gun + gun_by(a.gun, s), 360), a.fire >= 0.1 and b.heat <= 0 and b.energy > a.fire)")
fn("place", {"b": "Bot", "a": "Act", "h": "number", "v": "number", "g": "number", "fires": "boolean"}, "Bot",
   "walled(b, a, h, v, g, fires, b.x + v * sin_d(h), b.y - v * cos_d(h))")
fn("walled", {"b": "Bot", "a": "Act", "h": "number", "nv": "number", "g": "number", "fires": "boolean", "nx": "number", "ny": "number"}, "Bot",
   "{id: b.id, x: clamp(nx, 18, arena_w() - 18), y: clamp(ny, 18, arena_h() - 18), heading: h, "
   "v: if nx < 18 or nx > arena_w() - 18 or ny < 18 or ny > arena_h() - 18 then 0 else nv, "
   "gun: g, "
   "energy: b.energy - (if fires then clamp(a.fire, 0.1, 3) else 0) "
   "- (if nx < 18 or nx > arena_w() - 18 or ny < 18 or ny > arena_h() - 18 then max(0, abs(nv) * 0.5 - 1) else 0), "
   "heat: if fires then 1 + clamp(a.fire, 0.1, 3) / 5 else max(0, b.heat - 0.1), "
   "alive: b.alive, rule: a.rule, hit: false, damage: b.damage, "
   "fired: if fires then clamp(a.fire, 0.1, 3) else 0, died: b.died}")
fn("resting", {"b": "Bot"}, "Bot",
   "{id: b.id, x: b.x, y: b.y, heading: b.heading, v: 0, gun: b.gun, energy: b.energy, heat: b.heat, "
   "alive: false, rule: 0, hit: false, damage: b.damage, fired: 0, died: b.died}")

# Bullets
fn("fly", {"u": "Bullet"}, "Bullet",
   "{owner: u.owner, x: decimal(u.x + bullet_speed(u.power) * sin_d(u.heading), 2), "
   "y: decimal(u.y - bullet_speed(u.power) * cos_d(u.heading), 2), heading: u.heading, power: u.power}")
fn("hits", {"u": "Bullet", "b": "Bot"}, "boolean", "b.alive and b.id != u.owner and dist(u.x, u.y, b.x, b.y) < 18")
fn("hits_any", {"u": "Bullet", "bots": ["Bot"]}, "boolean", "count(bots[hits(u, item)]) > 0")
fn("out", {"u": "Bullet"}, "boolean", "u.x < 0 or u.x > arena_w() or u.y < 0 or u.y > arena_h()")
fn("spawn", {"b": "Bot"}, "Bullet",
   "{owner: b.id, x: decimal(b.x + 20 * sin_d(b.gun), 2), y: decimal(b.y - 20 * cos_d(b.gun), 2), heading: b.gun, power: b.fired}")

# One turn
fn("step", {"w": "World"}, "World",
   "resolve(w, for b in w.bots return if b.alive then advance(b, sense(b, w.bots)) else resting(b), "
   "for u in w.bullets return fly(u))")
fn("resolve", {"w": "World", "moved": ["Bot"], "flown": ["Bullet"]}, "World",
   "{tick: w.tick + 1, "
   "bots: for b in moved return settle(b, w.bots[item.id = b.id][1], moved, flown, w.tick + 1), "
   "bullets: concatenate(flown[not(out(item)) and not(hits_any(item, moved))], for b in moved[item.fired > 0] return spawn(b))}")
fn("settle", {"b": "Bot", "old": "Bot", "moved": ["Bot"], "flown": ["Bullet"], "tick": "number"}, "Bot",
   "finish(b, old, tick, total(for u in flown return if hits(u, b) then bullet_damage(u.power) else 0), "
   "total(for u in flown return if u.owner = b.id and hits_any(u, moved) then bullet_damage(u.power) else 0), "
   "total(for u in flown return if u.owner = b.id and hits_any(u, moved) then 3 * u.power else 0), "
   "b.alive and count(moved[item.alive and item.id != b.id and dist(item.x, item.y, b.x, b.y) < 36]) > 0)")
fn("finish", {"b": "Bot", "old": "Bot", "tick": "number", "taken": "number", "dealt": "number", "gain": "number", "rammed": "boolean"}, "Bot",
   "{id: b.id, x: decimal(if rammed then old.x else b.x, 2), y: decimal(if rammed then old.y else b.y, 2), "
   "heading: decimal(b.heading, 2), v: if rammed then 0 else b.v, gun: decimal(b.gun, 2), "
   "energy: decimal(max(0, b.energy - taken + gain - (if rammed then 0.6 else 0)), 2), "
   "heat: decimal(b.heat, 2), alive: b.alive and b.energy - taken + gain - (if rammed then 0.6 else 0) > 0, "
   "rule: b.rule, hit: taken > 0, damage: decimal(b.damage + dealt, 2), fired: b.fired, "
   "died: if b.alive and b.energy - taken + gain - (if rammed then 0.6 else 0) <= 0 then tick else b.died}")
fn("run", {"w": "World", "k": "number"}, ["World"],
   "if k <= 0 then [] else concatenate([w], run(step(w), k - 1))")

TYPES = {
    "Bot": {"id": "string", "x": "number", "y": "number", "heading": "number", "v": "number",
            "gun": "number", "energy": "number", "heat": "number", "alive": "boolean",
            "rule": "number", "hit": "boolean", "damage": "number", "fired": "number", "died": "number"},
    "Bullet": {"owner": "string", "x": "number", "y": "number", "heading": "number", "power": "number"},
    "World": {"tick": "number", "bots": ["Bot"], "bullets": ["Bullet"]},
    "Sense": {"id": "string", "enemy_distance": "number", "enemy_bearing": "number", "gun_bearing": "number",
              "enemy_in_sight": "boolean", "my_energy": "number", "enemy_energy": "number", "near_wall": "boolean",
              "wall_distance": "number", "gun_ready": "boolean", "was_hit": "boolean", "speed": "number",
              "enemies_left": "number"},
    "Act": {"drive": "ahead|back|stop", "turn": "left|right|none|toward_enemy|away_from_enemy|perpendicular",
            "gun": "aim|sweep_left|sweep_right|hold", "fire": "number", "rule": "number"},
}

# brain_of and brain_r1, brain_r2... are added per battle by the API.

world = {
    "name": "RoboRules · The battle",
    "types": TYPES,
    "inputs": {
        "world": {"type": "World", "desc": "The battlefield now: every robot and bullet"},
        "turns": {"type": "number [1..50]", "desc": "How many turns to play in this call"},
    },
    "functions": F,
    "decisions": {"frames": {"type": ["World"], "desc": "The world after each turn", "expr": "run(step(world), turns)"}},
}

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "models/world.json"
    with open(out, "w") as f:
        json.dump(world, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"wrote {out}: {len(F)} functions")
