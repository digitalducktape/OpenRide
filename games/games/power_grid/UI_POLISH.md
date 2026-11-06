# Power Grid: UI polish punch list

From the UI review (ux-designer and ui-programmer passes) against `framework/ui/UI_STYLE.md` and Safe
Cracker's `UI_POLISH.md`, and wave A's review lessons. Captures as in `GFX_POLISH.md`.

**Identity:** arc blue `#8FD8FF` on dusk indigo `#151336`, skew 0.06 (`PowerGrid.look`).
**Hero:** the town itself, with the supply bar against its gold tick as the glance.

## What works

- One watts reading: the ride panel, through `set_power_source`. The bar has no number, and there are
  no "×" labels to compete with "Effort ×1.0".
- Pips carry state by shape as well as colour: a slash for dark, red for a downed line.
- The intro card: the valley's own render, each district's watts and the storm's, all from the params.
- The summary: town lit %, districts n/4, lines fixed n/m through `summary_stats`; no storm tile in
  an easy role.

## P0

1. [x] **Callouts over the town.** `GridBanner`: a centred lane over the sky, heavy outline, by
   priority, so news can't cut in on a storm's instruction. It follows the status widget down.
2. [x] **Callouts must say what to do.** Each carries a computed number: "Pedal to 126 W: stadium
   fading", "Line down! Hold 156 W for 10 s". The repair's watts are frozen at the warning.
3. [x] **WHOLE TOWN LIT showed while SHORT!** The note now reads CATCH UP as soon as a district dims.

## P1

4. [x] **Long callouts overflowed at 56 px.** 48 px, and shorter wording; `grid_layout_test` measures
   the longest at four-digit watts.
5. [x] **Text at 40 px or more** where it's the game's: the note 40, callouts 48, intro watts 44. The
   badge stays at the kit's 34.
6. [x] **An easy role needs a calm word.** Over the cap the badge reads EASY in blue, never amber
   alarm, and the note EASE OFF: NO NEED.

## Left

7. **Text isn't routed through `tr()` everywhere.** The other games' callouts aren't either.
8. **Keyboard and gamepad (ux-designer's checklist):** the game has no input of its own beyond the
   bike and the shared HUD buttons, so nothing to add.
