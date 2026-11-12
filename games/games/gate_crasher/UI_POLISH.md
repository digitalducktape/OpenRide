# Gate Crasher: UI punch list

Reviewed against `framework/ui/UI_STYLE.md` and earlier wave 2 review findings, 2026-11-06.

**What works:** one slim widget, the kit's themed panels, words in every state, centred callouts in
the display face with the kit's heavy outline.

1. **Done.** Watts show once, in the ride panel; the pace is its band tick. A test checks the widget
   never shows a watts number or a "W".
2. **Done.** No "×" label: "4 FAULTS", "CLEAR SO FAR", "CIRCLING" and "PEDAL ON" are words, so
   nothing competes with "Effort ×1.1".
3. **Done.** Nothing is clipped: tests cover the widget's budget with the longest texts, the ears
   against the frame and the HUD, and every fence whole in the frame at its line.
4. **Done.** The intro card has real art, and its numbers come from the segment.
5. **Done.** The summary uses `summary_stats`: clear jumps as "12/12", faults, clear rounds.
6. **Skipped.** The 3-2-1 sits over the ear gap and "Can't see you: circling" crosses the ears. Both
   are brief, and the kit's message slot is shared by every game.
