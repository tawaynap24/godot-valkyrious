@tool
extends Label
class_name LocalizedLabel

## Reusable LocalizedLabel component that automatically updates its text
## based on the exported localize_key.

@export var localize_key: String = "":
	set(val):
		localize_key = val
		_update_text()

func _ready() -> void:
	if not Engine.is_editor_hint():
		var ls = get_node_or_null("/root/LocalizationSettings")
		if ls:
			ls.language_changed.connect(_on_language_changed)
	
	_update_text()

func _update_text() -> void:
	if localize_key == "":
		return
		
	# In editor preview, show key name itself (since singleton doesn't exist in editor context)
	if Engine.is_editor_hint():
		text = localize_key
		return
		
	# At runtime, use native tr()
	text = tr(localize_key)

func _on_language_changed(_new_lang: String) -> void:
	_update_text()

