# Translation Key Guidelines

This document outlines the naming conventions, organization, and guidelines for Valkyrious Revive's localization keys.

## Naming Conventions

All translation keys must be **capitalized** and use **underscores** to separate words. Keys are grouped by category prefixes.

| Category | Prefix | Description | Example |
| :--- | :--- | :--- | :--- |
| **UI Text** | `UI_` | Buttons, screen titles, static labels, headers, and UI messages | `UI_CANCEL`, `UI_DECK_BUILDER` |
| **Characters/Cards** | `CHAR_` | Character and card names, plus their background descriptions | `CHAR_ANGE_NAME`, `CHAR_ANGE_DESC` |
| **Skills** | `SKILL_` | Card skill names and their level-scaled description templates | `SKILL_DEATH_BURST_NAME`, `SKILL_DEATH_BURST_DESC` |
| **Error Messages** | `ERROR_` | Network errors, input validation errors, and alert messages | `ERROR_CONNECTION_LOST`, `ERROR_INVALID_NAME` |

## Design Rules

1. **Do NOT Use Visible Text As Keys**:
   * *Bad*: `tr("Battle")`
   * *Good*: `tr("UI_BATTLE")`
2. **Never Store Localized Text Directly in Resources**:
   * Always export `name_key: String` and `description_key: String` in Resources (like `CharacterStat` or `CharacterSkill`).
   * Store only the stable capitalized keys (e.g. `CHAR_FATIMA_NAME`) in the `.tres` files.
3. **Use Format Specifiers for Dynamic Content**:
   * Support dynamic data formatting (e.g. `Must have exactly %d characters to save` -> `UI_DECK_LIMIT_WARNING`).
   * When loading, translate the template key first, then inject arguments:
     ```gdscript
     label.text = tr("UI_DECK_LIMIT_WARNING") % limit_count
     ```

## Adding New Content

### 1. Adding a New UI Element
1. Define a unique, descriptive uppercase key prefixed with `UI_` (e.g., `UI_CONFIRM_DELETE`).
2. Add the key and its translated values to `res://data/localization/translations.en.csv` and `res://data/localization/translations.th.csv`.
3. In your scene, use a `LocalizedLabel` node with `localize_key = "UI_CONFIRM_DELETE"`, or in script use `tr("UI_CONFIRM_DELETE")`.

### 2. Adding a New Card / Character
1. Open/create your character's `CharacterStat` `.tres` resource.
2. In the inspector:
   * Set `Name Key` to `CHAR_[ID]_NAME` (e.g., `CHAR_HERCULES_NAME`).
   * Set `Description Key` to `CHAR_[ID]_DESC` (e.g., `CHAR_HERCULES_DESC`).
3. Add the keys and translation strings to both CSV files.

### 3. Adding a New Language
1. Create a new CSV file under `res://data/localization/` named `translations.[locale].csv` (e.g. `translations.ja.csv` for Japanese).
2. The header must be `keys,[locale]` (e.g. `keys,ja`).
3. Copy all keys from `translations.en.csv` and translate their values.
4. Register the compiled path (e.g., `res://data/localization/translations.ja.ja.translation`) in the `locale/translations` array in `project.godot`.

## Validation

Before submitting any translation edits, run the validation tool headlessly to catch missing keys, empty values, or duplicates:
```powershell
D:\GoDot\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe --headless --path . -s res://data/localization/translation_validator.gd
```
