extends Node
## ArchaeologyManager — tracks excavation and the museum. Dig-site artefacts drop through
## the normal action loot path; donating them here rewards GP and raises completion.

const DONATE_GP := {"artefact_common": 100, "artefact_uncommon": 500, "artefact_rare": 2500, "artefact_unique": 15000}

var excavated: Dictionary = {}   # site_id -> count
var donated: Dictionary = {}     # artefact_id -> count

func get_site(site_id: String) -> Dictionary:
    return DataLoader.archaeology_sites.get(site_id, {})

## Called by SkillManager after a successful archaeology action.
func on_excavate(site_id: String) -> void:
    excavated[site_id] = int(excavated.get(site_id, 0)) + 1

func donate(artefact_id: String) -> bool:
    if not BankManager.has_item(artefact_id, 1):
        return false
    if not DONATE_GP.has(artefact_id):
        return false
    BankManager.remove_item(artefact_id, 1)
    donated[artefact_id] = int(donated.get(artefact_id, 0)) + 1
    PlayerData.add_gp(float(DONATE_GP[artefact_id]))
    EventBus.notification.emit("Donated %s to the museum" % artefact_id, "success")
    return true

func total_donated() -> int:
    var n: int = 0
    for k in donated.keys():
        n += int(donated[k])
    return n

func serialize() -> Dictionary:
    return {"excavated": excavated, "donated": donated}

func deserialize(d: Dictionary) -> void:
    excavated = d.get("excavated", {})
    donated = d.get("donated", {})
