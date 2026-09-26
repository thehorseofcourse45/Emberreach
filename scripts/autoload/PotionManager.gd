extends Node
## PotionManager — active potion with charge-based consumption.
## The equipped potion registers its `potion_effect` as a ModifierSource in the
## "potion" category; charges decrement per completed action and the potion clears at 0.

const CATEGORY: String = "potion"
const SOURCE_ID: String = "potion:active"

func _ready() -> void:
    EventBus.game_loaded.connect(_reapply)

## Charge consumption is called explicitly from the authoritative simulation
## (SkillManager.perform_action and CombatManager._player_attack) rather than from bus
## signals, because signals are suppressed during the silent offline catch-up. Wiring it to
## signals previously made a potion last forever while the player was offline.

func get_potion(item_id: String) -> Dictionary:
    return DataLoader.get_item(item_id)

## Drink a potion from the bank and make it active.
func use_potion(item_id: String) -> bool:
    var def: Dictionary = get_potion(item_id)
    if def.get("item_type", "") != "potion":
        return false
    if not BankManager.has_item(item_id, 1):
        EventBus.notification.emit("No %s in bank" % def.get("name", item_id), "warn")
        return false
    BankManager.remove_item(item_id, 1)
    clear()
    PlayerData.active_potion = item_id
    PlayerData.potion_charges = int(def.get("charges", 0))
    _register(item_id)
    EventBus.notification.emit("Activated %s (%d charges)" % [def.get("name", item_id), PlayerData.potion_charges], "success")
    return true

## Consume one charge; clears the potion when it runs out.
func consume_charge() -> void:
    if PlayerData.active_potion == "":
        return
    PlayerData.potion_charges -= 1
    if PlayerData.potion_charges <= 0:
        var name: String = get_potion(PlayerData.active_potion).get("name", PlayerData.active_potion)
        clear()
        EventBus.notification.emit("%s expired" % name, "info")

func clear() -> void:
    ModifierManager.unregister(SOURCE_ID)
    PlayerData.active_potion = ""
    PlayerData.potion_charges = 0

func is_active() -> bool:
    return PlayerData.active_potion != ""

func _register(item_id: String) -> void:
    var def: Dictionary = get_potion(item_id)
    var effect: Dictionary = def.get("potion_effect", {})
    if not effect.is_empty():
        ModifierManager.register(SOURCE_ID, effect, CATEGORY, def.get("name", item_id))

## Re-assert the active potion's modifier source after a load.
func _reapply() -> void:
    if PlayerData.active_potion != "":
        _register(PlayerData.active_potion)
