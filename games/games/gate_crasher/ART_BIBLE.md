# Gate Crasher: art bible

> **Status:** v1, 2026-11-06. **Sources of truth:** `GateWorld.gd` (layout, per frame),
> `GateMeshes.gd` (every mesh), `shaders/*` (the grade), `GateCrasher.look` and `GateStatus` (UI).

Everything is procedural: shapes built in code, lit by hand in shaders. No textures beyond the
shared 64x64 noise, no imported models, no fonts but the kit's OFL display face. Nothing is any
real show, federation or sponsor's name or livery.

## 1. Identity

**The one rule:** *a clean, bright morning at a county show, seen between a horse's ears.* When
something is ambiguous, pick what makes the next fence and its line read faster.

| Pillar | Design test |
| --- | --- |
| **The fence is the hero** | Painted poles are the strongest colour on the sand, and each fence has its own colours. |
| **The line tells you when** | From 3 s out the approach turns gold, and on the line it pulses teal. |
| **You're on a horse** | The ears frame the view, the neck nods with the stride, the view rocks over a jump. |

It stands apart from its neighbours: Pull is warm-on-cool dusk, Dodge cool asphalt, Tug a timber
pier, Kart a violet night. This is the only sand-and-grass daylight.

## 2. Mood by state

| State | Look |
| --- | --- |
| Canter | The view bobs and the neck nods once a stride. |
| Count | The chevrons, the line and its poles turn gold; a big 3, 2, 1. |
| The line | It pulses teal, "STAND!". |
| Jump | The view lifts on an arc and rocks up, then down. Dust on landing. |
| Fault | The top rail tips and drops behind you, "4 faults". |
| Clear round | Confetti ahead, the crowd jumps. |
| Circling | The view turns a full circle off the course. |

## 3. Palette

| Role | Colour |
| --- | --- |
| Accent (UI, browband, the live line) | `#2FC4B2` rosette teal |
| Ink | `#0C2A2E` |
| Sand | `#D9BD8C`, worn darker along the course |
| Grass | mown stripes round `#5C8F42` |
| Horse | bay `#7A4526`, points `#54301C`, mane `#1D1612` |
| Fence pairs | `GateMeshes.RAIL_SETS`, eight of them |

## 4. Light

Sun at 38 degrees, warm; sky ambient; pale warm haze (`GateWorld.LOOK`). Saturation 1.1, contrast
1.05, a slightly warm gain (`gate_look.gdshaderinc`). The vignette is painted into the view grid.

## 5. Layout

A 436 m stadium loop (`GateCourse`). The white ring fence stands 9 m either side of the course, with
a hedge outside it, flower beds in the infield, a striped grandstand down the first straight, the
judges' box opposite and a belt of trees beyond.

## 10. Silhouette check (rider's rule, required)

Every main shape, solid black at 240 px (`tests/capture_gate.gd --silhouette`).

| Shape | Reading at small size | Verdict |
| --- | --- | --- |
| Horse, v1 (tall smooth neck, rounded top) | A single tapering column | **Rejected**: the neck was rebuilt |
| Horse, v2 (a centred dark mane strip under a forelock oval) | A round head with a tapering tail, inside the shape | **Rejected**: no forelock, and the mane moved to one side |
| Horse, v3 (wide trapezoid, flat poll, two ears far apart) | A horse's head from behind | Pass |
| Mane (ragged locks to the right) | Hair | Pass |
| Fence, line, chevrons, flags | Posts and bars | Pass |
| Confetti, dust | Small squares; soft discs | Pass: nothing has a tail |
| Crowd figures | Static people, a head over a body | Pass |
| Intro art | Posts, poles, an arrow, a dashed arc | Pass: no figure |

No rider's arms or hands appear anywhere, by the rider's direction.
