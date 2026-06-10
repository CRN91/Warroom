# Next session — state & first steps

## Where things stand after the git reset

Your reset kept all the SYSTEMS from this session (they were pushed):
line of control + pockets + sieges, artillery setup/deploy, rotation +
garrison rest, engineer shuttle routes, partisan harassment, coalition
endgame with two victory paths, alliances (orange team 3), damage pass.

The reset wiped only the late visual fixes. Two have been re-applied just now:

1. **Grid._fit_tile_art** — tile pngs at ANY size now render (upscaled to the
   cell; silently-dropped tiles recreated). Every "tile is set but nothing
   shows" incident was Godot dropping the tile because the declared region
   (500×580) was bigger than the png. This function is the permanent cure.
2. **ControlMap multiply blending** — territory tint darkens/casts the tile
   art instead of painting over it. Constants at top of control_map.gd;
   1.0 per channel = untouched, lower = darker.

NOT re-applied (was also wiped, re-add if wanted): the C-key display cycle
for the control layer (tints+line / line only / hidden).

## First 10 minutes next session

1. Run the game. If the board renders and the front line draws — good,
   baseline restored.
2. "Front line not working": if it persists, check ControlMap is in game.tscn
   (node after Grid, z_index -2, script control_map.gd) and that Game.gd calls
   control_map.setup(s) and TurnManager calls s.control.weekly_update().
   The reset may have left game.tscn at an older revision than the scripts.
3. Commit immediately once it boots clean, so there's a known-good point.

## The tile art rules (hard-won, don't relearn them)

- Grid is POINTY-TOP: points up/down. Cell 500×580. Author hexes pointy-top.
- Author tile art at **50×58** — at game zoom that's ~1 art px per screen px,
  so single-pixel texture detail is actually visible. Bigger canvases get
  mipmap-averaged into flat color at this zoom (your 500×500 grass tile WAS
  rendering — its detail just averaged away, and its flat-top borders didn't
  line up with the cell edges).
- Side corners of the pointy hex sit at 1/4 and 3/4 of the height.
- Overwrite assets/bluehex.png to iterate; rename files only inside the Godot
  FileSystem dock (Explorer renames caused the .png.png and dangling-path bugs).
- tools/hex_tile_generator.gd (if kept) bakes a bordered + speckled tile at
  the right size/orientation; constants at the top.

## Balance watchpoints from the last playable build

- Coalition landfall week 52 vs typical run length (~36) — consider 40-44.
- Town income 5/wk with capital 80/wk — verify hauling feels necessary but
  not tedious; engineer shuttle routes ("Set Route") are the antidote.
- Artillery 30 dmg + setup turn — check defense actually holds a line now.
