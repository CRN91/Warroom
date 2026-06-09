extends Node
class_name WeatherManager

## Owns everything calendar- and weather-related:
##   • the in-game date (each turn advances one week from a random spring start)
##   • the season derived from that date
##   • the current weather name + its modifier bundle
##
## Weather effects themselves are ordinary modifiers tagged "weather" living in
## ModifierManager — this class just manages their lifecycle, so a new weather
## front always replaces the previous one cleanly.

const MONTHS := ["January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December"]
const MONTH_DAYS := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

var weather_name: String = "clear"
var start_doy: int = 60        # day-of-year the run starts on
var day: int = 0               # current turn (1 turn == 1 week)

var _modifiers: ModifierManager

func setup(modifiers: ModifierManager) -> void:
	_modifiers = modifiers
	start_doy = randi_range(60, 151)   # Mar 1 .. May 31 — always a spring start
	Events.day_advanced.connect(func(d: int): day = d)

# ── Calendar ──────────────────────────────────────────────────────────────────

func current_doy() -> int:
	return (start_doy + day * 7) % 365

func current_season() -> String:
	var doy := current_doy()
	if doy < 60:  return "winter"            # Jan–Feb
	if doy < 152: return "spring"            # Mar–May
	if doy < 244: return "summer"            # Jun–Aug
	if doy < 335: return "autumn"            # Sep–Nov
	return "winter"                          # Dec

func date_string() -> String:
	var doy := current_doy()
	for m in range(12):
		if doy < MONTH_DAYS[m]:
			return "%s %d" % [MONTHS[m], doy + 1]
		doy -= MONTH_DAYS[m]
	return "December 31"

# ── Weather ───────────────────────────────────────────────────────────────────

func set_weather(name: String, modifier_bundles: Array = [], source: String = "") -> void:
	## Replaces the current weather. Each bundle is a normal modifier dictionary;
	## it gets force-tagged "weather" so the next front (or clear_weather) removes it.
	weather_name = name
	_modifiers.remove_by_tag("weather")
	for m in modifier_bundles:
		var mm: Dictionary = m.duplicate(true)
		var tags: Array = mm.get("tags", [])
		if not ("weather" in tags):
			tags.append("weather")
		mm["tags"] = tags
		if source != "" and not mm.has("source"):
			mm["source"] = source
		_modifiers.add_modifier(mm)
	Events.weather_changed.emit(weather_name)

func clear_weather() -> void:
	set_weather("clear")

func _check_expiry() -> void:
	## If every weather-tagged modifier has expired, the sky is clear again.
	if weather_name == "clear":
		return
	for m in _modifiers.mods:
		if "weather" in m.get("tags", []):
			return
	weather_name = "clear"
	Events.weather_changed.emit(weather_name)

func on_day_tick() -> void:
	## Called by TurnManager after modifiers.tick() so expired weather clears itself.
	_check_expiry()
