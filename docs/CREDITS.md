# CreditsThe models are made by Claude in Blender from `assets/source/look_target_models.py` (no outside art). Sounds from others:
| What | Where in the project | Source | Licence | Credit needed? |
|---|---|---|---|---|
| Impact Sounds, Interface Sounds, RPG Audio, Sci-fi Sounds (Kenney), 97 files chosen from them (2026-11-14) | `assets/audio/sfx/shared/` | kenney.nl | CC0 (licence file checked in each pack) | No (we credit Kenney anyway in the game credits) |

The list the in-game credits are built from (roadmap WP19, gap G45). Keep it up to date: every time something made
by someone else goes into the game, add a line here and check its licence first. Started 2026-11-13.

## The game
- **Made by:** Zachary
- **Playtesters:** (add the friends who play the test builds)

## Engine and code we use
| What | By | Licence | Ships in the game? | What we must do |
|---|---|---|---|---|
| Godot Engine 4.7 | Juan Linietsky, Ariel Manzur and contributors | MIT | yes | Show Godot's licence text (with its third-party notices) somewhere players can read it, e.g. the credits. The engine provides the text itself (`Engine.get_license_text()`, `Engine.get_copyright_info()`). |
| GodotSteam | GP Garcia, Chris Ridenour and contributors | MIT | yes | Include its licence notice in the credits. |
| Steamworks SDK (`steam_api64.dll`) | Valve | Steamworks SDK Access Agreement | yes | Allowed for games released on Steam. Nothing to show. |
| GUT (Godot Unit Test) | Tom "Butch" Wesley and contributors | MIT | no (left out of exports) | Nothing. |
| Godot AI (editor plugin) | Godot AI contributors | MIT (checked 2026-11-13, `addons/godot_ai/LICENSE`) | yes for now: its small game helper is an autoload (roadmap gap G61) | Leave it out of release builds (G61). Until then, include its licence notice with the others. |

## Art, sound and music
The models are made by Claude in Blender from `assets/source/look_target_models.py` (no outside art). Music is still
the game's own generated placeholder. Sounds and art from others:
| What | Where in the project | Source | Licence | Credit needed? |
|---|---|---|---|---|
| Kenney's Impact Sounds, Interface Sounds, RPG Audio and Sci-fi Sounds: 97 files chosen from them (downloaded 2026-11-14) | `assets/audio/sfx/shared/` (the packs themselves in `assets/_incoming/audio/`, not in git) | kenney.nl | CC0 (each pack's License.txt checked) | No, but we credit Kenney in the game's credits anyway |

AI-made assets also go in `docs/AI_CONTENT_LOG.md` for Steam's disclosure.

## Tools used to make the game (not shipped, thanks only)
- Claude (Anthropic) helped write the code and plans.
- Blender, Mixamo, Meshy and ElevenLabs once the art and sound phases start (roadmap WP20 to WP30).
