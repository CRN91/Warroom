@tool
extends EditorScript

## Generates a textured, pointy-top pixel hex tile and saves it as a PNG.
## HOW TO RUN: open in the Script editor, then File > Run (Ctrl+Shift+X).
##
## WHY 50×58: at game zoom the board shows each hex ~50px wide, so this size
## puts ~1 art pixel on ~1 screen pixel — every speckle you add is actually
## visible. (Bigger canvases get mipmap-averaged into flat color.)
## WHY POINTY-TOP: the grid's cells are 500×580 — points up/down, flat sides
## left/right. Flat-top art lands its borders nowhere near the cell edges.

const W := 50                           # native width  (50 : 58 ≈ √3/2 — true pointy hex)
const H := 58                           # native height
const BORDER := 2.0                     # px; 0 = borderless
const FILL := Color8(135, 150, 166)     # fallback if MATCH_PATH can't be sampled
const BORDER_COL := Color8(40, 40, 40)  # plain dark grey
const OUT_PATH := "res://assets/bluehex.png"

# Sample the base color from an existing tile so palettes stay consistent.
const MATCH_PATH := ""                  # e.g. "res://assets/bluehex_borderless.png"

# Texture: sparse single-pixel speckles, light and dark. At 50×58 each one is
# ~1 screen pixel — visible but quiet. Raise density/strength for more grit.
const SPECKLE_DENSITY := 0.05           # fraction of fill pixels speckled
const SPECKLE_STRENGTH := 0.10          # max brightness shift (0..1)
const SEED := 1337                      # change for a different speckle pattern

func _run() -> void:
	var fill := FILL
	if MATCH_PATH != "" and ResourceLoader.exists(MATCH_PATH):
		var tex: Texture2D = load(MATCH_PATH)
		var src: Image = tex.get_image() if tex != null else null
		if src != null and not src.is_empty():
			if src.is_compressed(): src.decompress()
			fill = src.get_pixel(src.get_width() / 2, src.get_height() / 2)
			print("Sampled fill %s from %s" % [fill, MATCH_PATH])

	var rng := RandomNumberGenerator.new()
	rng.seed = SEED

	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)

	var a := W / 2.0                   # half-width  (distance to the flat sides)
	var r := H / 2.0                   # half-height (distance to the top/bottom points)
	var slope := (r / 2.0) / a         # slant of the four diagonal edges
	var n := sqrt(slope * slope + 1.0) # normal length, for true perpendicular distance

	for y in range(H):
		for x in range(W):
			var dx := absf(x + 0.5 - a)
			var dy := absf(y + 0.5 - r)
			var d_side := a - dx                          # vertical edges
			var d_slant := (r - dy - slope * dx) / n      # diagonal edges
			var d := minf(d_side, d_slant)

			if d < 0.0:
				continue                                  # outside: transparent
			if d < BORDER:
				img.set_pixel(x, y, BORDER_COL)
				continue

			var c := fill
			if rng.randf() < SPECKLE_DENSITY:
				var shift := rng.randf_range(-SPECKLE_STRENGTH, SPECKLE_STRENGTH)
				c = Color(clampf(c.r + shift, 0, 1), clampf(c.g + shift, 0, 1),
					clampf(c.b + shift, 0, 1), 1.0)
			img.set_pixel(x, y, c)

	img.save_png(ProjectSettings.globalize_path(OUT_PATH))
	print("Wrote %s (%d x %d)" % [OUT_PATH, img.get_width(), img.get_height()])
	EditorInterface.get_resource_filesystem().scan()
