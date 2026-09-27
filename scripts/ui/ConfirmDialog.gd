extends ConfirmationDialog
class_name ConfirmDialog
## ConfirmDialog — one shared confirmation flow.
##
## Used only for genuinely consequential or irreversible actions (selling everything, resetting a
## save, discarding a loadout). Ordinary actions never raise a modal; they act and report through
## a toast. This is the brief's "avoid disruptive modals for ordinary actions" made concrete.
##
## It also hosts the activity-event CARD (ask_event, Task 6 of the activity plan): the same
## chrome, but the event's own two choices ARE the buttons and a timeout bar drains with the
## pending card's own timer.

## Live state for an open event card. The bar POLLS EventDirector.pending_card's timer — the game
## clock the watchdog runs on — instead of animating independently, so it cannot disagree with
## the state that will actually resolve the card.
var _event_bar: ProgressBar = null
var _event_id: String = ""

func _process(_delta: float) -> void:
	if _event_bar == null:
		set_process(false)
		return
	if EventDirector.pending_card.is_empty():
		return   # resolved elsewhere; the offer's owner closes this dialog on event_resolved
	_event_bar.value = clampf(
		float(EventDirector.pending_card.get("timer", 0.0)) / EventDirector.CARD_TIMEOUT_SECONDS,
		0.0, 1.0) * 100.0

## Show a confirmation. `on_confirm` receives nothing; close behaviour is handled here.
static func ask(parent: Node, dialog_title: String, body: String, confirm_text: String,
		on_confirm: Callable, destructive := false, extra_note := "") -> ConfirmDialog:
	var dlg := ConfirmDialog.new()
	dlg.title = dialog_title
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

## Show an ACTIVITY EVENT card (data/events.json) — Task 6 of the activity plan. Reuses this
## dialog's chrome with the event's own title/text, its TWO choices as the buttons, and a
## timeout bar wired to the pending card's timer.
## Button semantics, deliberately: choice 0 rides OK (Enter + initial focus take it), choice 1 is
## an extra right-hand button, and the built-in Cancel is HIDDEN — dismissing the dialog (X, Esc)
## is NOT a third choice but resolves through EventDirector's TIMEOUT path, the same one the
## CARD_TIMEOUT_SECONDS watchdog fires, so a walk-away applies the stored policy and the loop
## never stays paused behind a closed window.
## dialog_text stays EMPTY on purpose: AcceptDialog gives EVERY custom child the same full
## content rect (they would overlap the internal label), so the text and the bar live together
## in one composed VBox instead.
static func ask_event(parent: Node, event: Dictionary) -> ConfirmDialog:
	var dlg := ConfirmDialog.new()
	dlg.title = str(event.get("title", "Event"))
	var choices: Array = event.get("choices", []) if typeof(event.get("choices", [])) == TYPE_ARRAY else []
	# Choice 0 rides the OK button: visible, focused, Enter takes it.
	if not choices.is_empty() and typeof(choices[0]) == TYPE_DICTIONARY:
		var first: Dictionary = choices[0]
		dlg.ok_button_text = str(first.get("label", "First choice"))
		dlg.confirmed.connect(func(): _resolve_and_close(dlg, event, str(first.get("policy", ""))))
	# Choice 1 as a custom right-hand button.
	if choices.size() > 1 and typeof(choices[1]) == TYPE_DICTIONARY:
		var second: Dictionary = choices[1]
		var extra := dlg.add_button(str(second.get("label", "Second choice")), true, "event_choice_1")
		extra.pressed.connect(_resolve_and_close.bind(dlg, event, str(second.get("policy", ""))))
	# No hidden third option: X and Esc still resolve — through the TIMEOUT path below.
	dlg.get_cancel_button().hide()
	dlg.canceled.connect(func(): _resolve_and_close(dlg, event, "TIMEOUT"))
	dlg.min_size = Vector2i(420, 0)
	# Composed content: the card's text over the timeout bar (see the note about content rects).
	var content := UIStyle.vbox(UITokens.SP_3)
	var text_label := UIStyle.label(str(event.get("text", "")), false, UITokens.FONT_SMALL)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(text_label)
	content.add_child(Widgets.progress_bar(100.0, 100.0, UITokens.AMBER, "", 6,
		"Resolves itself in %d seconds if you walk away" % int(EventDirector.CARD_TIMEOUT_SECONDS)))
	dlg.add_child(content)
	dlg._event_bar = content.get_child(1) as ProgressBar
	dlg._event_id = str(event.get("id", ""))
	dlg.set_process(true)
	parent.add_child(dlg)
	dlg.popup_centered()
	return dlg

## One resolution path for buttons AND the timeout: EventDirector.resolve applies the choice,
## clears the pending card and releases the pause; the event_resolved it emits also reaches the
## strip's listener, which closes this dialog again — queue_free is idempotent, so double-close
## from the two owners is safe.
static func _resolve_and_close(dlg: ConfirmDialog, event: Dictionary, policy: String) -> void:
	EventDirector.resolve(event, policy)
	if is_instance_valid(dlg):
		dlg.hide()
		dlg.queue_free()
