### Сложность Act I

Сложность Act I задаётся тремя слоями. Первые два перемножаются в общую силу `p`, которая даёт врагу `p^0.85` Max HP и `p^1.15` Damage: урон растёт быстрее здоровья, чтобы поздние бои становились опаснее, а не длиннее (по таймауту в 120 секунд побеждает сторона с большим суммарным HP). Это касается стартовой группы и подкреплений; призванные существа используют свои базовые значения.

| Слой | Где | Назначение |
|---|---|---|
| `act_one_enemy_power_curve` | `demo_route.tres` | Сила врагов по индексу боя (`0..12`). Растёт вместе с уровнями героев и veterancy солдат |
| `act_two_enemy_power_curve` | `demo_route.tres` | То же для Акта II (`0..11`). Пусто = сила 1 |
| `enemy_power` | `EncounterDefinition` | Относительная сила конкретной карты внутри своего tier |
| `base_stats` | `EnemyDefinition` | Базовые характеристики врага |

Пример: Ogre Brute (950 HP, 19 Damage) в карте с `enemy_power = 1.1` на 9-м бою (`curve[8] = 3.35`): `p = 3.685`, HP `950 × 3.685^0.85 ≈ 2880`, Damage `19 × 3.685^1.15 ≈ 85`.

`difficulty_hint` теперь принимает `Low`, `Moderate`, `High`, `Elite` или `Boss`. Он управляет не только иконками угрозы на карте, но и частотой появления: `EncounterDefinition.selection_weight()` даёт лёгким картам больший вес в начале акта, а `High` и `Elite` — ближе к боссу. Диапазон `min_encounter_index..max_encounter_index` по-прежнему жёстко ограничивает, где карта может появиться.

Сейчас Act I содержит 12 обычных боёв (индексы `0..11`) и босса 13-м боем (`act_one_boss_wave = 13`).

### Баланс (Balance Lab, октябрь 2026)

Цель — средний винрейт около 30% по всем стилям Balance Lab, потери в каждом бою и гибель дальников. Кривые подобраны прогонами `sim_cli.gd` (48 забегов на итерацию): ранние бои ослаблены (0.48–0.72), середина Акта I и босс усилены, у Акта II своя растущая кривая. Ловушки Hexer's Mire, Marching Warband и Witch Doctor's Escort ослаблены через `enemy_power`, слишком лёгкие Raiding Party, Brute Vanguard, Bonebreakers, боссы и карты Акта II — усилены.

Удар по тылу: Troll Berserker (`targeting_mode = "back_line"` в `EnemyDefinition`) бежит к ближайшему дальнику; Bone-Breaking Leap использует цель `RANDOM_BACK_LINE_ENEMY`.

### Враги Act I — жители пустоши

Врагов 8 (включая боссов и призыв Bog Spawn). Ogre Juggernaut, Ogre War-Drummer, Troll Spear-Thrower и Bog Spitter удалены как повторяющие других.

| ID | Имя | Роль | Способности |
|---|---|---|---|
| `enemy.raider` | Ogre Brute | Бронированный ближний бой | Skull Crack — периодический оглушающий удар |
| `enemy.summoner` | Troll Hexer | Призыватель | Call Bog Spawn; Bog Curse — враги рядом атакуют медленнее |
| `enemy.troll_priest` | Troll Witch Doctor | Поддержка | Лечение и яд |
| `enemy.ogre_bonebreaker` | Ogre Bonebreaker | Элитный прыгун | Bone-Breaking Leap — прыгает во вторую линию и оглушает |
| `enemy.troll_berserker` | Troll Berserker | Быстрый ближний бой | Troll Blood — регенерация от каждого полученного удара; Berserk |
| `enemy.bog_spawn` | Bog Spawn | Призыв Bog King и Troll Hexer | Rotten Burst — взрыв при смерти |
| `enemy.bog_king` | Mugrot the Bog King | Мини-босс (`BossDefinition`, 2 фазы) | Call of the Mire, Mire Slam, Ancient Troll Blood |
| `enemy.iron_warden` | The Iron Warden | Босс Act I | Iron Resolve — щит и броня при низком HP |

`enemy.summoned_brawler`, `enemy.summoned_shooter` и `enemy.summoned_amalgam` используются профессией Summoner игрока и не участвуют в Act I.

Замедляющие ауры атаки (`attack_speed_aura_effect`) не складываются: на юнита действует только самая сильная.

### Генератор контента и симулятор баланса

Враги, вражеские способности и все карты Act I генерируются скриптом `tools/balance/gen_act1_content.py` — все числа собраны в его таблицах `T` (способности), `S` (характеристики) и `ENC` (карты). После правки таблиц запустите `python3 tools/balance/gen_act1_content.py .` из корня проекта. Можно править и `.tres` напрямую в редакторе, но следующий запуск генератора перезапишет эти файлы.

`tools/balance/balance_sim.gd` проигрывает карты против синтетических армий нужной стадии забега (уровень героев, veterancy, профессии). Пример:

```
godot --headless --fixed-fps 60 --path . --script res://tools/balance/balance_sim.gd -- auto bog_king_court,war_drums 0 7 idx=mid
```

Аргументы: стадия (`auto` выбирает её по индексу боя), список карт или `all`, номер тройки героев, seed, затем необязательные `idx=min|mid|max|N`, `power=X`, `rp=X`, `abilities`. Каждая строка `SIM {...}` содержит победу, длительность, погибших солдат (`sd`) и героев (`hd`).
