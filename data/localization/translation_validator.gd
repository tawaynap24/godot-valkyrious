extends SceneTree

const EN_CSV_PATH = "res://data/localization/translations.en.csv"
const TH_CSV_PATH = "res://data/localization/translations.th.csv"

func _init() -> void:
	print("--- Starting Localization Validation Tool ---")
	
	var en_keys_dict = _parse_csv_for_validation(EN_CSV_PATH)
	var th_keys_dict = _parse_csv_for_validation(TH_CSV_PATH)
	
	if en_keys_dict.is_empty() or th_keys_dict.is_empty():
		print("[ERROR] Could not parse translation CSVs correctly.")
		quit(1)
		return
		
	var has_warnings = false
	
	# Check for duplicates & empty values in EN
	var en_keys = en_keys_dict.keys()
	var th_keys = th_keys_dict.keys()
	
	print("\n--- Checking Empty Translations ---")
	for k in en_keys:
		if en_keys_dict[k].strip_edges() == "":
			print("[WARNING] Key '%s' has an empty translation in English." % k)
			has_warnings = true
			
	for k in th_keys:
		if th_keys_dict[k].strip_edges() == "":
			print("[WARNING] Key '%s' has an empty translation in Thai." % k)
			has_warnings = true
			
	print("\n--- Checking Missing Keys (Cross-Locale consistency) ---")
	var missing_in_th = []
	for k in en_keys:
		if not th_keys_dict.has(k):
			missing_in_th.append(k)
			
	var missing_in_en = []
	for k in th_keys:
		if not en_keys_dict.has(k):
			missing_in_en.append(k)
			
	if not missing_in_th.is_empty():
		print("[WARNING] The following keys exist in English but are MISSING in Thai:")
		for k in missing_in_th:
			print("  - ", k)
		has_warnings = true
		
	if not missing_in_en.is_empty():
		print("[WARNING] The following keys exist in Thai but are MISSING in English:")
		for k in missing_in_en:
			print("  - ", k)
		has_warnings = true
		
	if not has_warnings:
		print("[SUCCESS] No duplicate, missing, or empty keys detected! Translation files are clean and consistent.")
		quit(0)
	else:
		print("\n[FINISHED] Validation finished with warnings/errors.")
		quit(1)

func _parse_csv_for_validation(path: String) -> Dictionary:
	var dict = {}
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("[ERROR] Failed to open: ", path)
		return dict
		
	# read header
	var header = file.get_line()
	var line_num = 1
	var duplicates = []
	
	while not file.eof_reached():
		line_num += 1
		var line = file.get_line().strip_edges()
		if line == "":
			continue
			
		var key = ""
		var val = ""
		
		# Parse simple CSV line of format "key","value"
		if line.begins_with("\"") and line.ends_with("\""):
			var content = line.substr(1, line.length() - 2)
			var parts = content.split("\",\"")
			if parts.size() >= 2:
				key = parts[0]
				val = parts[1]
			else:
				var split_idx = content.find("\",\"")
				if split_idx != -1:
					key = content.substr(0, split_idx)
					val = content.substr(split_idx + 3)
		else:
			var comma_idx = line.find(",")
			if comma_idx != -1:
				key = line.substr(0, comma_idx).strip_edges().trim_prefix("\"").trim_suffix("\"")
				val = line.substr(comma_idx + 1).strip_edges().trim_prefix("\"").trim_suffix("\"")
				
		if key != "":
			if dict.has(key):
				duplicates.append([key, line_num])
			else:
				dict[key] = val
				
	file.close()
	
	if not duplicates.is_empty():
		print("[WARNING] Duplicate keys detected in file '%s':" % path)
		for dup in duplicates:
			print("  - Key: '%s' on line: %d" % [dup[0], dup[1]])
			
	return dict
