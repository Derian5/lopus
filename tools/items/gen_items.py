"""Generates every Hero item, its ability and status resources.

Run from anywhere: python tools/items/gen_items.py
To update only art references without rewriting balance: python tools/items/gen_items.py --icons-only
It REWRITES content/demo/items/**, content/demo/abilities/items/** and
content/demo/summons/summoned_skeleton.tres. Edit the tables below, not the .tres files.
Stat keys: dmg, hp, armor, as% (attack speed %), ms% (move speed %), crit (chance %),
critx (crit multiplier), ls (lifesteal %), dodge (%), regen (HP/s), cdr (%).
"""
import argparse
import os
import re
import shutil

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ITEM_DIR = os.path.join(ROOT, "content", "demo", "items")
ABILITY_DIR = os.path.join(ROOT, "content", "demo", "abilities", "items")
ICON_PATH = "res://graphics/ui/item_icons/warcraft/%s.png"

CATEGORY = {"damage": 0, "tank": 1, "support": 2, "command": 3, "unique": 4}
HEROES = {
    "pride": "hero.control_savant", "envy": "hero.army_support", "wrath": "hero.ashen_duelist",
    "despair": "hero.iron_oracle", "greed": "hero.test_vanguard", "gluttony": "hero.thorn_warden",
    "lust": "hero.glass_arcanist",
}
STATS = {
    "dmg": ("damage", 0), "hp": ("max_hp", 0), "armor": ("armor", 0), "as%": ("attack_speed", 2),
    "ms%": ("movement_speed", 2), "crit": ("crit_chance", 0), "critx": ("crit_multiplier", 0),
    "ls": ("lifesteal", 0), "dodge": ("dodge", 0), "regen": ("hp_regen", 0), "cdr": ("cooldown_reduction", 0),
}

EFFECT_SCRIPTS = {
    "OnHitStatusEffect": "res://content/definitions/effects/on_hit_status_effect.gd",
    "ApplyStatusEffect": "res://content/definitions/effects/apply_status_effect.gd",
    "HealEffect": "res://content/definitions/effects/heal_effect.gd",
    "DamageEffect": "res://content/definitions/effects/damage_effect.gd",
}
for name in ["OnHitStackTriggerEffect", "NthHitStatusEffect", "ExecuteOnHitEffect", "LowHealthShieldEffect",
             "DamageRedirectEffect", "EmergencyStealthEffect", "DamageThresholdNovaEffect", "AllyRadiusStatusEffect",
             "PulseHealEffect", "SoldierDamageAuraEffect", "DeathSummonEffect", "LastRitesEffect",
             "IsolationBonusEffect", "EnemyCastBuffEffect", "RageEffect", "EnemySlowAuraEffect",
             "KillGrowthEffect", "PostBattleGoldEffect", "GoldStatScalingEffect", "CharmEffect"]:
    snake = re.sub(r"(?<!^)(?=[A-Z])", "_", name).lower()
    EFFECT_SCRIPTS[name] = "res://content/definitions/effects/items/%s.gd" % snake

# --- statuses -----------------------------------------------------------------------
# polarity: 1 positive, 2 negative. mods: list of (stat, operation, value); op 0 add, 2 add%.
STATUSES = {
    "bleed": dict(name="Bleeding", desc="Takes damage every second.", duration=5, max_stacks=3, stacking=True,
                  polarity=2, presentation_style="bleed", periodic=(1.0, ("DamageEffect", {"amount": 15.0}))),
    "thread": dict(name="Thread", desc="At 3 Threads the unit is bound in place.", duration=4, max_stacks=3,
                   stacking=True, polarity=2),
    "bound": dict(name="Bound", desc="Cannot move.", duration=2, polarity=2, prevents_movement=True),
    "noose": dict(name="Noose", desc="Takes more damage from all sources.", duration=6, polarity=2,
                  mods=[("damage_taken", 0, 35.0)]),
    "fear": dict(name="Feared", desc="Flees in terror and cannot act.", duration=2, polarity=2, fear=True),
    "diligence": dict(name="Diligence", desc="Regenerating HP.", duration=6, polarity=1, mods=[("hp_regen", 0, 25.0)]),
    "shackled": dict(name="Shackled", desc="Cannot move.", duration=3.5, polarity=2, prevents_movement=True),
    "besieged": dict(name="Call of the Besieged", desc="Attacks faster.", duration=8, polarity=1,
                     mods=[("attack_speed", 2, 60.0)]),
    "last_night": dict(name="Last Night", desc="Cannot take damage.", duration=4, polarity=1, invulnerable=True),
    "stolen_joy": dict(name="Stolen Joy", desc="More damage and attack speed per stack.", duration=10, max_stacks=5,
                       stacking=True, polarity=1, mods=[("damage", 2, 25.0), ("attack_speed", 2, 25.0)]),
    "fury": dict(name="Fury", desc="Attacks much faster and ignores most armor.", duration=6, polarity=1,
                 mods=[("attack_speed", 2, 120.0), ("armor_penetration", 0, 80.0)]),
    "eternal_slumber": dict(name="Eternal Slumber", desc="Asleep. Damage does not wake it.", duration=4, polarity=2,
                            prevents_actions=True, prevents_movement=True),
}

# --- abilities ----------------------------------------------------------------------
# kind: "active"/"passive"; effects: list of (EffectClass, params) where params may use
# {"status": "<key>"} or {"summoned_unit": "skeleton"}.
A = {}
A["butcher_cleaver"] = dict(name="Butcher's Cut", kind="passive",
    effects=[("OnHitStatusEffect", {"status": "bleed"})],
    desc="Basic attacks cause [dmg]bleeding for {e0.status.periodic_effects.0.amount} damage per second[/dmg] for {e0.status.default_duration}s, stacking up to {e0.status.max_stacks} times.")
A["spinner_needle"] = dict(name="Binding Thread", kind="passive",
    effects=[("OnHitStackTriggerEffect", {"stack_status": "thread", "stacks_required": 3, "trigger_status": "bound", "per_target_cooldown": 8.0})],
    desc="Basic attacks weave a Thread. At {e0.stacks_required} Threads the target is [cc]bound in place for {e0.trigger_status.default_duration}s[/cc] (once per {e0.per_target_cooldown}s per target).")
A["hangman_bow"] = dict(name="Noose", kind="passive",
    effects=[("NthHitStatusEffect", {"hits_required": 3, "status": "noose"})],
    desc="Every {e0.hits_required}rd basic attack tightens a Noose: the target [debuff]takes +{e0.status.stat_modifiers.0.value}% damage from all sources[/debuff] for {e0.status.default_duration}s.")
A["executioner_gloves"] = dict(name="Execution", kind="passive",
    effects=[("ExecuteOnHitEffect", {"health_threshold": 0.2, "gold_per_execute": 15, "max_gold": 90})],
    desc="Basic attacks [dmg]execute[/dmg] enemies left below {e0.health_threshold:pct}% HP (not bosses). After a won battle [gold]+{e0.gold_per_execute} Gold per execution[/gold] (up to {e0.max_gold}).")
A["ash_shroud"] = dict(name="Ashen Veil", kind="passive",
    effects=[("LowHealthShieldEffect", {"health_threshold": 0.4, "shield_amount": 600.0, "duration": 6.0, "regen_bonus": 30.0})],
    desc="Once per battle, below {e0.health_threshold:pct}% HP gain a [shield]shield of {e0.shield_amount}[/shield] for {e0.duration}s and [heal]+{e0.regen_bonus} HP regeneration per second[/heal] while it holds.")
A["martyr_ribs"] = dict(name="Martyrdom", kind="passive",
    effects=[("DamageRedirectEffect", {"radius": 400.0, "redirect_percent": 40.0, "heal_percent": 25.0})],
    desc="[shield]Takes {e0.redirect_percent}% of the damage[/shield] dealt to allies within {e0.radius} and [heal]heals for {e0.heal_percent}%[/heal] of the damage taken this way.")
A["shadow_monk_cloak"] = dict(name="Vanish", kind="active", cooldown=30.0, targeting=0,
    effects=[("EmergencyStealthEffect", {"health_threshold": 0.4, "duration": 3.0, "heal_percent": 25.0})],
    desc="Below {e0.health_threshold:pct}% HP, [buff]turns invisible for {e0.duration}s[/buff] (enemies lose their target) and [heal]restores {e0.heal_percent}% Max HP[/heal].")
A["thorn_crown"] = dict(name="Crown of Thorns", kind="passive",
    effects=[("DamageThresholdNovaEffect", {"damage_threshold": 300.0, "damage": 250.0, "radius": 200.0, "status": "fear", "heal_percent": 15.0})],
    desc="Every {e0.damage_threshold} damage taken bursts outward: [dmg]{e0.damage} damage[/dmg] to enemies within {e0.radius}, [cc]fear for {e0.status.default_duration}s[/cc] and [heal]heals {e0.heal_percent}% Max HP[/heal].")
A["lamp_of_penance"] = dict(name="Light of Penance", kind="active", cooldown=10.0, targeting=2, search=800.0,
    effects=[("HealEffect", {"amount": 400.0})],
    desc="[heal]Heals {e0.amount} HP[/heal] to the ally with the lowest HP within {search}.")
A["beads_of_diligence"] = dict(name="Diligent Prayer", kind="active", cooldown=20.0, targeting=0,
    effects=[("AllyRadiusStatusEffect", {"status": "diligence", "radius": 500.0, "require_wounded_ally": True})],
    desc="All allies within {e0.radius} gain [heal]+{e0.status.stat_modifiers.0.value} HP regeneration per second[/heal] for {e0.status.default_duration}s.")
A["canon_shackles"] = dict(name="Canon's Shackles", kind="active", cooldown=14.0, targeting=8,
    effects=[("ApplyStatusEffect", {"status": "shackled"})],
    desc="[cc]Roots the enemy with the highest damage[/cc] for {e0.status.default_duration}s.")
A["vial_of_tears"] = dict(name="Mother's Tears", kind="passive",
    effects=[("PulseHealEffect", {"interval": 1.0, "target_count": 3, "max_hp_percent": 4.0})],
    desc="Every second [heal]heals the {e0.target_count} nearest wounded allies for {e0.max_hp_percent}% of this Hero's Max HP[/heal].")
A["horn_of_besieged"] = dict(name="Call of the Besieged", kind="active", cooldown=40.0, targeting=0,
    effects=[("AllyRadiusStatusEffect", {"status": "besieged", "radius": 0.0, "min_wounded_allies": 3, "wounded_health_ratio": 0.5})],
    desc="When {e0.min_wounded_allies}+ allies are below {e0.wounded_health_ratio:pct}% HP, the whole army [buff]attacks {e0.status.stat_modifiers.0.value}% faster[/buff] for {e0.status.default_duration}s.")
A["banner_of_fallen"] = dict(name="Banner of the Fallen", kind="passive",
    effects=[("SoldierDamageAuraEffect", {"radius": 600.0, "soldier_percent": 25.0, "veteran_percent": 40.0, "veteran_min_level": 1})],
    desc="Aura {e0.radius}: allied Soldiers [buff]deal +{e0.soldier_percent}% damage[/buff], veterans (Veterancy {e0.veteran_min_level}+) [buff]+{e0.veteran_percent}%[/buff].")
A["necromagister_skull"] = dict(name="Raise the Fallen", kind="passive",
    effects=[("DeathSummonEffect", {"summoned_unit": "skeleton", "radius": 400.0, "chance_percent": 50.0, "lifetime": 20.0, "max_active_summons": 6})],
    desc="When an enemy dies within {e0.radius}, {e0.chance_percent}% chance to raise a [summon]Skeleton ({e0.summoned_unit.base_stats.max_hp} HP, {e0.summoned_unit.base_stats.damage} damage)[/summon] for {e0.lifetime}s, up to {e0.max_active_summons} at once.")
A["bell_of_last_night"] = dict(name="Last Night", kind="active", cooldown=0.0, targeting=0,
    effects=[("LastRitesEffect", {"army_alive_ratio": 0.5, "status": "last_night", "heal_percent": 40.0})],
    desc="Once per battle, when less than {e0.army_alive_ratio:pct}% of the army is alive, all allies become [shield]invulnerable for {e0.status.default_duration}s[/shield] and [heal]heal {e0.heal_percent}% HP[/heal].")
A["pride_crown"] = dict(name="Unbroken Majesty", kind="passive",
    effects=[("IsolationBonusEffect", {"radius": 500.0, "damage_percent": 90.0, "damage_taken_percent": -45.0})],
    desc="While no ally is within {e0.radius}, [buff]deals +{e0.damage_percent}% damage[/buff] and [shield]takes {e0.damage_taken_percent:abs}% less damage[/shield].")
A["envy_mask"] = dict(name="Stolen Joy", kind="passive",
    effects=[("EnemyCastBuffEffect", {"radius": 800.0, "status": "stolen_joy"})],
    desc="When an enemy within {e0.radius} uses an active ability, gain [buff]+{e0.status.stat_modifiers.0.value}% damage and +{e0.status.stat_modifiers.1.value}% attack speed[/buff] for {e0.status.default_duration}s, stacking up to {e0.status.max_stacks} times.")
A["wrath_axe"] = dict(name="Fury", kind="passive",
    effects=[("RageEffect", {"damage_per_point": 15.0, "points_required": 40.0, "status": "fury"})],
    desc="Damage taken builds Rage (1 per {e0.damage_per_point} damage). At {e0.points_required} Rage, for {e0.status.default_duration}s [buff]attacks {e0.status.stat_modifiers.0.value}% faster[/buff] and [dmg]ignores {e0.status.stat_modifiers.1.value}% of the target's armor[/dmg].")
A["despair_chains_aura"] = dict(name="Leaden Chains", kind="passive",
    effects=[("EnemySlowAuraEffect", {"radius": 450.0, "slow_percent": 45.0})],
    desc="Aura {e0.radius}: enemies [cc]attack and move {e0.slow_percent}% slower[/cc].")
A["despair_chains_sleep"] = dict(name="Eternal Slumber", kind="active", cooldown=10.0, targeting=8,
    effects=[("ApplyStatusEffect", {"status": "eternal_slumber"})],
    desc="Puts the enemy with the highest damage to [cc]sleep for {e0.status.default_duration}s[/cc]. Damage does not wake it.")
A["greed_idol"] = dict(name="Marauder's Hoard", kind="passive",
    effects=[("GoldStatScalingEffect", {"percent_per_step": 2.0, "gold_step": 50, "max_percent": 50.0}), ("PostBattleGoldEffect", {"gold": 50})],
    desc="[buff]+{e0.percent_per_step}% damage and Max HP[/buff] for every {e0.gold_step} Gold you hold (up to +{e0.max_percent}%). After a won battle [gold]+{e1.gold} Gold[/gold].")
A["gluttony_maw"] = dict(name="Insatiable", kind="passive",
    effects=[("KillGrowthEffect", {"max_hp_per_kill": 15.0, "max_total": 500.0, "heal_percent": 20.0})],
    desc="Each enemy this Hero kills grants [heal]+{e0.max_hp_per_kill} Max HP for the rest of the run[/heal] (up to +{e0.max_total}) and [heal]heals {e0.heal_percent}% Max HP[/heal].")
A["lust_veil"] = dict(name="Temptation", kind="active", cooldown=10.0, targeting=9,
    effects=[("CharmEffect", {"duration": 5.0})],
    desc="[cc]Charms the enemy with the most HP[/cc] for {e0.duration}s: it attacks its own allies. Bosses are immune.")

# --- items ----------------------------------------------------------------------------
# (category, slug, name, price, stats, ability keys, hero)
ITEMS = [
    ("damage", "butcher_cleaver", "Butcher's Cleaver", 325, {"dmg": 45, "as%": 25}, ["butcher_cleaver"]),
    ("damage", "spinner_needle", "Spinner's Needle", 325, {"as%": 60, "dmg": 25}, ["spinner_needle"]),
    ("damage", "hangman_bow", "Hangman's Bow", 400, {"as%": 55, "dmg": 40}, ["hangman_bow"]),
    ("damage", "executioner_gloves", "Executioner's Gloves", 500, {"dmg": 80, "crit": 25, "critx": 2.5}, ["executioner_gloves"]),
    ("damage", "gravedigger_fang", "Gravedigger's Fang", 250, {"dmg": 60, "ls": 25}, []),
    ("damage", "traitor_stiletto", "Traitor's Stiletto", 275, {"dmg": 45, "crit": 40, "critx": 2.0, "as%": 25}, []),
    ("damage", "devourer_ring", "Devourer's Ring", 375, {"dmg": 70, "ls": 28, "as%": 25}, []),
    ("damage", "censer_of_decay", "Censer of Decay", 325, {"as%": 60, "dmg": 45}, []),
    ("damage", "cathedral_hammer", "Cathedral Mason's Hammer", 475, {"dmg": 110, "armor": 25, "hp": 400}, []),
    ("tank", "ash_shroud", "Ash Shroud", 325, {"hp": 450, "armor": 12}, ["ash_shroud"]),
    ("tank", "martyr_ribs", "Martyr's Ribs", 375, {"hp": 700, "regen": 8}, ["martyr_ribs"]),
    ("tank", "shadow_monk_cloak", "Shadow Monk's Cloak", 325, {"dodge": 45, "ms%": 30, "hp": 250}, ["shadow_monk_cloak"]),
    ("tank", "thorn_crown", "Crown of Thorns", 450, {"armor": 25, "hp": 700, "dmg": 35}, ["thorn_crown"]),
    ("tank", "bone_bell", "Bone Bell", 200, {"hp": 500, "armor": 12, "regen": 6}, []),
    ("tank", "plague_hound_hide", "Plague Hound Hide", 250, {"hp": 500, "armor": 20, "regen": 10}, []),
    ("tank", "spiked_cuirassier", "Spiked Cuirassier", 375, {"armor": 35, "hp": 500, "dmg": 40}, []),
    ("tank", "iron_maiden", "Iron Maiden", 500, {"armor": 40, "hp": 800, "regen": 10}, []),
    ("tank", "boar_heart", "Boar's Heart", 425, {"hp": 1100, "regen": 20, "armor": 10}, []),
    ("support", "lamp_of_penance", "Lamp of Penance", 275, {"hp": 250, "cdr": 35}, ["lamp_of_penance"]),
    ("support", "beads_of_diligence", "Beads of Diligence", 250, {"cdr": 45, "dmg": 25, "hp": 250}, ["beads_of_diligence"]),
    ("support", "canon_shackles", "Canon's Shackles", 350, {"dmg": 35, "cdr": 25}, ["canon_shackles"]),
    ("support", "vial_of_tears", "Vial of Mother's Tears", 325, {"hp": 600, "regen": 15, "cdr": 25}, ["vial_of_tears"]),
    ("support", "seal_of_oblivion", "Seal of Oblivion", 400, {"hp": 600, "cdr": 45, "regen": 15}, []),
    ("support", "book_of_damned_names", "Book of Damned Names", 425, {"hp": 600, "cdr": 50, "dmg": 40}, []),
    ("support", "crimson_mass_chalice", "Chalice of the Crimson Mass", 375, {"cdr": 60, "hp": 650, "ls": 25, "regen": 10}, []),
    ("support", "plague_doctor_mask", "Plague Doctor's Mask", 450, {"hp": 900, "cdr": 55, "armor": 15, "regen": 20}, []),
    ("support", "black_bile_flask", "Flask of Black Bile", 200, {"hp": 500, "regen": 20, "cdr": 35}, []),
    ("command", "horn_of_besieged", "Horn of the Besieged", 350, {"hp": 350, "ms%": 25, "as%": 25}, ["horn_of_besieged"]),
    ("command", "banner_of_fallen", "Banner of Fallen Companies", 475, {"hp": 400, "armor": 12, "dmg": 40}, ["banner_of_fallen"]),
    ("command", "necromagister_skull", "Necromagister's Skull", 500, {"hp": 350, "dmg": 50, "cdr": 25}, ["necromagister_skull"]),
    ("command", "bell_of_last_night", "Bell of the Last Night", 750, {"hp": 900, "armor": 30, "dmg": 50}, ["bell_of_last_night"]),
    ("command", "rusted_talisman", "Rusted Talisman of Sorrow", 175, {"hp": 350, "armor": 10, "as%": 25}, []),
    ("command", "recruiter_signet", "Recruiter's Signet", 325, {"dmg": 50, "hp": 450, "armor": 12}, []),
    ("command", "executor_seal", "Executor's Seal", 350, {"hp": 450, "cdr": 35, "dmg": 40}, []),
    ("command", "bone_shepherd_staff", "Bone Shepherd's Staff", 475, {"hp": 700, "cdr": 45, "dmg": 60}, []),
    ("unique", "pride_crown", "Crown of Unbroken Majesty", 750, {"hp": 700, "dmg": 80, "armor": 15}, ["pride_crown"], "pride"),
    ("unique", "envy_mask", "Mask of Stolen Joy", 700, {"hp": 450, "as%": 60, "dodge": 25}, ["envy_mask"], "envy"),
    ("unique", "wrath_axe", "Crimson Axe of Fury", 725, {"dmg": 90, "ls": 25, "as%": 25}, ["wrath_axe"], "wrath"),
    ("unique", "despair_chains", "Chains of Eternal Slumber", 700, {"hp": 900, "armor": 25, "cdr": 35}, ["despair_chains_aura", "despair_chains_sleep"], "despair"),
    ("unique", "greed_idol", "Marauder's Golden Idol", 800, {"dmg": 70, "hp": 700, "armor": 15}, ["greed_idol"], "greed"),
    ("unique", "gluttony_maw", "Insatiable Maw", 725, {"hp": 1200, "ls": 25, "regen": 15}, ["gluttony_maw"], "gluttony"),
    ("unique", "lust_veil", "Scarlet Veil of Temptation", 700, {"as%": 70, "dodge": 40, "ms%": 25}, ["lust_veil"], "lust"),
]

ABILITY_ITEM_SLUGS = {key: entry[1] for entry in ITEMS for key in entry[5]}

FLAVOR = {
    "damage": "A weapon of the wasteland's executioners.",
    "tank": "Protection paid for in blood and bone.",
    "support": "A relic of the cathedral's healers.",
    "command": "A token that makes the whole army fight harder.",
    "unique": "Forged for a single Sin.",
}


def num(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    return repr(float(value))


class Res:
    """Accumulates ext/sub resources for one .tres file."""

    def __init__(self):
        self.ext = []  # (type, path)
        self.subs = []  # (id, lines)

    def ext_id(self, kind, path):
        for index, (k, p) in enumerate(self.ext):
            if p == path:
                return str(index + 1)
        self.ext.append((kind, path))
        return str(len(self.ext))

    def sub(self, sub_id, lines):
        if not any(existing == sub_id for existing, _ in self.subs):
            self.subs.append((sub_id, lines))
        return sub_id

    def render(self, script_class, resource_lines):
        out = ['[gd_resource type="Resource" script_class="%s" load_steps=%d format=3]' % (script_class, len(self.ext) + len(self.subs) + 1), ""]
        for index, (kind, path) in enumerate(self.ext):
            out.append('[ext_resource type="%s" path="%s" id="%d"]' % (kind, path, index + 1))
        out.append("")
        for sub_id, lines in self.subs:
            out.append('[sub_resource type="Resource" id="%s"]' % sub_id)
            out.extend(lines)
            out.append("")
        out.append("[resource]")
        out.extend(resource_lines)
        return "\n".join(out) + "\n"


def modifier_sub(res, sub_id, stat, operation, value):
    script = res.ext_id("Script", "res://content/definitions/effects/stat_modifier.gd")
    return res.sub(sub_id, ['script = ExtResource("%s")' % script, 'stat = "%s"' % stat, "operation = %d" % operation, "value = %s" % num(float(value))])


def status_sub(res, key):
    spec = STATUSES[key]
    sub_id = "Status_%s" % key
    if any(existing == sub_id for existing, _ in res.subs):
        return sub_id
    script = res.ext_id("Script", "res://content/definitions/status_definition.gd")
    lines = ['script = ExtResource("%s")' % script, 'id = &"status.item_%s"' % key, 'display_name = "%s"' % spec["name"],
             'description = "%s"' % spec["desc"], "default_duration = %s" % num(float(spec["duration"])),
             "max_stacks = %d" % spec.get("max_stacks", 1), "stack_policy = %d" % (1 if spec.get("stacking") else 0)]
    mods = []
    for index, (stat, operation, value) in enumerate(spec.get("mods", [])):
        mods.append(modifier_sub(res, "Mod_%s_%d" % (key, index), stat, operation, value))
    if "periodic" in spec:
        interval, (effect_class, params) = spec["periodic"]
        effect = effect_sub(res, "Periodic_%s" % key, effect_class, params, "effect.item_%s_tick" % key)
        lines.append("periodic_interval = %s" % num(float(interval)))
        lines.append('periodic_effects = Array[Resource]([SubResource("%s")])' % effect)
    if mods:
        mod_script = res.ext_id("Script", "res://content/definitions/effects/stat_modifier.gd")
        lines.append('stat_modifiers = Array[ExtResource("%s")]([%s])' % (mod_script, ", ".join('SubResource("%s")' % m for m in mods)))
    for flag, field in [("prevents_actions", "prevents_actions"), ("prevents_movement", "prevents_movement"),
                        ("fear", "causes_fear"), ("invulnerable", "grants_invulnerability")]:
        if spec.get(flag):
            lines.append("%s = true" % field)
    lines.append("polarity = %d" % spec["polarity"])
    if spec.get("presentation_style"):
        lines.append('presentation_style = &"%s"' % spec["presentation_style"])
    res.sub(sub_id, lines)
    return sub_id


def effect_sub(res, sub_id, effect_class, params, effect_id):
    script = res.ext_id("Script", EFFECT_SCRIPTS[effect_class])
    lines = ['script = ExtResource("%s")' % script, 'effect_id = &"%s"' % effect_id]
    for key, value in params.items():
        if key in ("status", "stack_status", "trigger_status"):
            lines.append('%s = SubResource("%s")' % (key, status_sub(res, value)))
        elif key == "summoned_unit":
            lines.append('%s = ExtResource("%s")' % (key, res.ext_id("Resource", "res://content/demo/summons/summoned_skeleton.tres")))
        else:
            lines.append("%s = %s" % (key, num(value)))
    res.sub(sub_id, lines)
    return sub_id


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", newline="\n") as handle:
        handle.write(text)


def ability_text(key, spec, category):
    res = Res()
    script = res.ext_id("Script", "res://content/definitions/ability_definition.gd")
    icon = res.ext_id("Texture2D", ICON_PATH % ABILITY_ITEM_SLUGS[key])
    effects = [effect_sub(res, "Effect%d" % index, cls, params, "effect.item_%s_%d" % (key, index)) for index, (cls, params) in enumerate(spec["effects"])]
    active = spec["kind"] == "active"
    lines = ['script = ExtResource("%s")' % script, 'icon = ExtResource("%s")' % icon, 'presentation_icon = ExtResource("%s")' % icon,
             'id = &"ability.item_%s"' % key, 'display_name = "%s"' % spec["name"], 'description = "%s"' % spec["desc"],
             "kind = %d" % (0 if active else 1)]
    if spec.get("cooldown"):
        lines.append("cooldown_seconds = %s" % num(float(spec["cooldown"])))
    lines.append("targeting_policy = %d" % spec.get("targeting", 0))
    lines.append("delivery_method = 0")
    lines.append('effects = Array[Resource]([%s])' % ", ".join('SubResource("%s")' % e for e in effects))
    if spec.get("search"):
        lines.append("target_search_radius = %s" % num(float(spec["search"])))
    lines.append('presentation_text = "%s"' % spec["name"])
    lines.append("available_to_heroes = false")
    lines.append('tags = Array[StringName]([&"ability", &"item", &"%s"])' % ("active" if active else "passive"))
    return res.render("AbilityDefinition", lines)


def item_text(entry):
    category, slug, name, price, stats, abilities = entry[:6]
    hero = entry[6] if len(entry) > 6 else None
    res = Res()
    script = res.ext_id("Script", "res://content/definitions/item_definition.gd")
    icon = res.ext_id("Texture2D", ICON_PATH % slug)
    mods = [modifier_sub(res, "Stat%d" % index, STATS[key][0], STATS[key][1], value) for index, (key, value) in enumerate(stats.items())]
    mod_script = res.ext_id("Script", "res://content/definitions/effects/stat_modifier.gd")
    lines = ['script = ExtResource("%s")' % script, 'icon = ExtResource("%s")' % icon, "category = %d" % CATEGORY[category],
             'passive_effects = Array[ExtResource("%s")]([%s])' % (mod_script, ", ".join('SubResource("%s")' % m for m in mods)),
             "ability_ids = Array[StringName]([%s])" % ", ".join('&"ability.item_%s"' % a for a in abilities)]
    if hero:
        lines.append('allowed_hero_ids = Array[StringName]([&"%s"])' % HEROES[hero])
    lines += ["price = %d" % price, "sell_price = %d" % (price // 2), 'id = &"item.%s"' % slug, 'display_name = "%s"' % name,
              'description = "%s"' % FLAVOR[category],
              'tags = Array[StringName]([&"item", &"hero", &"%s"%s])' % (category, ', &"unique"' if hero else "")]
    return res.render("ItemDefinition", lines)


SKELETON = '''[gd_resource type="Resource" script_class="EnemyDefinition" format=3]

[ext_resource type="Script" path="res://content/definitions/enemy_definition.gd" id="1"]
[ext_resource type="Script" path="res://content/definitions/stat_block.gd" id="2"]

[sub_resource type="Resource" id="Stats"]
script = ExtResource("2")
max_hp = 200.0
damage = 30.0
attack_speed = 1.0
movement_speed = 100.0
attack_range = 40.0
armor = 0.0

[resource]
script = ExtResource("1")
base_stats = SubResource("Stats")
placeholder_color = Color(0.86, 0.84, 0.74, 1)
id = &"enemy.summoned_skeleton"
display_name = "Skeleton"
description = "A fallen enemy raised for a short time by the Necromagister's Skull."
tags = Array[StringName]([&"enemy", &"summon", &"melee", &"undead"])
'''


def update_icon_references():
    """Preserve authored balance and other edits when installing a new art set."""
    changes = []
    for entry in ITEMS:
        category, slug = entry[:2]
        paths = [os.path.join(ITEM_DIR, category, slug + ".tres")]
        paths += [os.path.join(ABILITY_DIR, key + ".tres") for key in entry[5]]
        for path in paths:
            with open(path, encoding="utf-8") as handle:
                text = handle.read()
            pattern = r'(?m)^(\[ext_resource type="Texture2D"[^\n]*?path=")[^"]+("[^\n]*\])$'
            def replace_icon(match):
                line = match[1] + ICON_PATH % slug + match[2]
                return re.sub(r' uid="[^"]+"', "", line)
            updated, count = re.subn(pattern, replace_icon, text, count=1)
            if count != 1:
                raise ValueError("Expected one icon resource in %s" % path)
            if updated != text:
                changes.append((path, updated))
    for path, updated in changes:
        write(path, updated)
    print("Updated icon references in %d resources; balance preserved." % len(changes))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--icons-only", action="store_true", help="Update texture references only.")
    args = parser.parse_args()
    for entry in ITEMS:
        path = os.path.join(ROOT, (ICON_PATH % entry[1]).removeprefix("res://"))
        if not os.path.isfile(path):
            raise FileNotFoundError("Missing icon: %s; run download_item_icons.py first." % path)
    if args.icons_only:
        update_icon_references()
        return
    for directory in (ITEM_DIR, ABILITY_DIR):
        if os.path.isdir(directory):
            shutil.rmtree(directory)
    write(os.path.join(ROOT, "content", "demo", "summons", "summoned_skeleton.tres"), SKELETON)
    used = set()
    for entry in ITEMS:
        category = entry[0]
        write(os.path.join(ITEM_DIR, category, entry[1] + ".tres"), item_text(entry))
        for key in entry[5]:
            used.add(key)
            write(os.path.join(ABILITY_DIR, key + ".tres"), ability_text(key, A[key], category))
    missing = set(A) - used
    assert not missing, missing
    print("Wrote %d items and %d item abilities." % (len(ITEMS), len(used)))


if __name__ == "__main__":
    main()
