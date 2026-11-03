# Watt Lane: UI polish punch list

> **Status:** every item done on `games-78-watt-lane` (2026-11-02).

From the UI review of 2026-11-02 against `framework/ui/UI_STYLE.md`, with the wave 1 games'
`capture_ui_states.gd` shots side by side (`review/watt_lane/refs/`).

## What works (keep)

- **One power number.** The ride panel's W is the rules' smoothed watts
  (`RideMetrics.set_power_source`) and turns gold exactly inside the band the rules use; the
  hero shows the lane's exact bounds; the chip and the step label name the next lane's exact
  bounds. `watt_lane_scene_test` checks every frame that the gold and the rules agree.
- The widget fits the 850 × 120 slot with the longest texts; labels change only with their
  values.

## Items

1. **The accent was a meaning colour.** Lime (`#C8FF3E`) reads as GOOD green (§4: "an accent is
   never a meaning colour"). **Done:** copper `#F0875A` on dusk navy `#0F1A2E`, in the HUD skin,
   the intro card, the pause screen, the summary and the hub card (`HubTheme.LOOKS`).
2. **The intro copy described the old road.** **Done** (rider's words): how-to "More watts move
   you up. Keep the chevron in the lit lane", target "Start between 110 and 160 W".
3. **The step's watts only showed in the HUD.** **Done:** the new bounds ("135–185 W", 40 px,
   amber, ink outline) sit beside the riser on the field, the same numbers as the chip, above an
   upward step and below a downward one.
4. **The chip overflowed the slot** with three-digit lanes ("DOWN to 880–960 W in 5").
   **Done:** "▼ DOWN 880–960 in 5" (the hero's caption says W); the arrow is a drawn shape.
5. **The out-of-lane state was colour only on the field.** **Done:** the chip PUSH ▲ / EASE ▼ /
   PEDAL ▲ in the widget, the chevron's amber rim, and the softer hum (never colour alone).
6. **The cursor sat under the ride panel at high power.** **Done** (`GFX_POLISH.md` item 2).
