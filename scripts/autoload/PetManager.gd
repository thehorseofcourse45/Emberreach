extends Node
## PetManager — rare passive unlocks. A pet is rolled while training its source skill
## (or in combat for combat pets) and, once unlocked, registers a permanent modifier source.

const CATEGORY: String = "pet"
const SKILL_PET_CHANCE: float = 0.004
const COMBAT_PET_CHANCE: float = 0.003

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
    _rng.randomize()
    EventBus.game_loaded.connect(_reapply)

func is_unlocked(pet_id: String) -> bool:
    return PlayerData.unlocked_pets.has(pet_id)

## Four training seconds equal one historical roll; collecting/logging in cannot alter odds.
func skill_roll_chance(training_seconds: float) -> float:
    if not is_finite(training_seconds) or training_seconds <= 0: return 0.0
    return 1.0 - pow(1.0 - SKILL_PET_CHANCE, training_seconds / 4.0)

func roll_for_skill(_skill_id: String, training_seconds: float = 4.0) -> void:
    if _rng.randf() > skill_roll_chance(training_seconds):
        return
    var pool: Array = []
    for pid in DataLoader.pets.keys():
        if DataLoader.pets[pid].get("source_skill", "") == _skill_id and not is_unlocked(pid):
            pool.append(pid)
    if not pool.is_empty():
        unlock(pool[_rng.randi_range(0, pool.size() - 1)])

func roll_for_combat() -> void:
    if _rng.randf() > COMBAT_PET_CHANCE:
        return
    var pool: Array = []
    for pid in DataLoader.pets.keys():
        if DataLoader.pets[pid].get("source_skill", "") == "combat" and not is_unlocked(pid):
            pool.append(pid)
    if not pool.is_empty():
        unlock(pool[_rng.randi_range(0, pool.size() - 1)])

## A pet can hang off a skill roll or a combat kill, or off clearing an expedition. The third
## form is the only path the two endgame companions have, so it hangs off the existing
## dungeon_completed site — no new event, no new bus.
func on_dungeon_cleared(dungeon_id: String) -> void:
    for pid in DataLoader.pets.keys():
        var p: Dictionary = DataLoader.pets[pid]
        if str(p.get("source_dungeon", "")) == dungeon_id and not is_unlocked(pid):
            unlock(pid)

func unlock(pet_id: String) -> void:
    if is_unlocked(pet_id):
        return
    PlayerData.unlock_pet(pet_id)
    _register(pet_id)
    EventBus.notification.emit("Pet unlocked: %s" % DataLoader.pets.get(pet_id, {}).get("name", pet_id), "success")

func _register(pet_id: String) -> void:
    var eff: Dictionary = DataLoader.pets.get(pet_id, {}).get("effect", {})
    if not eff.is_empty():
        ModifierManager.register("%s:%s" % [CATEGORY, pet_id], eff, CATEGORY, DataLoader.pets[pet_id].get("name", pet_id))

func _reapply() -> void:
    for pet_id in PlayerData.unlocked_pets:
        _register(pet_id)

func serialize() -> Dictionary:
    return {"pets": PlayerData.unlocked_pets}

func deserialize(_d: Dictionary) -> void:
    _reapply()
