# Custom JSON-Based Localization System Setup Guide

This guide walks through configuring and using the custom JSON-based localization system in your Godot 4.x project.

---

## 1. Register the Autoload Singleton

To make `LocalizationManager` globally accessible across all scenes and scripts:

1. Open your Godot project.
2. Navigate to **Project** -> **Project Settings** -> **Autoload** tab.
3. Click the folder icon next to **Path** and select [localization_manager.gd](file:///d:/GoDot/valkyrious-revive/scripts/core/localization_manager.gd).
4. Set the **Node Name** to `LocalizationManager`.
5. Click **Add** to register it. Make sure the **Enabled** checkbox is checked.

---

## 2. Structure of JSON Translation Files

All translation files must be placed under `res://data/localization/` directory.

### Example: English (`res://data/localization/en.json`)
```json
{
	"UI_BATTLE": "Battle",
	"UI_COLLECTION": "Collection",
	"UI_SETTINGS": "Settings",
	"UI_SHOP": "Shop",
	"UI_DECK": "Deck",
	"UI_RECORDS": "Records",
	"UI_GACHA": "Gacha"
}
```

### Example: Thai (`res://data/localization/th.json`)
```json
{
	"UI_BATTLE": "ต่อสู้",
	"UI_COLLECTION": "คอลเลกชัน",
	"UI_SETTINGS": "ตั้งค่า",
	"UI_SHOP": "ร้านค้า",
	"UI_DECK": "ทีม",
	"UI_RECORDS": "บันทึก",
	"UI_GACHA": "Gacha"
}
```

---

## 3. UI Integration with `LocalizedLabel`

The `LocalizedLabel` component automatically updates its text property to display the translation matching the active language setting.

### How to use in the Editor:
1. Create a Label node in a scene.
2. Right-click the node and select **Change Type**, then select `LocalizedLabel`.
3. In the Inspector, set the **Localize Key** property (e.g. `UI_BATTLE`).
4. The label's text will immediately update to preview the key in the editor workspace, and will dynamically fetch the translation at runtime.

---

## 4. Resource Integration (Cards / Skills / Units)

Future character and skill resource files (`.tres`) should never store raw localized text. Instead, they must store localization keys which are resolved dynamically by the UI layer using `LocalizationManager.get_text()`.

### Example script:
```gdscript
extends Resource
class_name CharacterStat

@export var card_id: String = ""
@export var name_key: String = ""
@export var description_key: String = ""
```

### Rendering in UI code:
```gdscript
func update_card_display(card: CharacterStat) -> void:
	# Resolve translated card name and description
	name_label.text = LocalizationManager.get_text(card.name_key)
	desc_label.text = LocalizationManager.get_text(card.description_key)
```

---

## 5. Runtime Language Switching

To toggle or switch languages programmatically:

```gdscript
# Switch to Thai
LocalizationManager.set_language("th")

# Switch to English
LocalizationManager.set_language("en")

# Get currently active language code
var active_lang := LocalizationManager.get_current_language()
```

When the language switches, all `LocalizedLabel` nodes in the active scene tree automatically refresh their text immediately.

---

## 6. Language Preference Caching

Language preferences are automatically saved on change and loaded on startup using Godot's `ConfigFile` API. The user settings are cached inside:
`user://localization_settings.cfg`

If no settings file exists, the system defaults to English (`"en"`).
