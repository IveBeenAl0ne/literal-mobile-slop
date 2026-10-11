@tool
extends SceneTree
# Configure editor SDK paths with env vars; never write credentials into the repository.
func _initialize():
	var settings = EditorInterface.get_editor_settings()
	if not OS.get_environment("JAVA_HOME").is_empty():
		settings.set_setting("export/android/java_sdk_path", OS.get_environment("JAVA_HOME"))
	if not OS.get_environment("ANDROID_HOME").is_empty():
		settings.set_setting("export/android/android_sdk_path", OS.get_environment("ANDROID_HOME"))
	settings.set_setting("export/android/debug_keystore", OS.get_environment("TYCOON_DEBUG_KEYSTORE"))
	var preset = ConfigFile.new()
	preset.load("res://export_presets.cfg")
	var team = OS.get_environment("IOS_TEAM_ID")
	if not team.is_empty(): preset.set_value("preset.1.options", "application/app_store_team_id", team)
	preset.save("res://export_presets.cfg")
	call_deferred("finish")

func finish():
	await process_frame
	await process_frame
	quit()
