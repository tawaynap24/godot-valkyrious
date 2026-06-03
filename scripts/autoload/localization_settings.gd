extends Node

# ─────────────────────────────────────────────────────────────────────────────
# LocalizationSettings — lightweight singleton for managing Godot's locale.
# ─────────────────────────────────────────────────────────────────────────────

signal language_changed(language_code: String)

const CONFIG_PATH: String = "user://settings.cfg"
const DEFAULT_LANGUAGE: String = "en"

var _current_language: String = DEFAULT_LANGUAGE

func _ready() -> void:
	load_language()

## Sets the active language code, updates Godot's locale, saves the setting, and notifies listeners.
func set_language(language_code: String) -> void:
	if language_code != "en" and language_code != "th":
		push_warning("[LocalizationSettings] Unsupported language code '%s'. Defaulting to '%s'." % [language_code, DEFAULT_LANGUAGE])
		language_code = DEFAULT_LANGUAGE
		
	_current_language = language_code
	TranslationServer.set_locale(language_code)
	save_language()
	language_changed.emit(language_code)
	print("[LocalizationSettings] Language set to: ", language_code)

## Returns the current active language code.
func get_language() -> String:
	return _current_language

## Saves the selected language code to ConfigFile.
func save_language() -> void:
	var config := ConfigFile.new()
	# Load existing config to not overwrite other settings
	if FileAccess.file_exists(CONFIG_PATH):
		config.load(CONFIG_PATH)
		
	config.set_value("localization", "language", _current_language)
	var err := config.save(CONFIG_PATH)
	if err != OK:
		push_error("[LocalizationSettings] Failed to save settings. Error: ", err)

## Loads the selected language code from ConfigFile at startup, defaulting to English.
func load_language() -> void:
	var config := ConfigFile.new()
	var err := config.load(CONFIG_PATH)
	var lang := DEFAULT_LANGUAGE
	
	if err == OK:
		lang = str(config.get_value("localization", "language", DEFAULT_LANGUAGE))
		
	set_language(lang)
