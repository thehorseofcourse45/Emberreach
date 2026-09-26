extends AcceptDialog
## WelcomeBackModal — shows the offline-progression summary produced on load.

func _ready() -> void:
    title = "Welcome Back"
    ok_button_text = "Collect"
    EventBus.offline_progress_summary.connect(_on_summary)

func _on_summary(summary: Dictionary) -> void:
    if summary.is_empty():
        return
    var hours: float = float(summary.get("elapsed_seconds", 0.0)) / 3600.0
    var lines: Array[String] = []
    lines.append("You were away for %.1f hours." % hours)
    if summary.get("skill", "") != "":
        lines.append("%s: %d actions, %s XP" % [summary["skill"], int(summary.get("actions", 0)),
            TopBar._fmt(float(summary.get("xp_gained", 0.0)))])
    var combat: Dictionary = summary.get("combat", {})
    if int(combat.get("kills", 0)) > 0:
        lines.append("Combat: %d kills" % int(combat["kills"]))
    if int(summary.get("farming_advanced", 0)) > 0:
        lines.append("Farming: %d plots ready" % int(summary["farming_advanced"]))
    if int(summary.get("township_ticks", 0)) > 0:
        lines.append("Township: %d production ticks" % int(summary["township_ticks"]))
    dialog_text = "\n".join(lines)
    popup_centered()
