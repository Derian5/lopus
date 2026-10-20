"""Generates the 'CBO *' combat effects for Can Be Only One Hero as Arcaidia Effector
library files (library/CBO <Name>.json). Sparse format: Model.hydrate fills defaults."""
import json, os, sys

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'library')


def K(*pairs, m='ease'):
    return {"keys": [{"t": t, "v": v, "i": {"m": m}, "o": {"m": m}} for t, v in pairs]}


def C(*pts):
    return {"pts": [{"t": t, "v": v} for t, v in pts]}


def G(*stops):
    return {"stops": [{"t": t, "c": c} for t, c in stops]}


WHITE = G((0, [255, 255, 255]), (1, [255, 255, 255]))
FADE = C((0, 1), (0.6, 0.8), (1, 0))
FADE_LATE = C((0, 0), (0.12, 1), (0.7, 0.75), (1, 0))


def sprite(lid, name, shape, size, color, opacity, scale, x=0, y=0, aspect=1.0, rot=0, glow=0.0,
           blend='add', start=0.0, end=None, p=None, squash=0, glowSize=1.6, glowBlur=0.15):
    layer = {"id": lid, "name": name, "type": "sprite", "start": start, "blend": blend, "opacity": opacity,
             "sp": {"sprite": {"kind": "shape", "id": shape, "p": p or {}}, "size": size, "x": x, "y": y,
                    "scale": scale, "aspect": aspect, "rot": rot, "color": color, "glow": glow,
                    "glowSize": glowSize, "glowBlur": glowBlur, "squash": squash}}
    if end is not None:
        layer["end"] = end
    return layer


def emitter(lid, name, em, pt, blend='add', start=0.0, end=None, glowL=0, glowLR=24):
    em = dict(em)
    em.setdefault("bursts", [])
    layer = {"id": lid, "name": name, "type": "emitter", "start": start, "blend": blend, "em": em, "pt": pt}
    if end is not None:
        layer["end"] = end
    if glowL:
        layer["glowL"] = glowL
        layer["glowLR"] = glowLR
    return layer


def effect(slug, name, w, h, dur, cols, rows, frames, cw, ch, layers, t0=0.0, t1=-1, cam=0):
    doc = {"v": 2, "id": "fx_cbo_" + slug, "name": name, "comp": {"w": w, "h": h, "dur": dur, "fps": 60},
           "cam": {"comp": cam},
           "exp": {"cols": cols, "rows": rows, "frames": frames, "cellW": cw, "cellH": ch, "t0": t0, "t1": t1,
                   "mode": "rgba", "thr": 0, "ss": 2},
           "layers": layers}
    return {"app": "arcadia-effects", "v": 2, "doc": doc, "tex": {}}


EFFECTS = {}


def reg(file_name, data):
    EFFECTS[file_name] = data


# ---------------------------------------------------------------- projectiles
# Loops of P seconds in a 256x128 composition (exported to 192x96 cells); the shot flies
# toward +X and its head sits at x = +64 (the game shifts the sprite by -48 px).
P = 0.4
H = 64


def pulse(a, b, period=P):
    return K((0, a), (period * 0.25, b), (period * 0.5, a), (period * 0.75, b), (period, a))


def spin(deg, period=P):
    return K((0, 0), (period, deg), m='lin')


def stream(lid, name, grad, size, life, speed=230, rate=80, sprite_id='soft', glow=0.4, spread=10, stretch=0,
           align=False, x=H - 10, y=0, seed=3, blend='add', turb=0, gravY=0, sizeOL=None, opacityOL=None, drag=1.5,
           shape='point', sy=0):
    em = {"x": x, "y": y, "dir": "dir", "angle": 180, "spread": spread, "speed": speed, "speedRnd": 0.3, "rate": rate,
          "seed": seed}
    if shape != 'point':
        em.update({"shape": shape, "sx": sy, "sy": sy})
    return emitter(lid, name, em,
                   {"life": life, "lifeRnd": 0.3, "sprite": {"kind": "shape", "id": sprite_id, "p": {}}, "size": size,
                    "sizeRnd": 0.35, "sizeOL": sizeOL or C((0, 1), (1, 0.15)),
                    "opacityOL": opacityOL or C((0, 0.9), (0.4, 0.6), (1, 0)), "grad": grad, "spin": 0,
                    "rotRnd": 1, "drag": drag, "glow": glow, "alignVel": align, "stretch": stretch,
                    "turbAmp": turb, "turbFreq": 3, "gravY": gravY},
                   blend=blend)


def projectile(slug, name, layers):
    # Particles need ~1 s to fill the tail, so the atlas samples one period after that.
    reg(name, effect(slug, name, 256, 128, 1.6, 4, 2, 8, 192, 96, layers, t0=1.0, t1=1.0 + P))


# Archer: a real arrow. Wooden shaft, steel head, red fletching, a faint motion streak.
projectile("arrow", "CBO Arrow", [
    sprite("lr_arrow_glint", "Head Glint", "spark", 22, [255, 250, 235], pulse(0.9, 0.5), pulse(0.9, 1.15), x=H + 2,
           glow=0.3),
    sprite("lr_arrow_head", "Arrow Head", "poly", 22, [178, 184, 190], 1, 1, x=H - 6, aspect=0.62, rot=90,
           blend='normal', p={"n": 3}),
    sprite("lr_arrow_shaft", "Shaft", "square", 6, [118, 84, 52], 1, 1, x=H - 62, aspect=27, blend='normal'),
    sprite("lr_arrow_shine", "Shaft Shine", "square", 3, [214, 180, 130], 0.8, 1, x=H - 62, y=-1, aspect=50,
           blend='normal'),
    sprite("lr_arrow_fletch_a", "Fletching A", "shard", 20, [190, 50, 40], 1, 1, x=H - 116, y=-4, aspect=1.5, rot=-70,
           blend='normal', p={"var": 2}),
    sprite("lr_arrow_fletch_b", "Fletching B", "shard", 20, [150, 36, 30], 1, 1, x=H - 116, y=4, aspect=1.5, rot=-110,
           blend='normal', p={"var": 3}),
    sprite("lr_arrow_blur", "Motion Blur", "streak", 150, [255, 236, 200], 0.15, 1, x=H - 80, glow=0.1),
])

# Envy: a crossbow bolt (not magic): dark short shaft, heavy steel broadhead, green
# poison smeared on the head and dripping from it.
projectile("venom", "CBO Venom Bolt", [
    sprite("lr_venom_glint", "Edge Glint", "spark", 18, [235, 255, 220], pulse(1, 0.55), pulse(0.9, 1.2), x=H + 4,
           glow=0.35),
    sprite("lr_venom_poison", "Poison Sheen", "soft", 34, [70, 230, 60], pulse(0.45, 0.3), pulse(0.95, 1.1), x=H - 6,
           aspect=1.6),
    sprite("lr_venom_head", "Broadhead", "poly", 30, [150, 160, 156], 1, 1, x=H - 8, aspect=0.85, rot=90,
           blend='normal', p={"n": 3}),
    sprite("lr_venom_edge", "Poisoned Edge", "poly", 20, [120, 220, 80], 0.75, 1, x=H - 6, aspect=0.6, rot=90,
           blend='normal', p={"n": 3}),
    sprite("lr_venom_shaft", "Bolt Shaft", "square", 9, [84, 64, 46], 1, 1, x=H - 52, aspect=13, blend='normal'),
    sprite("lr_venom_band", "Poison Band", "square", 10, [110, 200, 60], 0.9, 1, x=H - 28, aspect=1.6,
           blend='normal'),
    sprite("lr_venom_vane_a", "Vane A", "shard", 18, [40, 70, 36], 1, 1, x=H - 96, y=-4, aspect=1.4, rot=-70,
           blend='normal', p={"var": 2}),
    sprite("lr_venom_vane_b", "Vane B", "shard", 18, [30, 54, 28], 1, 1, x=H - 96, y=4, aspect=1.4, rot=-110,
           blend='normal', p={"var": 3}),
    stream("lr_venom_drops", "Venom Drops", G((0, [200, 255, 120]), (1, [40, 150, 40])), 10, 0.45, speed=90,
           rate=40, sprite_id='dot', glow=0.35, spread=40, x=H - 8, gravY=320, seed=9),
    stream("lr_venom_mist", "Venom Mist", G((0, [120, 230, 90]), (1, [30, 110, 40])), 26, 0.35, speed=160,
           rate=40, glow=0.1, spread=12, x=H - 10, seed=10,
           opacityOL=C((0, 0.35), (0.5, 0.2), (1, 0))),
    sprite("lr_venom_blur", "Motion Blur", "streak", 140, [200, 255, 190], 0.25, 1, x=H - 70),
])

# Priest: a radiant holy star with a long golden comet tail.
projectile("holy", "CBO Holy Bolt", [
    sprite("lr_holy_core", "Core", "dot", 22, [255, 255, 245], 1, pulse(1, 1.15), x=H, glow=0.8),
    sprite("lr_holy_star", "Star", "star", 70, [255, 225, 130], 0.75, pulse(1, 1.12), x=H, rot=spin(90), glow=0.35,
           p={"n": 8, "inr": 0.25}),
    sprite("lr_holy_cross", "Cross", "spark", 96, [255, 240, 200], pulse(0.6, 0.4), pulse(0.95, 1.1), x=H, glow=0.3),
    sprite("lr_holy_halo", "Halo", "soft", 110, [255, 190, 70], 0.38, pulse(0.92, 1.08), x=H - 4),
    sprite("lr_holy_bloom", "Bloom", "soft", 180, [255, 160, 50], 0.16, 1, x=H - 30, aspect=2.2),
    stream("lr_holy_sparks", "Sparks", G((0, [255, 252, 230]), (0.5, [255, 214, 110]), (1, [230, 140, 40])), 18,
           0.5, speed=200, rate=90, sprite_id='spark', glow=0.4, spread=26),
    stream("lr_holy_tail", "Comet Tail", G((0, [255, 236, 170]), (1, [210, 120, 30])), 44, 0.35, speed=200,
           rate=70, glow=0.15, spread=6, seed=5),
])

# Summoner / summoned shooter: a big ghostly flame with curling spirit motes.
projectile("wisp", "CBO Spirit Wisp", [
    sprite("lr_wisp_core", "Core", "dot", 20, [235, 255, 255], 1, pulse(1, 1.2), x=H, glow=0.9),
    sprite("lr_wisp_flame", "Spirit Flame", "flame", 120, [80, 220, 215], 0.85, pulse(1, 1.08), x=H - 26,
           aspect=1.8, rot=180, glow=0.5, p={"taper": 0.5, "var": 2}),
    sprite("lr_wisp_flame2", "Inner Flame", "flame", 80, [200, 255, 250], 0.45, pulse(1.05, 0.95), x=H - 16,
           aspect=1.7, rot=180, glow=0.3, p={"taper": 0.4, "var": 1}),
    sprite("lr_wisp_aura", "Aura", "soft", 160, [140, 80, 255], 0.35, pulse(0.95, 1.1), x=H - 30, aspect=2.0),
    stream("lr_wisp_motes", "Spirit Motes", G((0, [200, 255, 250]), (1, [150, 90, 255])), 11, 0.6, speed=170,
           rate=70, sprite_id='dot', glow=0.5, spread=40, turb=1100, seed=7, drag=1.0),
    stream("lr_wisp_ghost", "Ghost Trail", G((0, [120, 230, 230]), (1, [90, 60, 200])), 50, 0.45, speed=180,
           rate=50, glow=0.1, spread=10, seed=8, opacityOL=C((0, 0.5), (0.5, 0.3), (1, 0))),
])

# Pride: a long arcane lance with a spinning rune disc and a trail of stars.
projectile("arcane", "CBO Arcane Lance", [
    sprite("lr_arcane_head", "Crystal Head", "poly", 34, [235, 190, 255], 1, pulse(1, 1.15), x=H, aspect=1.5,
           rot=spin(120), glow=0.5, p={"n": 4}),
    sprite("lr_arcane_core", "White Core", "streak", 170, [255, 238, 255], 1, 1, x=H - 70, glow=0.45),
    sprite("lr_arcane_disc", "Rune Disc", "ring", 66, [210, 140, 255], 0.85, pulse(1, 1.1), x=H - 6, aspect=0.4,
           glow=0.4, p={"th": 0.12}),
    sprite("lr_arcane_disc2", "Rune Disc 2", "star", 60, [200, 120, 255], 0.55, 1, x=H - 6, aspect=0.4,
           rot=spin(180), glow=0.2, p={"n": 6, "inr": 0.7}),
    sprite("lr_arcane_aura", "Violet Aura", "soft", 150, [150, 60, 255], pulse(0.6, 0.45), pulse(0.95, 1.06),
           x=H - 30, aspect=2.4),
    sprite("lr_arcane_bloom", "Bloom", "soft", 210, [110, 40, 220], 0.18, 1, x=H - 60, aspect=2.6),
    stream("lr_arcane_stars", "Star Trail", G((0, [255, 225, 255]), (0.5, [200, 110, 255]), (1, [110, 40, 200])),
           16, 0.5, speed=230, rate=90, sprite_id='star', glow=0.5, spread=22, seed=11),
])

# Despair: a heavy orb of gloom: dark core, cold blue rim, a smoky tail.
projectile("gloom", "CBO Gloom Orb", [
    sprite("lr_gloom_glint", "Cold Glint", "dot", 16, [210, 225, 255], pulse(1, 0.6), 1, x=H + 6, glow=0.7),
    sprite("lr_gloom_rim", "Rim", "ring", 74, [120, 150, 255], 0.95, pulse(1, 1.08), x=H - 4, glow=0.7,
           p={"th": 0.16}),
    sprite("lr_gloom_rune", "Rune", "star", 60, [140, 160, 255], 0.5, 1, x=H - 4, rot=spin(-90), glow=0.2,
           p={"n": 5, "inr": 0.7}),
    sprite("lr_gloom_core", "Dark Core", "soft", 66, [26, 18, 60], 1, pulse(1, 1.06), x=H - 4, blend='normal'),
    stream("lr_gloom_smoke", "Gloom Smoke", G((0, [70, 60, 150]), (1, [20, 15, 40])), 46, 0.6, speed=180,
           rate=70, sprite_id='smoke', glow=0, spread=16, x=H - 20, seed=12, blend='normal',
           sizeOL=C((0, 0.6), (1, 1.4)), opacityOL=C((0, 0.85), (1, 0)), drag=2),
    stream("lr_gloom_wisps", "Blue Wisps", G((0, [180, 200, 255]), (1, [80, 90, 255])), 10, 0.5, speed=200,
           rate=50, sprite_id='dot', glow=0.5, spread=30, turb=700, seed=13),
    sprite("lr_gloom_aura", "Aura", "soft", 160, [80, 90, 255], 0.45, pulse(0.95, 1.08), x=H - 10),
])

# Troll hexer: a sickly green hex orb with a purple curse smoke trail.
projectile("hex", "CBO Hex Orb", [
    sprite("lr_hex_core", "Core", "dot", 18, [230, 255, 200], 1, pulse(1, 1.2), x=H, glow=0.5),
    sprite("lr_hex_rune", "Rune", "star", 60, [150, 240, 80], 0.95, 1, x=H, rot=spin(-90), blend='normal',
           p={"n": 5, "inr": 0.45}),
    sprite("lr_hex_glow", "Glow", "soft", 90, [140, 255, 70], 0.55, pulse(0.95, 1.1), x=H),
    stream("lr_hex_smoke", "Curse Smoke", G((0, [140, 60, 170]), (1, [50, 20, 60])), 44, 0.55, speed=170,
           rate=65, sprite_id='smoke', spread=16, x=H - 16, seed=14, blend='normal',
           sizeOL=C((0, 0.6), (1, 1.4)), opacityOL=C((0, 0.8), (1, 0)), drag=2),
    stream("lr_hex_sparks", "Hex Sparks", G((0, [210, 255, 140]), (1, [90, 200, 60])), 10, 0.45, speed=190,
           rate=50, sprite_id='spark', glow=0.4, spread=30, seed=15),
])

# Witch doctor: a roaring fireball with embers and smoke.
projectile("ember", "CBO Ember Bolt", [
    sprite("lr_ember_core", "Core", "dot", 26, [255, 252, 225], 1, pulse(1, 1.15), x=H, glow=0.9),
    sprite("lr_ember_flame", "Flame", "flame", 130, [255, 130, 40], 0.9, pulse(1, 1.08), x=H - 30, aspect=1.7, rot=180,
           glow=0.5, p={"taper": 0.45, "var": 1}),
    sprite("lr_ember_flame2", "Inner Flame", "flame", 84, [255, 220, 120], 0.5, pulse(1.05, 0.95), x=H - 18,
           aspect=1.6, rot=180, glow=0.3, p={"taper": 0.4, "var": 3}),
    sprite("lr_ember_glow", "Glow", "soft", 140, [255, 80, 20], 0.35, pulse(0.95, 1.1), x=H - 20, aspect=1.7),
    stream("lr_ember_smoke", "Smoke", G((0, [90, 70, 60]), (1, [40, 32, 28])), 40, 0.5, speed=150, rate=50,
           sprite_id='smoke', spread=14, x=H - 50, seed=16, blend='normal', sizeOL=C((0, 0.6), (1, 1.4)),
           opacityOL=C((0, 0.5), (1, 0)), drag=2),
    stream("lr_ember_sparks", "Embers", G((0, [255, 240, 180]), (0.5, [255, 140, 40]), (1, [160, 40, 10])), 12, 0.45,
           speed=210, rate=80, sprite_id='ember', glow=0.4, spread=32, gravY=-60, seed=17),
])

# Ability shots: a white orb, tinted with the ability colour.
projectile("magic_orb", "CBO Magic Orb", [
    sprite("lr_orb_core", "Core", "dot", 20, [255, 255, 255], 1, pulse(1, 1.18), x=H, glow=0.7),
    sprite("lr_orb_star", "Star", "star", 56, [255, 255, 255], 0.8, pulse(1, 1.1), x=H, rot=spin(90), glow=0.3,
           p={"n": 4, "inr": 0.25}),
    sprite("lr_orb_ring", "Ring", "ring", 50, [255, 255, 255], 0.8, pulse(1, 1.12), x=H, glow=0.3, p={"th": 0.16}),
    sprite("lr_orb_aura", "Aura", "soft", 110, [255, 255, 255], pulse(0.38, 0.28), pulse(0.95, 1.1), x=H - 10,
           aspect=1.5),
    stream("lr_orb_motes", "Motes", WHITE, 12, 0.5, speed=200, rate=70, sprite_id='dot', glow=0.4, spread=24,
           turb=500, seed=18),
    stream("lr_orb_tail", "Tail", WHITE, 34, 0.32, speed=200, rate=60, glow=0.1, spread=6, seed=19,
           opacityOL=C((0, 0.5), (1, 0))),
])


# ---------------------------------------------------------------- impacts
# All impact compositions are 256x256 exported to 192 px cells (0.75) for crisp detail.
# Light effects are drawn additively in the game; smoke and dust normally.
import math


def flash(lid, size, color, peak=1.0, grow=(0.3, 1.4), fade=0.22, glow=0.6, start=0.0, aspect=1.0, x=0, y=0):
    return sprite(lid, "Flash", "soft", size, color, K((0, peak), (0.04, peak), (fade, 0)),
                  K((0, grow[0]), (fade * 0.7, grow[1])), glow=glow, start=start, end=start + fade + 0.02,
                  aspect=aspect, x=x, y=y)


def ring(lid, size, color, th=0.12, peak=0.85, grow=(0.2, 1.5), dur=0.35, start=0.0, squash=0, glow=0.5, y=0,
         aspect=1.0):
    return sprite(lid, "Ring", "ring", size, color, K((0, peak), (dur * 0.4, peak * 0.7), (dur, 0)),
                  K((0, grow[0]), (dur, grow[1])), glow=glow, start=start, end=start + dur + 0.02,
                  p={"th": th}, squash=squash, y=y, aspect=aspect)


def sparks(lid, n, speed, life, grad, size=30, spread=360, angle=0, dirmode='omni', gravY=0, drag=2.2,
           stretch=1.5, seed=1, shape='streak', glow=0.4, start=0.0, x=0, y=0, emshape='point', sx=60):
    em = {"x": x, "y": y, "shape": emshape, "sx": sx, "dir": dirmode, "angle": angle, "spread": spread,
          "speed": speed, "speedRnd": 0.5, "bursts": [{"t": 0, "n": n}], "seed": seed}
    return emitter(lid, "Sparks", em,
                   {"life": life, "lifeRnd": 0.4, "sprite": {"kind": "shape", "id": shape, "p": {}}, "size": size,
                    "sizeRnd": 0.5, "sizeOL": C((0, 1), (0.4, 0.7), (1, 0.1)), "opacityOL": FADE, "grad": grad,
                    "alignVel": shape in ('streak', 'flame'), "stretch": stretch if shape == 'streak' else 0,
                    "gravY": gravY, "drag": drag, "glow": glow, "spin": 0 if shape == 'streak' else 180},
                   start=start, end=start + 0.05)


def swoosh(slug, radius, a0, a1, n, width, color, t0=0.0, dt=0.012, life=0.16, cx=0, cy=0, glow=0.5, edge=None):
    """A blade arc: streak segments along a circle, lit one after another (a swing)."""
    layers = []
    step = (a1 - a0) / (n - 1)
    seg = abs(radius * math.radians(step)) * 2.2
    for i in range(n):
        a = math.radians(a0 + step * i)
        x = cx + math.cos(a) * radius
        y = cy + math.sin(a) * radius
        rot = math.degrees(a) + 90
        # Thin at both ends of the swing, thick in the middle.
        k = math.sin(math.pi * (i + 0.5) / n)
        start = t0 + dt * i
        layers.append(sprite("lr_%s_arc_%d" % (slug, i), "Arc %d" % i, "streak", seg, color,
                             K((0, 0), (0.015, 1), (life, 0)), K((0, 0.85), (life, 1.05)),
                             x=round(x, 1), y=round(y, 1), rot=round(rot, 1), aspect=1.0 / max(0.25, k * width),
                             glow=glow, start=round(start, 3), end=round(start + life + 0.02, 3)))
        if edge is not None:
            layers.append(sprite("lr_%s_edge_%d" % (slug, i), "Edge %d" % i, "streak", seg * 0.9, edge,
                                 K((0, 0), (0.015, 0.9), (life * 0.7, 0)), 1,
                                 x=round(x * 0.97, 1), y=round(y * 0.97, 1), rot=round(rot, 1),
                                 aspect=1.0 / max(0.15, k * width * 0.4), start=round(start, 3),
                                 end=round(start + life + 0.02, 3)))
    return layers


HOT = G((0, [255, 255, 255]), (0.3, [255, 236, 150]), (0.7, [255, 150, 60]), (1, [170, 50, 20]))
WARM = G((0, [255, 250, 235]), (0.5, [255, 210, 140]), (1, [230, 120, 60]))

# Melee hit: a bright blade arc across the target, sparks thrown along the blow (+X).
reg("CBO Hit Slash", effect("hit_slash", "CBO Hit Slash", 256, 256, 0.4, 4, 2, 8, 192, 192,
    [sparks("lr_slash_sparks", 18, 560, 0.24, HOT, size=28, spread=60, angle=0, dirmode='dir', gravY=420, seed=3,
            x=10)]
    + swoosh("slash", 62, -75, 75, 9, 0.55, [255, 244, 225], cx=-30, edge=[255, 255, 255])
    + [flash("lr_slash_flash", 110, [255, 214, 150], peak=0.7, fade=0.16, glow=0.3, x=20)],
    t1=0.3))

# Heavy hit (Heroes, bosses, big enemies): wide arc, star burst, shock ring, sparks and grit.
reg("CBO Hit Heavy", effect("hit_heavy", "CBO Hit Heavy", 256, 256, 0.5, 4, 3, 12, 192, 192,
    [sparks("lr_heavy_sparks", 30, 700, 0.32, HOT, size=36, spread=90, angle=0, dirmode='dir', gravY=520, seed=5),
     sparks("lr_heavy_debris", 9, 360, 0.42, G((0, [210, 190, 160]), (1, [90, 70, 50])), size=14, spread=120,
            angle=0, dirmode='dir', gravY=900, drag=1.0, shape='shard', glow=0, seed=6),
     sprite("lr_heavy_star", "Impact Star", "star", 150, [255, 250, 235], K((0, 1), (0.03, 1), (0.14, 0)),
            K((0, 0.45), (0.12, 1.1)), rot=12, glow=0.4, end=0.16, p={"n": 8, "inr": 0.22}),
     ring("lr_heavy_ring", 170, [255, 232, 190], th=0.07, grow=(0.25, 1.25), dur=0.3, glow=0.4)]
    + swoosh("heavy", 74, -85, 85, 11, 0.75, [255, 238, 210], cx=-36, dt=0.01, life=0.2, edge=[255, 255, 255])
    + [flash("lr_heavy_flash", 170, [255, 200, 120], peak=0.75, fade=0.22, glow=0.3)],
    t1=0.34))

# Spear thrust (militia, shieldbearers): a flurry of hot sparks off the point.
reg("CBO Spear Sparks", effect("spear_sparks", "CBO Spear Sparks", 256, 256, 0.5, 4, 3, 12, 192, 192, [
    sparks("lr_spear_flurry", 44, 760, 0.32, HOT, size=30, spread=55, angle=0, dirmode='dir', gravY=700, drag=1.6,
           stretch=1.8, seed=21, glow=0.5),
    sparks("lr_spear_scatter", 20, 420, 0.42, HOT, size=18, spread=150, angle=0, dirmode='dir', gravY=900, drag=1.2,
           stretch=1.3, seed=22, glow=0.4),
    sparks("lr_spear_embers", 10, 260, 0.5, G((0, [255, 240, 190]), (1, [255, 120, 40])), size=10, spread=180,
           dirmode='omni', gravY=600, drag=1.0, shape='ember', glow=0.4, seed=23),
    sprite("lr_spear_glint", "Point Glint", "spark", 90, [255, 250, 235], K((0, 1), (0.03, 1), (0.12, 0)),
           K((0, 0.5), (0.1, 1.1)), glow=0.5, end=0.14),
    flash("lr_spear_flash", 90, [255, 214, 140], peak=0.8, fade=0.14, glow=0.3),
], t1=0.42))

# Magic burst: white, tinted at runtime (shot hits, ability hits, launch flashes).
reg("CBO Magic Burst", effect("magic_burst", "CBO Magic Burst", 256, 256, 0.5, 4, 3, 12, 192, 192, [
    sparks("lr_burst_motes", 16, 330, 0.36, WHITE, size=16, shape='star', drag=3, glow=0.5, seed=8),
    sparks("lr_burst_streaks", 14, 540, 0.22, WHITE, size=30, drag=2.5, seed=9),
    sprite("lr_burst_star", "Star", "star", 120, [255, 255, 255], K((0, 1), (0.03, 1), (0.14, 0)),
           K((0, 0.4), (0.12, 1.0)), rot=22, glow=0.4, end=0.16, p={"n": 4, "inr": 0.18}),
    ring("lr_burst_ring", 160, [255, 255, 255], th=0.09, grow=(0.2, 1.2), dur=0.3, glow=0.4),
    flash("lr_burst_core", 60, [255, 255, 255], peak=1, grow=(0.6, 1.2), fade=0.14, glow=0.8),
    flash("lr_burst_flash", 160, [225, 225, 255], peak=0.6, fade=0.24, glow=0.3),
], t1=0.33))

# Ground slam, light part (additive): isometric shock rings and a flash.
reg("CBO Slam Ring", effect("slam_ring", "CBO Slam Ring", 512, 320, 0.7, 4, 3, 12, 288, 180, [
    sparks("lr_slamr_sparks", 26, 520, 0.3, HOT, size=30, spread=360, dirmode='omni', drag=2.5, seed=11,
           emshape='ring', sx=30),
    ring("lr_slamr_hot", 330, [255, 240, 210], th=0.05, peak=1.0, grow=(0.1, 1.25), dur=0.38, squash=1, glow=0.6),
    ring("lr_slamr_wide", 330, [255, 200, 140], th=0.14, peak=0.6, grow=(0.1, 1.05), dur=0.5, squash=1, glow=0.3),
    flash("lr_slamr_flash", 220, [255, 225, 170], peak=0.6, fade=0.2, aspect=1.6, glow=0.2),
], cam=37, t1=0.6))

# Ground slam, matter part (normal): dust wave and flying rocks.
reg("CBO Slam Dust", effect("slam_dust", "CBO Slam Dust", 512, 320, 0.9, 4, 3, 12, 288, 180, [
    sparks("lr_slamd_rocks", 14, 420, 0.5, G((0, [170, 150, 120]), (1, [80, 66, 52])), size=18, spread=70,
           angle=-90, dirmode='dir', gravY=1100, drag=0.5, shape='shard', glow=0, seed=4),
    emitter("lr_slamd_dust", "Dust Wave",
            {"shape": "ring", "sx": 40, "sy": 10, "dir": "out", "speed": 400, "speedRnd": 0.4,
             "bursts": [{"t": 0, "n": 40}], "seed": 2},
            {"life": 0.8, "lifeRnd": 0.3, "sprite": {"kind": "shape", "id": "smoke", "p": {}}, "size": 80,
             "sizeRnd": 0.4, "sizeOL": C((0, 0.5), (1, 1.5)), "opacityOL": C((0, 0.85), (0.4, 0.6), (1, 0)),
             "grad": G((0, [176, 150, 116]), (1, [118, 98, 78])), "drag": 3.4, "gravY": -40, "spin": 40,
             "squash": 1},
            blend='normal', end=0.05),
], cam=37, t1=0.85))

# Cast sigil: a glowing rune circle on the ground and rising light, white (tinted).
reg("CBO Cast Sigil", effect("cast_sigil", "CBO Cast Sigil", 256, 256, 0.75, 4, 3, 12, 192, 192, [
    emitter("lr_sigil_rays", "Rising Rays",
            {"y": 40, "shape": "ring", "sx": 62, "sy": 4, "dir": "dir", "angle": -90, "spread": 2, "speed": 260,
             "rate": 40, "seed": 3},
            {"life": 0.42, "sprite": {"kind": "shape", "id": "streak", "p": {}}, "size": 44, "sizeRnd": 0.4,
             "sizeOL": C((0, 0.4), (0.3, 1), (1, 0.3)), "opacityOL": FADE_LATE, "grad": WHITE, "alignVel": True,
             "stretch": 1.6, "drag": 1.2, "glow": 0.4, "squash": 1},
            end=0.42),
    emitter("lr_sigil_motes", "Motes",
            {"y": 40, "shape": "circle", "sx": 60, "dir": "dir", "angle": -90, "spread": 20, "speed": 110,
             "rate": 30, "seed": 4},
            {"life": 0.5, "sprite": {"kind": "shape", "id": "spark", "p": {}}, "size": 16, "sizeRnd": 0.4,
             "sizeOL": C((0, 0.4), (0.3, 1), (1, 0.2)), "opacityOL": FADE_LATE, "grad": WHITE, "drag": 1,
             "glow": 0.5},
            end=0.4),
    sprite("lr_sigil_inner", "Inner Circle", "ring", 120, [255, 255, 255], K((0, 0), (0.1, 0.9), (0.5, 0.6), (0.72, 0)),
           K((0, 1.3), (0.15, 1.0), (0.72, 0.95)), y=40, glow=0.5, end=0.73, squash=1, p={"th": 0.04}),
    sprite("lr_sigil_star", "Rune Star", "star", 150, [255, 255, 255], K((0, 0), (0.12, 0.22), (0.5, 0.15), (0.72, 0)),
           K((0, 0.6), (0.2, 1.0), (0.72, 1.05)), y=40, rot=K((0, 0), (0.72, 60), m='lin'), glow=0.3, end=0.73,
           squash=1, p={"n": 6, "inr": 0.8}),
    sprite("lr_sigil_ring", "Rune Circle", "ring", 168, [255, 255, 255], K((0, 0), (0.08, 1), (0.5, 0.75), (0.72, 0)),
           K((0, 0.6), (0.12, 1.0), (0.72, 1.06)), y=40, glow=0.6, end=0.73, squash=1, p={"th": 0.05}),
    sprite("lr_sigil_floor", "Floor Glow", "soft", 190, [255, 255, 255], K((0, 0), (0.1, 0.22), (0.6, 0)),
           K((0, 0.7), (0.6, 1.05)), y=40, end=0.62, squash=1),
], cam=37, t1=0.72))

# Heal: green crosses and light rising around the unit.
reg("CBO Heal Sparkle", effect("heal", "CBO Heal Sparkle", 256, 256, 0.85, 4, 3, 12, 192, 192, [
    emitter("lr_heal_crosses", "Crosses",
            {"y": 20, "shape": "box", "sx": 100, "sy": 60, "dir": "dir", "angle": -90, "spread": 6, "speed": 110,
             "bursts": [{"t": 0, "n": 4}, {"t": 0.12, "n": 3}, {"t": 0.24, "n": 2}], "seed": 4},
            {"life": 0.6, "sprite": {"kind": "shape", "id": "spark", "p": {}}, "size": 46, "sizeRnd": 0.3,
             "sizeOL": C((0, 0.3), (0.25, 1), (1, 0.5)), "opacityOL": FADE_LATE,
             "grad": G((0, [235, 255, 225]), (0.5, [150, 255, 140]), (1, [70, 210, 90])), "spin": 0, "rotRnd": 0,
             "drag": 1.0, "glow": 0.6}),
    emitter("lr_heal_rays", "Rays",
            {"y": 50, "shape": "box", "sx": 110, "sy": 10, "dir": "dir", "angle": -90, "spread": 2, "speed": 220,
             "rate": 34, "seed": 5},
            {"life": 0.45, "sprite": {"kind": "shape", "id": "streak", "p": {}}, "size": 30, "sizeRnd": 0.4,
             "sizeOL": C((0, 0.5), (1, 0.2)), "opacityOL": FADE_LATE,
             "grad": G((0, [220, 255, 200]), (1, [90, 220, 110])), "alignVel": True, "stretch": 1.5, "drag": 1,
             "glow": 0.4},
            end=0.4),
    sprite("lr_heal_glow", "Glow", "soft", 170, [110, 255, 140], K((0, 0), (0.12, 0.45), (0.65, 0)),
           K((0, 0.7), (0.65, 1.1)), y=10, aspect=0.75, end=0.67),
], t1=0.78))

# Death, light part (additive): the soul leaves the body.
reg("CBO Death Soul", effect("death_soul", "CBO Death Soul", 256, 320, 1.0, 4, 3, 12, 192, 240, [
    emitter("lr_death_wisp", "Soul",
            {"y": 50, "dir": "dir", "angle": -90, "spread": 4, "speed": 230, "speedRnd": 0.05,
             "bursts": [{"t": 0.05, "n": 1}], "seed": 6},
            {"life": 0.85, "lifeRnd": 0, "sprite": {"kind": "shape", "id": "flame", "p": {"taper": 0.6, "var": 2}},
             "size": 74, "sizeRnd": 0, "sizeOL": C((0, 0.5), (0.3, 1), (1, 0.4)), "opacityOL": FADE_LATE,
             "grad": WHITE, "alignVel": True, "drag": 0.8, "turbAmp": 240, "turbFreq": 2, "glow": 0.7}),
    emitter("lr_death_motes", "Soul Motes",
            {"y": 60, "shape": "circle", "sx": 34, "dir": "dir", "angle": -90, "spread": 25, "speed": 170,
             "bursts": [{"t": 0.04, "n": 16}], "seed": 7},
            {"life": 0.75, "sprite": {"kind": "shape", "id": "dot", "p": {}}, "size": 9, "sizeRnd": 0.5,
             "sizeOL": C((0, 1), (1, 0.2)), "opacityOL": FADE_LATE, "grad": WHITE, "drag": 1, "turbAmp": 420,
             "glow": 0.5}),
    ring("lr_death_ring", 170, [255, 255, 255], th=0.06, peak=0.8, grow=(0.3, 1.3), dur=0.45, squash=1, y=80,
         aspect=1.0),
    flash("lr_death_flash", 150, [255, 255, 255], peak=0.6, fade=0.3, y=40),
], cam=37, t1=0.95))

# Death, matter part (normal): a dark puff of smoke and dust.
reg("CBO Death Smoke", effect("death_smoke", "CBO Death Smoke", 256, 256, 1.0, 4, 3, 12, 192, 192, [
    emitter("lr_dsmoke_puff", "Smoke Puff",
            {"y": 50, "shape": "circle", "sx": 36, "dir": "out", "speed": 150, "speedRnd": 0.5,
             "bursts": [{"t": 0, "n": 18}], "seed": 8},
            {"life": 0.9, "lifeRnd": 0.3, "sprite": {"kind": "shape", "id": "smoke", "p": {}}, "size": 84,
             "sizeRnd": 0.4, "sizeOL": C((0, 0.5), (1, 1.35)), "opacityOL": C((0, 0.85), (0.5, 0.5), (1, 0)),
             "grad": G((0, [96, 88, 100]), (1, [44, 40, 48])), "drag": 3, "gravY": -70, "spin": 50},
            blend='normal'),
], t1=0.95))

# Walk dust: a puff kicked up behind the feet (normal blend).
reg("CBO Walk Dust", effect("walk_dust", "CBO Walk Dust", 128, 128, 0.6, 4, 2, 8, 96, 96, [
    emitter("lr_dust_puff", "Puff",
            {"y": 20, "shape": "box", "sx": 30, "sy": 6, "dir": "dir", "angle": -90, "spread": 80, "speed": 70,
             "bursts": [{"t": 0, "n": 6}], "seed": 3},
            {"life": 0.5, "lifeRnd": 0.3, "sprite": {"kind": "shape", "id": "smoke", "p": {}}, "size": 50,
             "sizeRnd": 0.4, "sizeOL": C((0, 0.45), (1, 1.3)), "opacityOL": C((0, 0.85), (0.4, 0.55), (1, 0)),
             "grad": G((0, [170, 146, 110]), (1, [128, 108, 84])), "drag": 3, "gravY": -20, "spin": 40},
            blend='normal'),
], t1=0.56))

# Summon: a vortex pulling in, then a flash where the creature appears.
reg("CBO Summon Portal", effect("summon", "CBO Summon Portal", 256, 256, 0.75, 4, 3, 12, 192, 192, [
    flash("lr_summon_pop", 190, [255, 255, 255], peak=0.85, fade=0.25, start=0.32),
    sparks("lr_summon_burst", 16, 420, 0.3, WHITE, size=26, drag=2.5, seed=12, start=0.32, y=20),
    emitter("lr_summon_in", "Vortex",
            {"y": 30, "shape": "ring", "sx": 100, "sy": 10, "dir": "in", "speed": 260, "rate": 70, "seed": 4},
            {"life": 0.35, "sprite": {"kind": "shape", "id": "streak", "p": {}}, "size": 22,
             "sizeOL": C((0, 0.4), (1, 1)), "opacityOL": FADE_LATE, "grad": WHITE, "alignVel": True,
             "stretch": 1.4, "drag": 0, "glow": 0.5, "squash": 1},
            end=0.32),
    ring("lr_summon_ring", 210, [255, 255, 255], th=0.06, peak=0.9, grow=(1.1, 0.2), dur=0.34, squash=1, y=30),
    ring("lr_summon_out", 210, [255, 255, 255], th=0.1, peak=0.8, grow=(0.2, 1.3), dur=0.36, start=0.33, squash=1,
         y=30),
    sprite("lr_summon_floor", "Floor Glow", "soft", 220, [255, 255, 255], K((0, 0), (0.25, 0.5), (0.7, 0)),
           K((0, 0.8), (0.7, 1.1)), y=30, end=0.72, squash=1),
], cam=37, t1=0.72))


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, data in EFFECTS.items():
        with open(os.path.join(OUT, name + '.json'), 'w', encoding='utf-8', newline='\n') as f:
            json.dump(data, f, indent=1)
    print('\n'.join(sorted(EFFECTS)))


if __name__ == '__main__':
    main()
