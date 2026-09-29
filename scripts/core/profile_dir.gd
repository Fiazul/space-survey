class_name ProfileDir
extends RefCounted
## Where player state lives: user:// unless ASTRYX_PROFILE_DIR points elsewhere.
## Tools that boot the real main call isolate() first, so a bare test run can
## never overwrite the live save (it did, twice, on 2026-09-29).
const ENV := "ASTRYX_PROFILE_DIR"

static func path(file: String) -> String:
	var dir := OS.get_environment(ENV)
	if dir.is_empty():
		return "user://".path_join(file)
	DirAccess.make_dir_recursive_absolute(dir)
	return dir.path_join(file)

# Default a tool run to a scratch profile named after the tool, unless the
# caller already chose one. Returns the directory in use.
static func isolate(tag: String) -> String:
	if OS.get_environment(ENV).is_empty():
		var base := OS.get_environment("TMPDIR")
		OS.set_environment(ENV, (base if not base.is_empty() else "/tmp").path_join("astryx_profile_%s" % tag))
	return OS.get_environment(ENV)
