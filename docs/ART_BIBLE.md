# Lab Escape art bible

The rules every model, texture, light and effect follows, so the game looks like one place made by one team.
Written 2026-11-14 for roadmap WP20 from the roadmap's art plan (section d), which Zachary approved with decision D7.
**Not final until the look target (WP21) is approved:** the numbers here may move once we see one room at final quality
(and after the performance check, WP21b, measures what a modest PC can draw).

Words used here:
- **Low-poly:** models made of few, large flat faces, so shapes read clearly and the game runs on modest PCs.
- **Triangle budget:** the most triangles (the flat pieces every 3D model is made of) one model may use.
- **Palette texture:** one small image of colour squares that every model in a department paints itself from.
- **UV mapping:** telling each face of a model which part of an image to show.
- **Emissive:** a material that glows by itself (screens, light strips).
- **LOD (level of detail):** simpler copies of a model the engine swaps in when it's far away.

## 1. Style in one line
Chunky, comedic low-poly lab: big readable shapes, flat colour with a few soft gradients, slightly exaggerated
proportions (big hands, big heads on enemies). Nothing photographic, no realistic gore: deaths are "poofs".

Do:
- Silhouettes you can recognise in one second, from across a room.
- Rounded-off chunky edges (a bevel of 1 or 2 segments on hero objects only).
- Colour carries meaning: lift parts and keys glow, danger is red/orange, pickups sparkle.

Don't:
- Thin details that flicker at a distance (cables thinner than 3 cm, text smaller than a sign).
- Photo textures, noise textures, normal maps (the palette texture is the only texture most models need).
- Characters or brands from other games, films or companies, in models, prompts or signs.

## 2. Colours and light per place
| Place | Colours | Light | When damaged |
|---|---|---|---|
| Zoology | warm wood, sand, moss green | warm, about 3200 K (amber) | dark corners, broken skylights |
| Botany | clinical white with green accents | bright and flat, about 5500 K | green-tinted and dim |
| Robotics | industrial grey with safety-yellow stripes | cold strip lights, about 6500 K (blue-white) | red emergency lights |
| Break Room | cosy staff room: warm, posters, a fridge | warm lamps | never |
| Cargo lift | scuffed safety yellow, dark metal floor | its own work light | sparks at broken slots |
| Car park (ending) | grey tarmac, white bay lines, coloured cars | daylight, blue sky | never |

The department files already hold each department's palette materials and light colours; the art pass replaces the
grey-box materials, not the system.

## 3. Triangle budgets
| Thing | Triangles |
|---|---|
| Player body | 2,000 to 3,000 |
| Mutation or cybernetic part | 300 to 800 each |
| Cosmetic (hat, glasses...) | 100 to 400 |
| Small enemy (rat, bat, fly, drone) | 800 to 2,000 |
| Large enemy (kangaroo, vine creeper, roomba) | 2,000 to 4,000 |
| Boss | 6,000 to 10,000 |
| Small prop (gem, vial, crate) | 50 to 400 |
| Large prop (vending machine, printer) | 400 to 1,200 |
| One modular kit piece (a wall, a floor tile) | under 300 |
| Everything in view at once | under about 300,000 |

## 4. Surfaces
- One **palette texture per department**, 256 x 256 pixels: a grid of colour squares. Models are UV-mapped onto the
  squares instead of having their own pictures. Changing the department changes the palette, so one modular kit
  serves all three departments.
- NEW 2026-11-14 (art rollout): the 16 x 16 grid has eight "shell" squares (lower wall, upper wall, trim, ceiling,
  beam, light, floor, accent). They hold Zoology's colours in `palette_zoology.png` and Botany's and Robotics'
  colours in `palette_botany.png` and `palette_robotics.png`. Every room's walls use them, so the rooms and
  hallways all departments share are one model each, coloured by the floor's department palette
  (`DepartmentData.palette["art"]`), and a doorway a floor doesn't use is filled with one wall piece that fits any
  room (`assets/models/shared/wall_patch`).
- Hero objects (bosses, the lift) may have one 512 x 512 texture of their own.
- Glowing parts use an emissive material from the shared set (`assets/materials/shared/`), not a texture.

## 5. Lighting
- A few real lights per room; at most 4 that cast shadows in view at once.
- Glow strips and screens are emissive materials (cheap), not lights.
- Light fog per department; a little ambient occlusion. No baked lightmaps: floors are generated at runtime.
- Measured 2026-11-14 (docs/PERFORMANCE.md): models are cheap in this style; lights, fog and glow are not. Keep one
  joined mesh per room dressing and prop, at most 4 shadowed lights in view, and volumetric fog only where it sells
  the room.

## 6. Scale and grid
1 Godot unit = 1 metre. The player is 1.8 m tall. Rooms sit on a 3 m grid. Doorways are 2.4 m wide and 2.8 m tall.
Ceilings are 3.6 m. The lift cage is 5 x 5 m inside. A crate is about 0.6 m. Props and characters have their origin
at the centre of their base (the floor point under them).

## 7. Files and folders
- File names: `<kind>_<name>.glb`, matching the content id where there is one: `enemy_rat.glb`, `prop_crate.glb`,
  `kit_zoology_wall_door.glb`, `cosmetic_hat_hard_hat.glb`.
- Models: `assets/models/<department or shared>/`. Textures: `assets/textures/<department>/`. Materials:
  `assets/materials/<department>/`. Sounds: see the roadmap's audio plan.
- **Drop new files in `assets/_incoming/`** (or `assets/_incoming/meshy/`, `assets/_incoming/cc0/`); Claude moves
  them to the right folder, sets the import settings and hooks them up.

## 8. Export from Blender, import into Godot
Blender: glTF 2.0 binary (`.glb`), +Y up, metres, apply all transforms, origin at the base centre.
Godot import: meshes with LODs generated and shadow meshes on; textures VRAM-compressed with mipmaps and linear
filtering. Claude sets these when it brings a file in.

## 9. Animation
Mixamo for the player and humanoid enemies (free with an Adobe account; check its terms the day you use it). Simple
animation in Blender or in code for animals, plants and robots. Keep to the few clips the game uses: idle, walk or run,
attack, hurt, death.

## 10. AI tools and licences
Every model or sound made with an AI tool gets a line in `docs/AI_CONTENT_LOG.md` (asset, tool, plan, date) for
Steam's disclosure. Check the tool's commercial licence for the plan in use first (Meshy's free plan is CC BY 4.0,
which needs credit; paid plans include commercial rights). Never prompt for existing characters or brands. Anything
made by someone else goes in `docs/CREDITS.md`.
