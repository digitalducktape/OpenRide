# The Pull: UI polish punch list

From the UI review of 2026-11-02 against `framework/ui/UI_STYLE.md` and the wave 1 games' HUD
captures (Tug of War, Dodge Ball), at 1920×1008 and judged at half size.

## What works (keep)

- One look: `GameTheme` tractor green on a field ink, the house fonts and outlines, the HUD
  skin. The intro card, pause and summary take it.
- The widget's hero distance (80 px), the state chip with words (never colour alone) and the
  progress bar with the best flag and the checked Full Pull end. It fits 820 × 120.
- Every number agrees: the sled's need appears in the widget and as the ride-metrics tick, from
  one value; metres share one rounding (`the_pull_scene_test`).

## P0

1. [x] **Intro copy, numbers from the segment.** The target line was "Full Pull at 336 m" or
   "Beat your best: N m". It now reads "Reach the Full Pull line at N m" (N from the segment's
   `d_ref_m` and `full_factor`, through `PullLogic.full_line_for`, the logic's own rule; the
   difficulty's default sled without params), or "Your best: N m" from the rider's best at that
   difficulty. Nothing is hard-coded. `test_the_intro_target_comes_from_the_segment` covers it.
2. [x] **Nothing clipped by the frame or a HUD panel.** A bounds check
   (`test_nothing_is_clipped_by_the_frame_or_a_hud_panel`) projects the mirror and the
   handlebars from the 3D view to the stage. They must lie inside the frame, and clear of the ride panel,
   the clock, Pause, End, the status widget and the longest centre message ("Stalled at 1888 m").
   The test also checks the HUD's own panels are on the
   stage.
3. [x] **The widget's chip touched the panel's top edge.** Its top margin went from 2 to 8 px.

## P1

4. [x] **The intro card had no picture** (Tug shows its bot, Dodge its mode). `PullIntroArt`
   draws the sled side-on, with its weight box over the rear, an arrow showing the box slides
   forward, and the chain running off toward the bike. It is drawn once.
5. [x] **Distance and pulls on the summary.** Through `GameInfo.summary_stats` (the framework
   part of Watt Lane's fc67b21, taken unchanged): "best pull", "pulls" and "peak watts" tiles.

## From the review of 2026-11-04

6. [x] **"DIG IN! 3" meant nothing.** The chip now reads "DIG IN! NEEDS 127 W · 3": the sled's
   need, as in the normal chip, then the seconds left.
7. [x] **One score.** The HUD floors the score and `Game.finish` rounds it, so the HUD said 1107
   and the summary 1108. The Pull's result now uses the HUD's floor. Every other game still has
   the mismatch: it is in the shared framework.
8. [x] **"FULL PULL! 336 m" was flat green and repeated the status bar.** The centre message is
   now "FULL PULL!" in the target gold, styled as "Dig in!" is, and the chip shows what it earned
   ("BONUS +500", as counted).
9. [x] **The intro.** The how-to lines are shorter and fit on one line (a test measures them),
   with no "metre". The sled picture is 1.75× larger and fills the space.
10. [x] **"PULL 1"** went from 34 to 44 px, in full white. The bar narrowed to fit.
11. [ ] **The clock and "ridden" disagree by 10 s.** Not a capture artefact, and not changed
    here. "ridden" is the plan's time, which includes the intro card (GAMES.md, "Recording"); the
    clock counts gameplay. It is the same in every game and matches the saved ride.
12. [ ] **"more resistance scores more"** is the shared effort badge: left alone and flagged.
