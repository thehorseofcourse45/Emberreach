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

func roll_for_skill(_skill_id: String) -> void:
    if _rng.randf() > SKILL_PET_CHANCE:
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
