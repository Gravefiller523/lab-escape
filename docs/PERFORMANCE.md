# Performance budget

What the game may ask a graphics card to draw, measured before the art rollout so the art bible's budgets are real
numbers (roadmap WP21b, 2026-11-14). The final check on a modest PC is WP31.

Words used here:
- **Frame rate (fps):** how many pictures a second the game draws. 60 is the target on a modest PC.
- **Draw call:** one "draw this" order to the graphics card. Fewer is faster; each separate mesh and material costs one.
- **Triangles:** the flat pieces models are made of. The count in view at once is what matters.

## How to measure
Type `perf` in the console (\`): it shows frames per second, the frame time, draw calls and triangles in view against
the budget, how many objects are drawn, and video memory. `fps` shows only the frame rate.
The budgets live in `config/game_config.tres` (`perf_draw_call_budget`, `perf_triangle_budget`).

## Budget for one frame (modest PC: GTX 1060-class card, 8 GB RAM, 1080p, medium settings)
| What | Budget |
|---|---|
| Triangles in view | 300,000 |
| Draw calls | 1,500 |
| Lights casting shadows in view | 4 |
| Frame time | under 16.7 ms (60 fps) |

## Measured 2026-11-14 on Zachary's PC (RTX 5080, i7-14700KF, 32 GB, 1080p, vsync off)
The Zoology animal holding room from the look target (room, 2 rats, crate, gem, meat, 3 shadowed spot lights,
2 lamps, volumetric fog, glow, ambient occlusion), against the grey-box room from the same spot:

| Scene | fps | Draw calls | Triangles | Objects | Video memory |
|---|---|---|---|---|---|
| Look target room | about 1,500 | 5 | 4,124 | 6 | 185 MB |
| Grey-box room | about 1,900 | 10 | 552 | 10 | 109 MB |

What it means:
- **Triangles are cheap at this style.** A whole room of the new style is about 4,000 triangles (the room itself is
  2,644). A floor of about 13 rooms with its enemies and props would be around 60,000: a fifth of the budget.
- **Draw calls are low** because each room is one joined mesh with one palette material. Keep it that way: one mesh
  per room dressing, one per prop, one per character.
- **The expensive parts are lighting and fog**, not models: the frame rate dropped about a fifth with volumetric fog,
  glow and ambient occlusion on. On a modest PC these are the first things to turn down (WP31 adds graphics settings
  for them).
- This PC is far faster than the target, so its fps says little about a modest PC. The draw call and triangle counts
  are the same on any PC, and they are well inside the budget.

## Rules for the rollout (added to the art bible)
- One joined mesh per room dressing and per prop, one palette material each.
- At most 4 shadow-casting lights in view; light the rest with lamps that don't cast shadows.
- Volumetric fog only where it sells the room (skylight beams), and behind a graphics setting.
