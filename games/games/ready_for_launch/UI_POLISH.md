# Ready for Launch: UI polish punch list

From the UI review of 2026-11-06 (ux-designer and ui-programmer passes), against
`framework/ui/UI_STYLE.md` and Safe Cracker's `UI_POLISH.md`, judged at half size.

**Identity:** mission teal `#2FD6C8` on deep night navy `#0A1A2E`, badges leaning 0.1, the face upright.

## What works

- The status widget changes with the phase: the tank, then the climb, one word on its chip.
- The mission clock is in the world, so the HUD stays slim, and it scrolls away with the ground.
- Watts show once, in the ride panel, from the rules (`set_power_source`), with the gold mark on what
  this phase asks for: the fill line, then the push target, then nothing.
- The intro card: a small scene with the real rocket, and the three steps with computed seconds and
  watts, all at 40 px or more.

## P0

1. [x] **Callouts ran past the lane and under the ride panel.** The panel is 338 px tall with the
   effort row. **Done:** a lane from x 640 to 1450, 48 px, 14 px ink outline; the longest texts are
   measured in `launch_scene_test`.
2. [x] **No "×" beside "Effort ×1.0".** The tank is a percentage and the climb kilometres (tested).
3. [x] **Nothing clipped by a panel.** Clock, tower and rocket tested at their tallest.

## P1

4. [x] **Milestone callouts said where you were, not what next.** **Done:** "Clouds! Next stop 100 km".
5. [x] **A rider under the line got no help.** **Done:** after 5 s, "Pedal past 100 W to fill the
   tank"; a stalled pad, "Push past 53 W to lift off!". Numbers from the rules.
6. [x] **The summary** uses `summary_stats`: best altitude, average tank, launches.
7. [ ] **The climb bar's ticks are unlabelled.** *Left:* icons would need 34 px text or tiny glyphs in
   a 34 px bar; the callouts name each one.
8. [ ] **The summary shows 384400 km with no comma.** *Left:* the shared `SummaryScreen` formats
   tiles, and its text is not this game's to change.

## Checks kept

Every label of ours at 40 px or more; the widget within 800 x 90; the game adds no touch targets.
