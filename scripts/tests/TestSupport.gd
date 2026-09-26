extends RefCounted
## TestSupport — file snapshot/restore and layout helpers shared by the suites.
## Deliberately no class_name: TestRunner loads it via preload, which keeps the
## global class table untouched and headless runs deterministic. All functions
## are static and touch only SaveManager, the filesystem and the scene tree.

## Snapshot the save files so a suite can restore them byte-for-byte after itself.
static func backup_save_files() -> Dictionary:
	var out: Dictionary = {}
	for path in [SaveManager.SAVE_PATH, SaveManager.BACKUP_PATH]:
		if FileAccess.file_exists(path):
			var f := FileAccess.open(path, FileAccess.READ)
			if f != null:
				out[path] = f.get_as_text()
				f.close()
			else:
				out[path] = null
		else:
			out[path] = null
	return out

## Put in-memory state and save files back exactly as they were found.
static func restore_snapshot(snapshot: Dictionary, files: Dictionary) -> void:
	# 1) Put the in-memory state back exactly as it was found.
	SaveManager._apply(snapshot)
	# 2) Put the save files back byte-for-byte, including "there was no save at all".
	for path in files.keys():
		var content: Variant = files[path]
		var abs_path: String = ProjectSettings.globalize_path(str(path))
		if content == null:
			if FileAccess.file_exists(str(path)):
				DirAccess.remove_absolute(abs_path)
			continue
		var f := FileAccess.open(str(path), FileAccess.WRITE)
		if f != null:
			f.store_string(str(content))
			f.close()
	SaveManager.last_outcome = SaveManager.LoadOutcome.NONE
	EventBus.state_refreshed.emit()
	print("test state restored: the player's save and progress are exactly as they were")

## Name the widest piece of a panel that will not fit, so a failure points at the row to fix
## rather than at the whole screen.
static func widest_descendant(root: Control) -> String:
	var worst: float = 0.0
	var worst_label: String = "none"
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		# Anything inside a scroll container is reachable by scrolling, so it cannot overflow.
		if node is ScrollContainer:
			continue
		for child in node.get_children():
			stack.append(child)
		if not (node is Control):
			continue
		# Name the row that sets the width: a vertical stack only inherits its widest child, so
		# reporting one would hide the actual offender.
		if node is VBoxContainer or node is MarginContainer or node is PanelContainer:
			continue
		var need: float = (node as Control).get_combined_minimum_size().x
		if need <= worst:
			continue
		worst = need
		worst_label = "%s '%s' in a %s at %dpx" % [node.get_class(), (node as Control).name,
			node.get_parent().get_class(), int(need)]
	return worst_label
