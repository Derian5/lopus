#!/usr/bin/env python3
"""Generates Act I wasteland content: enemies, enemy abilities and encounters.

Run: python3 gen_content.py <project_root>
All numbers live in the tables below so balance passes only touch this file.
"""
import os
import sys

def _project_root():
    """The project folder (the one with project.godot), wherever the script is run from."""
    candidates = [sys.argv[1]] if len(sys.argv) > 1 else []
    candidates.append(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
    for candidate in candidates:
        if os.path.exists(os.path.join(candidate, "project.godot")):
            return os.path.abspath(candidate)
    sys.exit("gen_act1_content.py: cannot find project.godot; pass the project folder as the first argument.")


ROOT = _project_root()

# Ability descriptions are templates rendered by ui/common/ability_text.gd: numbers come
# from the ability data ({e0.damage}, {area}, ...); cooldown/range/radius live in the header, not the text, keywords are colour tags ([dmg], [cc], ...).
TEMPLATES = {
    'ability.ogre_skull_crack': 'The next basic attack deals [dmg]{e0.amount} bonus damage[/dmg] and [cc]stuns for {e1.status.default_duration}s[/cc].',
    'ability.troll_hex_of_rot': 'Enemies within {e0.radius} attack [debuff]{e0.multiplier:inv_pct}% slower[/debuff]. Slowing auras do not stack.',
    'ability.enemy_summon': 'Calls a [summon]Bog Spawn[/summon] from the mire, up to {e0.max_active_summons} at once.',
    'ability.bog_rotten_burst': 'On death, bursts for [dmg]{e0.damage} damage[/dmg] to enemies within {e0.radius}.',
    'ability.ogre_bone_leap': 'Leaps onto a random [kw]back-line[/kw] enemy (ranged) within {search}, dealing [dmg]{e0.damage} damage[/dmg]. Enemies within {e0.impact_radius} are [cc]knocked back and stunned for {e0.stun_duration}s[/cc].',
    'ability.troll_blood': 'Each basic attack it takes adds a stack of [heal]regeneration: {e0.max_hp_percent_per_stack}% Max HP per second[/heal], up to {e0.max_stacks} stacks. Burst it down quickly.',
    'ability.bog_king_troll_blood': 'Each basic attack it takes adds a stack of [heal]regeneration: {e0.max_hp_percent_per_stack}% Max HP per second[/heal], up to {e0.max_stacks} stacks. Burst it down quickly.',
    'ability.troll_berserk': 'After taking damage, [buff]attacks {e0.modifier.value:bonus_pct}% faster[/buff] for {e0.duration}s.',
    'ability.bog_king_slam': 'The next basic attack also deals [dmg]{e0.damage_multiplier:pct}% damage[/dmg] to every enemy within {e0.radius}.',
    'ability.bog_king_call': 'Raises a [summon]Bog Spawn[/summon], up to {e0.max_active_summons} at once. Bog Spawn burst when they die.',
    'ability.warden_iron_resolve': 'The first time it drops below {e0.health_threshold:pct}% HP, gains a [shield]shield of {e0.shield_max_hp_multiplier:pct}% Max HP[/shield] and [buff]+{e0.armor_multiplier:bonus_pct}% armor[/buff] for {e0.duration}s.',
}

DEF = "res://content/definitions"
ICON = "res://graphics/generated/runware/final/ability_%s.png"


def fmt(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float):
        return repr(v) if v != int(v) else "%.1f" % v
    if isinstance(v, int):
        return str(v)
    if isinstance(v, str) and v.startswith("@"):
        return v[1:]
    if isinstance(v, str):
        return '"%s"' % v.replace('"', '\\"')
    if isinstance(v, tuple) and v[0] == "color":
        return "Color(%s, %s, %s, 1)" % v[1:]
    raise ValueError(v)


def sname(v):
    return '&"%s"' % v


def snames(values):
    return "Array[StringName]([%s])" % ", ".join(sname(v) for v in values)


def strings(values):
    return "Array[String]([%s])" % ", ".join(fmt(v) for v in values)


class Res:
    """Tiny .tres writer with ext/sub resources."""

    def __init__(self, script_class, script_path):
        self.script_class = script_class
        self.ext = []
        self.subs = []
        self.script = self.add_ext("Script", script_path)

    def add_ext(self, kind, path):
        for index, (k, p) in enumerate(self.ext):
            if p == path:
                return 'ExtResource("%d")' % (index + 1)
        self.ext.append((kind, path))
        return 'ExtResource("%d")' % len(self.ext)

    def add_sub(self, name, script_path, props):
        script = self.add_ext("Script", script_path)
        self.subs.append((name, script, props))
        return 'SubResource("%s")' % name

    def write(self, path, props):
        full = os.path.join(ROOT, path)
        uid = ""
        if os.path.exists(full):
            import re
            match = re.search(r'^\[gd_resource[^\]]*\buid="([^"]+)"', open(full).read(), re.M)
            if match:
                uid = ' uid="%s"' % match.group(1)
        lines = ['[gd_resource type="Resource" script_class="%s" load_steps=%d format=3%s]' % (self.script_class, len(self.ext) + len(self.subs) + 1, uid), ""]
        for index, (kind, p) in enumerate(self.ext):
            lines.append('[ext_resource type="%s" path="%s" id="%d"]' % (kind, p, index + 1))
        lines.append("")
        for name, script, sub_props in self.subs:
            lines.append('[sub_resource type="Resource" id="%s"]' % name)
            lines.append("script = %s" % script)
            for key, value in sub_props.items():
                lines.append("%s = %s" % (key, value if isinstance(value, str) and (value.startswith(("SubResource", "ExtResource", "Array", "&", "Color", "PackedFloat32Array"))) else fmt(value)))
            lines.append("")
        lines.append("[resource]")
        lines.append("script = %s" % self.script)
        for key, value in props.items():
            lines.append("%s = %s" % (key, value if isinstance(value, str) and (value.startswith(("SubResource", "ExtResource", "Array", "&", "Color", "PackedFloat32Array"))) else fmt(value)))
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w") as handle:
            handle.write("\n".join(lines) + "\n")


def color(r, g, b):
    return "Color(%s, %s, %s, 1)" % (r, g, b)


# --------------------------------------------------------------------------- abilities

def stun_status(res, name, duration):
    return res.add_sub(name, DEF + "/status_definition.gd", {
        "id": '&"status.%s"' % name.lower(),
        "display_name": "Stun",
        "description": "Prevents actions for a short duration.",
        "default_duration": float(duration),
        "max_stacks": 1,
        "stack_policy": 0,
        "prevents_actions": True,
        "polarity": 2,
    })


def ability(path, ability_id, name, description, icon, color_value, effects_builder, **props):
    res = Res("AbilityDefinition", DEF + "/ability_definition.gd")
    icon_ref = res.add_ext("Texture2D", ICON % icon)
    effects = effects_builder(res)
    base = {
        "presentation_icon": icon_ref,
        "id": sname(ability_id),
        "display_name": name,
        "description": TEMPLATES.get(ability_id, description),
    }
    base.update(props)
    base["effects"] = "Array[AbilityEffect]([%s])" % ", ".join(effects)
    base.setdefault("presentation_color", color_value)
    base["presentation_text"] = name
    base["available_to_heroes"] = False
    base.setdefault("tags", snames(["ability", "enemy"]))
    res.write(path, base)


A = "content/demo/abilities/enemies/"
SLOW = "res://content/demo/statuses/slow.tres"
BURN = None

ABILITIES = []


def define_abilities(t):
    # Ogre Brute: every few seconds the next blow cracks a skull and stuns.
    ability(A + "raider/ogre_skull_crack.tres", "ability.ogre_skull_crack", "Skull Crack",
            "Every %g seconds the next basic attack deals %d bonus damage and stuns the target for %.1f seconds." % (t["crack_cd"], t["crack_dmg"], t["crack_stun"]),
            "wrath_ground_slam", color(0.78, 0.52, 0.3),
            lambda r: [
                r.add_sub("CrackDamage", DEF + "/effects/damage_effect.gd", {"effect_id": '&"effect.ogre_skull_crack_damage"', "amount": float(t["crack_dmg"])}),
                r.add_sub("CrackStun", DEF + "/effects/apply_status_effect.gd", {"effect_id": '&"effect.ogre_skull_crack_stun"', "status": stun_status(r, "ogre_skull_crack_stun", t["crack_stun"])}),
            ],
            activation_mode=1, cooldown_seconds=float(t["crack_cd"]), initial_cooldown_seconds=3.0,
            targeting_policy=1, delivery_method=1, priority=60,
            tags=snames(["ability", "active", "enemy", "stun"]))
    # Troll Hexer: hexes the closest enemy so its attacks slow down.
    ability(A + "summoner/troll_hex_of_rot.tres", "ability.troll_hex_of_rot", "Bog Curse",
            "Passive. Enemies within %d attack %d%% slower." % (t["hex_radius"], round((1 - t["hex_mult"]) * 100)),
            "despair_withering_touch", color(0.5, 0.3, 0.62),
            lambda r: [r.add_sub("Curse", DEF + "/effects/attack_speed_aura_effect.gd", {"effect_id": '&"effect.troll_hex_of_rot"', "radius": float(t["hex_radius"]), "multiplier": float(t["hex_mult"])})],
            kind=1, targeting_policy=0, delivery_method=0,
            tags=snames(["ability", "passive", "enemy", "aura"]))
    # Hexer summon: calls Bog Spawn (shared with the Bog King).
    ability(A + "summoner/enemy_summon.tres", "ability.enemy_summon", "Call Bog Spawn",
            "Every %g seconds calls a Bog Spawn from the mire, up to %d at once." % (t["spit_cd"], t["spit_max"]),
            "enemy_summon", color(0.58, 0.35, 0.78),
            lambda r: [r.add_sub("Summon", DEF + "/effects/summon_effect.gd", {"effect_id": '&"effect.enemy_summon"', "summoned_unit": r.add_ext("Resource", "res://content/demo/enemies/bog_spawn.tres"), "max_active_summons": t["spit_max"]})],
            cooldown_seconds=float(t["spit_cd"]), initial_cooldown_seconds=1.5, targeting_policy=0, priority=100,
            tags=snames(["ability", "active", "summon", "enemy"]))
    # Bog Spawn: bursts on death.
    ability(A + "bog_spawn/bog_rotten_burst.tres", "ability.bog_rotten_burst", "Rotten Burst",
            "Passive. Bursts on death, dealing %d damage to enemies within %d." % (t["burst_dmg"], t["burst_radius"]),
            "gluttony_death_explosion", color(0.5, 0.62, 0.22),
            lambda r: [r.add_sub("Burst", DEF + "/effects/gluttony_death_explosion_effect.gd", {"effect_id": '&"effect.bog_rotten_burst"', "radius": float(t["burst_radius"]), "damage": float(t["burst_dmg"])})],
            kind=1, targeting_policy=0, delivery_method=0,
            tags=snames(["ability", "passive", "enemy", "death"]))
    # Troll Witch Doctor keeps heal + venom (authored by hand, untouched).
    # Ogre Bonebreaker: leaps into the back line.
    ability(A + "ogre_bonebreaker/ogre_bone_leap.tres", "ability.ogre_bone_leap", "Bone-Breaking Leap",
            "Every %g seconds leaps onto a random enemy within %d, dealing %d damage, knocking back and stunning enemies within %d for %.1f seconds." % (t["leap_cd"], t["leap_search"], t["leap_dmg"], t["leap_radius"], t["leap_stun"]),
            "wrath_leap_slam", color(0.86, 0.42, 0.2),
            lambda r: [r.add_sub("Leap", DEF + "/effects/leap_slam_effect.gd", {"effect_id": '&"effect.ogre_bone_leap"', "damage": float(t["leap_dmg"]), "impact_radius": float(t["leap_radius"]), "knockback_distance": 80.0, "stun_duration": float(t["leap_stun"])})],
            cooldown_seconds=float(t["leap_cd"]), initial_cooldown_seconds=float(t["leap_initial"]), targeting_policy=10, delivery_method=0,
            area_radius=float(t["leap_radius"]), target_search_radius=float(t["leap_search"]), priority=110,
            tags=snames(["ability", "active", "enemy", "movement", "stun"]))
    # Troll Berserker / Bog King: troll blood regeneration builds as they are struck.
    for path, ability_id, name, stacks, percent in [
        (A + "troll_berserker/troll_blood.tres", "ability.troll_blood", "Troll Blood", t["blood_stacks"], t["blood_pct"]),
        (A + "bog_king/bog_king_troll_blood.tres", "ability.bog_king_troll_blood", "Ancient Troll Blood", t["king_blood_stacks"], t["king_blood_pct"]),
    ]:
        ability(path, ability_id, name,
                "Passive. Every basic attack taken adds a stack of regeneration, up to %d stacks of %.2g%% Max HP per second. Burst it down quickly." % (stacks, percent),
                "gluttony_regeneration", color(0.36, 0.68, 0.32),
                lambda r, s=stacks, p=percent, a=ability_id: [r.add_sub("Blood", DEF + "/effects/gluttony_regeneration_effect.gd", {"effect_id": '&"effect.%s"' % a.split(".", 1)[1], "max_stacks": s, "max_hp_percent_per_stack": float(p)})],
                kind=1, targeting_policy=0, delivery_method=0,
                tags=snames(["ability", "passive", "enemy", "regeneration"]))
    ability(A + "troll_berserker/troll_berserk.tres", "ability.troll_berserk", "Berserk",
            "After taking damage, attacks %d%% faster for %g seconds. Cooldown %g seconds." % (round((t["berserk_mult"] - 1) * 100), t["berserk_dur"], t["berserk_cd"]),
            "wrath_frenzy", color(0.82, 0.24, 0.16),
            lambda r: [r.add_sub("Haste", DEF + "/effects/stat_modifier_effect.gd", {"effect_id": '&"effect.troll_berserk"', "modifier": r.add_sub("HasteModifier", DEF + "/effects/stat_modifier.gd", {"stat": "attack_speed", "operation": 1, "value": float(t["berserk_mult"])}), "duration": float(t["berserk_dur"])})],
            cooldown_seconds=float(t["berserk_cd"]), required_recent_damage_seconds=2.0, targeting_policy=0, delivery_method=0, priority=90,
            tags=snames(["ability", "active", "enemy", "self_buff"]))
    # Bog King: slam and the endless mire.
    ability(A + "bog_king/bog_king_slam.tres", "ability.bog_king_slam", "Mire Slam",
            "Every %g seconds the next basic attack also hits every enemy within %d for %d%% damage." % (t["slam_cd"], t["slam_radius"], round(t["slam_mult"] * 100)),
            "wrath_ground_slam", color(0.4, 0.56, 0.24),
            lambda r: [r.add_sub("Slam", DEF + "/effects/ground_slam_effect.gd", {"effect_id": '&"effect.bog_king_slam"', "damage_multiplier": float(t["slam_mult"]), "radius": float(t["slam_radius"])})],
            cooldown_seconds=float(t["slam_cd"]), initial_cooldown_seconds=2.0, targeting_policy=0, delivery_method=0, priority=95,
            tags=snames(["ability", "active", "enemy", "area"]))
    ability(A + "bog_king/bog_king_call.tres", "ability.bog_king_call", "Call of the Mire",
            "Every %g seconds raises a Bog Spawn, up to %d at once. Bog Spawn burst when they die." % (t["call_cd"], t["call_max"]),
            "summoner_job_summon", color(0.42, 0.6, 0.3),
            lambda r: [r.add_sub("Call", DEF + "/effects/summon_effect.gd", {"effect_id": '&"effect.bog_king_call"', "summoned_unit": r.add_ext("Resource", "res://content/demo/enemies/bog_spawn.tres"), "max_active_summons": t["call_max"]})],
            cooldown_seconds=float(t["call_cd"]), initial_cooldown_seconds=3.0, targeting_policy=0, priority=100,
            tags=snames(["ability", "active", "summon", "enemy"]))
    # Iron Warden: iron resolve when wounded.
    ability(A + "iron_warden/warden_iron_resolve.tres", "ability.warden_iron_resolve", "Iron Resolve",
            "Passive. The first time it falls below %d%% HP, gains a shield equal to %d%% of Max HP and %d%% more armor for %g seconds." % (round(t["resolve_threshold"] * 100), round(t["resolve_shield"] * 100), round((t["resolve_armor"] - 1) * 100), t["resolve_dur"]),
            "wrath_threshold_guard", color(0.72, 0.62, 0.52),
            lambda r: [r.add_sub("Resolve", DEF + "/effects/threshold_guard_effect.gd", {"effect_id": '&"effect.warden_iron_resolve"', "health_threshold": float(t["resolve_threshold"]), "shield_max_hp_multiplier": float(t["resolve_shield"]), "armor_multiplier": float(t["resolve_armor"]), "duration": float(t["resolve_dur"]), "cooldown_seconds": 999.0})],
            kind=1, targeting_policy=0, delivery_method=0,
            tags=snames(["ability", "passive", "enemy", "shield"]))


# --------------------------------------------------------------------------- enemies

E = "content/demo/enemies/"


def enemy(path, enemy_id, name, description, stats, attack_type, abilities, rgb, tags, boss=None, targeting="closest"):
    script = DEF + ("/boss_definition.gd" if boss else "/enemy_definition.gd")
    res = Res("BossDefinition" if boss else "EnemyDefinition", script)
    block = {k: float(v) for k, v in stats.items()}
    stats_ref = res.add_sub("Stats", DEF + "/stat_block.gd", block)
    props = {}
    if boss:
        props.update({
            "phase_count": boss["phases"],
            "phase_health_thresholds": "PackedFloat32Array(%s)" % ", ".join(str(v) for v in boss["thresholds"]),
            "phase_damage_multiplier": float(boss["dmg"]),
            "phase_attack_speed_multiplier": float(boss["as"]),
            "telegraph_color": color(*boss["color"]),
            "phase_telegraph_text": boss["text"],
        })
    props.update({
        "base_stats": stats_ref,
        "attack_type": sname(attack_type),
        "ability_ids": snames(abilities),
        "placeholder_color": color(*rgb),
        "targeting_mode": targeting,
        "id": sname(enemy_id),
        "display_name": name,
        "description": description,
        "tags": snames(tags),
    })
    res.write(path, props)


def define_enemies(t, s):
    enemy(E + "ogre_brute.tres", "enemy.raider", "Ogre Brute",
          "A thick-skinned wasteland ogre that cracks skulls and stuns whoever stands in front of it.",
          s["brute"], "melee", ["ability.ogre_skull_crack"], (0.62, 0.36, 0.22), ["enemy", "melee", "ogre", "brute"])
    enemy(E + "troll_hexer.tres", "enemy.summoner", "Troll Hexer",
          "A bog troll shaman that calls bloated Bog Spawn from the mire and curses nearby foes.",
          s["hexer"], "ranged", ["ability.enemy_summon", "ability.troll_hex_of_rot"], (0.48, 0.3, 0.6), ["enemy", "ranged", "troll", "summoner"])
    enemy(E + "troll_witch_doctor.tres", "enemy.troll_priest", "Troll Witch Doctor",
          "A durable troll mystic that mends its kin and spreads lasting venom across new targets.",
          s["witch"], "ranged", ["ability.troll_priest_heal", "ability.troll_priest_poison"], (0.34, 0.58, 0.2), ["enemy", "ranged", "support", "troll", "priest"])
    enemy(E + "ogre_bonebreaker.tres", "enemy.ogre_bonebreaker", "Ogre Bonebreaker",
          "A scarred ogre champion that leaps over the front line to smash the archers and priests behind it.",
          s["bonebreaker"], "melee", ["ability.ogre_bone_leap"], (0.72, 0.3, 0.16), ["enemy", "melee", "ogre", "elite"])
    enemy(E + "troll_berserker.tres", "enemy.troll_berserker", "Troll Berserker",
          "A fast, frenzied troll that runs past the front line to tear into archers and priests. Its blood knits its wounds shut with every blow it takes.",
          s["berserker"], "melee", ["ability.troll_blood", "ability.troll_berserk"], (0.3, 0.55, 0.36), ["enemy", "melee", "troll", "regeneration"], targeting="back_line")
    enemy(E + "bog_spawn.tres", "enemy.bog_spawn", "Bog Spawn",
          "A bloated mire creature raised by the Bog King and Troll Hexers. It bursts in a spray of rot when slain.",
          s["spawn"], "melee", ["ability.bog_rotten_burst"], (0.46, 0.56, 0.24), ["enemy", "summon", "melee", "troll"])
    enemy(E + "mugrot_the_bog_king.tres", "enemy.bog_king", "Mugrot the Bog King",
          "Mini-boss. An ancient troll chieftain whose blood never stops healing and whose mire never stops spawning.",
          s["bog_king"], "melee", ["ability.bog_king_call", "ability.bog_king_slam", "ability.bog_king_troll_blood"], (0.3, 0.45, 0.2),
          ["enemy", "boss", "miniboss", "melee", "troll"],
          boss={"phases": 2, "thresholds": [0.5], "dmg": t["king_phase_dmg"], "as": t["king_phase_as"], "color": (0.45, 0.85, 0.25), "text": "THE MIRE RISES: FASTER, HARDER BLOWS"})
    enemy(E + "iron_warden.tres", "enemy.iron_warden", "The Iron Warden",
          "Act I boss. The ogre warlord of the wasteland, clad in plates of salvaged iron.",
          s["warden"], "melee", ["ability.warden_iron_resolve"], (0.55, 0.12, 0.1), ["enemy", "boss", "melee", "armored", "ogre"],
          boss={"phases": 2, "thresholds": [0.5], "dmg": 1.35, "as": 1.2, "color": (1, 0.22, 0.08), "text": "ENRAGED: FASTER AREA ATTACKS"})


# --------------------------------------------------------------------------- encounters

N = "content/demo/encounters/act_1/"
SHORT = {
    "B": "enemy.raider", "H": "enemy.summoner", "W": "enemy.troll_priest", "K": "enemy.ogre_bonebreaker",
    "Z": "enemy.troll_berserker", "M": "enemy.bog_king", "X": "enemy.iron_warden",
}


def expand(spec):
    """'4B 2S' -> ids."""
    result = []
    for part in spec.split():
        count = int(part[:-1]) if len(part) > 1 else 1
        result.extend([SHORT[part[-1]]] * count)
    return result


def encounter(file_name, enc_id, name, description, tier, lo, hi, gold, power, units, props, reinf=None, threshold=2, entry=0, unknown=False, boss=False):
    res = Res("EncounterDefinition", DEF + "/encounter_definition.gd")
    data = {"enemy_ids": snames(expand(units))}
    if reinf:
        data["reinforcement_enemy_ids"] = snames(expand(reinf))
        data["reinforcement_alive_threshold"] = threshold
        data["reinforcement_entry_direction"] = entry
    data.update({
        "gold_reward": gold,
        "enemy_power": float(power),
        "min_encounter_index": lo,
        "max_encounter_index": hi,
        "difficulty_hint": tier,
        "key_properties": strings(props),
        "is_unknown": unknown,
        "is_boss": boss,
        "id": sname(enc_id),
        "display_name": name,
        "description": description,
        "tags": snames(["encounter", "act1"] + (["reinforcements"] if reinf else []) + (["boss"] if boss else [])),
    })
    res.write(N + file_name, data)


def define_encounters(enc):
    for row in enc:
        encounter(*row[:11], **(row[11] if len(row) > 11 else {}))


# --------------------------------------------------------------------------- tuning tables

T = {
    "crack_cd": 8, "crack_dmg": 30, "crack_stun": 1.0,
    "hunt_range": 60,
    "hex_radius": 200, "hex_mult": 0.8,
    "spit_cd": 5, "spit_max": 3,
    "sticky_cd": 5, "sticky_dmg": 8,
    "burst_dmg": 40, "burst_radius": 80,
    "leap_cd": 11, "leap_initial": 2.5, "leap_search": 520, "leap_dmg": 70, "leap_radius": 110, "leap_stun": 1.2,
    "blood_stacks": 10, "blood_pct": 0.4,
    "king_blood_stacks": 8, "king_blood_pct": 0.06,
    "berserk_mult": 1.6, "berserk_dur": 4, "berserk_cd": 10,
    "drum_radius": 260, "drum_mult": 0.75,
    "chant_cd": 7, "chant_shield": 160,
    "slam_cd": 7, "slam_radius": 130, "slam_mult": 1.2,
    "call_cd": 6, "call_max": 4,
    "king_phase_dmg": 1.3, "king_phase_as": 1.25,
    "resolve_threshold": 0.35, "resolve_shield": 0.2, "resolve_armor": 1.5, "resolve_dur": 6,
}

S = {
    "brute": dict(max_hp=950, damage=19, attack_speed=1.0, movement_speed=95, attack_range=44, armor=24),
    "spear": dict(max_hp=300, damage=15, attack_speed=2.4, movement_speed=85, attack_range=250, armor=0),
    "hexer": dict(max_hp=520, damage=9, attack_speed=0.8, movement_speed=80, attack_range=190, armor=4),
    "juggernaut": dict(max_hp=1750, damage=42, attack_speed=1.5, movement_speed=64, attack_range=48, armor=52),
    "witch": dict(max_hp=500, damage=21, attack_speed=1.0, movement_speed=100, attack_range=250, armor=0),
    "bonebreaker": dict(max_hp=1300, damage=28, attack_speed=0.9, movement_speed=92, attack_range=50, armor=30),
    "berserker": dict(max_hp=780, damage=15, attack_speed=1.5, movement_speed=118, attack_range=42, armor=10),
    "drummer": dict(max_hp=700, damage=12, attack_speed=0.9, movement_speed=80, attack_range=200, armor=10),
    "spitter": dict(max_hp=120, damage=6, attack_speed=1.2, movement_speed=95, attack_range=190, armor=0),
    "spawn": dict(max_hp=220, damage=9, attack_speed=1.0, movement_speed=110, attack_range=40, armor=4),
    "bog_king": dict(max_hp=3600, damage=56, attack_speed=0.8, movement_speed=75, attack_range=60, armor=26),
    "warden": dict(max_hp=4600, damage=64, attack_speed=0.75, movement_speed=72, attack_range=55, armor=30),
}

# (file, id, name, description, tier, min, max, gold, power, units, props, {reinf...})
ENC = [
    ("ogres_on_the_road.tres", "encounter.tutorial_volley", "Ogres on the Road", "A small ogre band blocks the old road out of the ruins.", "Low", 0, 0, 110, 1.4, "5B", ["Ogre Brutes only", "Skull Crack stuns your front line"]),
    ("brute_patrol.tres", "encounter.raider_line", "Brute Patrol", "Ogre Brutes on patrol with a single Troll Hexer.", "Low", 1, 3, 120, 1.55, "5B 1H", ["Dense melee front", "One Hexer calling Bog Spawn"]),
    ("spear_ambush.tres", "encounter.spear_ambush", "Raiding Party", "A raiding party led by a scarred champion.", "Low", 1, 3, 125, 1.73, "4B 1K", ["A Bonebreaker leaps into your back line", "Brutes hold the front"]),
    ("hexers_mire.tres", "encounter.hexers_mire", "Hexer's Mire", "Troll Hexers keep calling Bog Spawn from a stinking bog.", "Low", 2, 4, 125, 0.9, "3B 3H", ["Endless Bog Spawn", "Kill the Hexers first"]),
    ("lone_juggernaut.tres", "encounter.lone_juggernaut", "Brute Vanguard", "A few brutes scout ahead. More wait over the dune.", "Low", 1, 3, 130, 2.75, "3B", ["Reinforcements over the dune"], {"reinf": "2B", "threshold": 1, "entry": 1}),
    ("berserker_pack.tres", "encounter.berserker_pack", "Berserker Pack", "Fast trolls that regenerate unless you burst them down.", "Moderate", 3, 6, 150, 1.45, "5Z", ["Troll Blood regeneration", "Berserk when struck"]),
    ("ogres_attack.tres", "encounter.ogres_attack", "Ogres Attack", "Brutes escort two Hexers while more brutes follow behind.", "Moderate", 3, 6, 155, 1.31, "3B 2H", ["Hexers call Bog Spawn"], {"reinf": "4B", "threshold": 2, "entry": 1}),
    ("witch_doctors_escort.tres", "encounter.witch_escort", "Witch Doctor's Escort", "Brutes guard two Witch Doctors who mend every wound.", "Moderate", 4, 6, 155, 0.92, "4B 2W", ["Healing and venom", "Brutes shield the casters"]),
    ("war_drums.tres", "encounter.war_drums", "Hex Circle", "Hexers curse your soldiers while a witch doctor keeps the brutes standing.", "Moderate", 4, 7, 160, 1.01, "4B 2H 1W", ["Bog Curse slows your attacks", "Healing support"]),
    ("marching_warband.tres", "encounter.warband", "Marching Warband", "A full ogre warband on the march.", "Moderate", 4, 7, 165, 0.7, "6B 2H 1W", ["Large mixed force", "Durable melee majority"]),
    ("bonebreakers.tres", "encounter.bonebreakers", "Bonebreakers", "Ogre champions that leap straight into your archers.", "Moderate", 4, 7, 170, 1.55, "2K 4B", ["Leaps into your back line", "Stuns on landing"]),
    ("spear_wall.tres", "encounter.bolt_screen", "Witch Wall", "Witch doctors chant behind a wall of brutes, mending every wound.", "High", 5, 8, 195, 0.9, "3B 3W 1H", ["Three healers", "Rewards fast pressure"]),
    ("encirclement.tres", "encounter.reinforced_assault", "Encirclement", "The first wave pins you down while the second closes in from every side.", "High", 5, 10, 205, 1.02, "3B 1H 1W", ["Second wave from all sides"], {"reinf": "1K 3B 1H", "threshold": 2, "entry": 0}),
    ("troll_warcamp.tres", "encounter.crossfire", "Troll Warcamp", "A troll warcamp: berserkers in front, witch doctors and a hexer behind.", "High", 6, 10, 210, 0.77, "3B 2Z 2W 1H", ["Healing support", "Regenerating berserkers"]),
    ("blood_frenzy.tres", "encounter.blood_frenzy", "Blood Frenzy", "A Bonebreaker leads a frenzied pack. More berserkers howl in the distance.", "High", 6, 11, 215, 0.86, "1K 3Z 1W", ["Leaps and regeneration"], {"reinf": "3Z", "threshold": 2, "entry": 1}),
    ("bog_rising.tres", "encounter.bog_rising", "Bog Rising", "Hexers flood the field with Bog Spawn while berserkers charge.", "High", 7, 11, 220, 0.86, "3H 3Z 1W", ["Endless Bog Spawn"], {"reinf": "4B", "threshold": 2, "entry": 0}),
    ("juggernaut_line.tres", "encounter.juggernaut_line", "Bonebreaker Line", "Three Bonebreakers advance behind a pair of cursing Hexers.", "High", 7, 11, 230, 0.8, "3K 2H", ["Three leaping champions", "Bog Curse"]),
    ("night_raid.tres", "encounter.night_raid", "Night Raid", "Bonebreakers and berserkers strike your camp at night.", "High", 8, 11, 235, 0.92, "2K 3Z", ["Back-line leaps"], {"reinf": "2K 2B", "threshold": 2, "entry": 1}),
    ("court_of_the_bog_king.tres", "encounter.bog_king_court", "Court of the Bog King", "Mini-boss. Mugrot the Bog King holds court in his mire.", "Elite", 5, 7, 280, 0.92, "1M 2Z 1W", ["Mini-boss: regenerating troll chieftain", "Bog Spawn burst on death"], {"reinf": "3B", "threshold": 2, "entry": 1}),
    ("mugrots_revenge.tres", "encounter.bog_king_revenge", "Mugrot's Revenge", "Mini-boss. The Bog King returns with his witch doctors and bonebreakers.", "Elite", 9, 11, 320, 0.75, "1M 1W 2K", ["Mini-boss with healers"], {"reinf": "3Z", "threshold": 2, "entry": 0}),
    ("great_hunt.tres", "encounter.great_hunt", "The Great Hunt", "The whole warband hunts you across the wasteland.", "Elite", 8, 11, 300, 0.75, "5B 2H 1W", ["Huge army"], {"reinf": "3K 2Z", "threshold": 2, "entry": 0}),
    ("siege_of_bones.tres", "encounter.siege_of_bones", "Siege of Bones", "Bonebreakers storm your line while hexers curse it and witch doctors mend the wounded.", "Elite", 9, 11, 310, 0.7, "4K 2H 2W", ["Four leaping champions"], {"reinf": "3B", "threshold": 2, "entry": 1}),
    ("endless_swamp.tres", "encounter.endless_swamp", "Endless Swamp", "Hexers, witch doctors and berserkers wait in a swamp that never ends.", "Elite", 8, 11, 300, 0.66, "2H 2W 4Z", ["Summons, healing and regeneration"], {"reinf": "3Z", "threshold": 2, "entry": 0}),
    ("shapes_in_the_fog.tres", "encounter.unknown_fog", "Shapes in the Fog", "Something moves in the fog. You cannot tell what.", "Moderate", 1, 3, 200, 1.6, "3Z 2H", ["Composition concealed"], {"unknown": True}),
    ("unknown_ambush.tres", "encounter.unknown_ambush", "Unknown Ambush", "Scouts report an ambush but not who is waiting.", "High", 6, 11, 340, 0.81, "4B 2H 1K", ["Composition concealed"], {"reinf": "2K 2Z", "threshold": 2, "entry": 0, "unknown": True}),
    ("iron_warden.tres", "encounter.warden_guard", "The Iron Warden", "The ogre warlord of the wasteland waits with his guard.", "Boss", 0, 100, 300, 1.22, "1X 3B 2H", ["Armored boss with Iron Resolve", "Bog Curse slows your attacks", "Balanced guard"], {"boss": True}),
    ("wardens_last_stand.tres", "encounter.warden_horde", "Warden's Last Stand", "The Iron Warden calls every ogre left in the wasteland.", "Boss", 0, 100, 450, 1.06, "1X 5B", ["Armored boss"], {"reinf": "2K 4B", "threshold": 2, "entry": 0, "boss": True}),
]


def main():
    define_abilities(T)
    define_enemies(T, S)
    rows = []
    for row in ENC:
        extra = row[11] if len(row) > 11 else {}
        rows.append(row[:11] + (extra,))
    for row in rows:
        extra = dict(row[11])
        encounter(*row[:11], reinf=extra.get("reinf"), threshold=extra.get("threshold", 2), entry=extra.get("entry", 0), unknown=extra.get("unknown", False), boss=extra.get("boss", False))
    print("generated", len(rows), "encounters")


if __name__ == "__main__":
    main()
