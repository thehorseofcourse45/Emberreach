extends ConfirmationDialog
class_name ConfirmDialog
## ConfirmDialog — one shared confirmation flow.
##
## Used only for genuinely consequential or irreversible actions (selling everything, resetting a
## save, discarding a loadout). Ordinary actions never raise a modal; they act and report through
## a toast. This is the brief's "avoid disruptive modals for ordinary actions" made concrete.

## Show a confirmation. `on_confirm` receives nothing; close behaviour is handled here.
static func ask(parent: Node, title: String, body: String, confirm_text: String,
		on_confirm: Callable, destructive := false, extra_note := "") -> ConfirmDialog:
	var dlg := ConfirmDialog.new()
	dlg.title = title
	dlg.dialog_text = body if extra_note == "" else "%s\n\n%s" % [body, extra_note]
	dlg.ok_button_text = confirm_text
	dlg.cancel_button_text = "Cancel"
	dlg.dialog_autowrap = true
	dlg.min_size = Vector2i(420, 0)
	dlg.confirmed.connect(func():
		if on_confirm.is_valid():
			on_confirm.call()
		dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	parent.add_child(dlg)
	if destructive:
		var ok: Button = dlg.get_ok_button()
		ok.add_theme_color_override("font_color", UITokens.RED)
	dlg.popup_centered()
	# Keyboard focus lands on Cancel for destructive actions so Enter cannot destroy data.
	if destructive:
		dlg.get_cancel_button().grab_focus()
	else:
		dlg.get_ok_button().grab_focus()
	return dlg

## Preview a multi-entry transaction (bulk sale) before committing.
static func ask_bulk_sale(parent: Node, entries: Array, on_confirm: Callable) -> void:
	var lines: Array[String] = []
	var total: float = 0.0
	for item_id in entries:
		var preview: Dictionary = BankManager.sell_preview(str(item_id), -1)
		if int(preview["quantity"]) <= 0:
			continue
		lines.append("  %s ×%s — %s GP" % [str(preview["name"]),
			UIStyle.fmt_exact(float(preview["quantity"])), UIStyle.fmt(float(preview["gp_gained"]))])
		total += float(preview["gp_gained"])
	if lines.is_empty():
		EventBus.notify("Nothing to sell.", "info")
		return
	if lines.size() > 18:
		lines = lines.slice(0, 18)
		lines.append("  …and more")
	ask(parent, "Sell everything?",
		"\n".join(lines) + "\n\nTotal: %s GP" % UIStyle.fmt(total),
		"Sell all", on_confirm, true,
		"Protected items are skipped. This cannot be undone.")
