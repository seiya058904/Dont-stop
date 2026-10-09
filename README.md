<div align="center">

# DON'T STOP

**Move. Fight. Adapt. Go again.**

A top-down 2D survival shooter / roguelite built with Godot 4. Survive encounters, collect weapons and upgrades, then return to camp to shape the next run.

[**▶ Play in your browser**](https://seiya058904.github.io/Dont-stop/) · [**Download for Windows**](https://github.com/seiya058904/Dont-stop/releases/latest) · [Current release v1.3.5](https://github.com/seiya058904/Dont-stop/releases/tag/v1.3.5)

![Godot](https://img.shields.io/badge/engine-Godot%204-478cbf?style=flat-square) ![Platforms](https://img.shields.io/badge/platform-Windows%20%2F%20Web-555?style=flat-square)

![Don't Stop main menu, captured from the game](Don't%20stop/docs/iteration/evidence/gilded/after-menu.png)

</div>

## ⚡ One more run

| Fight | Build | Return |
| --- | --- | --- |
| Keep moving through combat encounters | Gather weapons, upgrades and changing loadouts | Return to camp and prepare for the next attempt |

This project places responsive combat, clear hit feedback and a readable survival loop at its center. The graphical presentation includes weapon effects, enemy feedback, scene lighting and camera movement; the underlying rules and save behavior are protected by regression checks.

## 🎮 Controls

| Input | Action |
| --- | --- |
| `WASD` / arrow keys | Move |
| Mouse | Aim |
| Left click | Fire |
| `R` | Reload |
| `Shift` | Dash |
| `1`–`7` | Switch weapons |
| `E` / `Tab` | Camp or loadout controls |

The browser build can have different performance characteristics from the native Windows release. For the most reliable comparison, use the published build appropriate to your platform.

## 📦 Play & releases

- **Web:** [launch the current Pages build](https://seiya058904.github.io/Dont-stop/).
- **Windows:** [download the latest GitHub Release](https://github.com/seiya058904/Dont-stop/releases/latest).
- **Release reference:** [`v1.3.5`](https://github.com/seiya058904/Dont-stop/releases/tag/v1.3.5) fixes a slow-Web save confirmation issue; it does **not** claim to redesign save formats or gameplay rules.

Save-state handling includes recovery paths and protection against treating an unconfirmed write as durable. Avoid interpreting patch notes as a promise that a specific browser/storage environment cannot fail.

## 🛠️ Built with Godot

The Git repository root is outside the actual Godot project directory. Open [`Don't stop/project.godot`](Don't%20stop/project.godot) in the appropriate Godot editor to work on the game.

| Inside `Don't stop/` | Responsibility |
| --- | --- |
| `game/` | Encounters, player behavior and gameplay logic |
| `ui/` | HUD, loadout and interface |
| `autoload/` | Global state and persistence services |
| `Sprites/`, `audio/`, `fonts/`, `shader/` | Artwork and presentation resources |
| `tests/`, `tools/` | Native and browser regression tooling |
| `web/loader.html` | Web launch presentation |

For a documentation-only change, use targeted checks and validate the final Markdown paths. For game/runtime changes, consult [`AGENTS.md`](AGENTS.md) for the relevant Godot and browser verification tiers; do not run an unrelated full export as a cosmetic formality.

## 📚 Release and engineering records

- [v1.3.4 release audit](Don't%20stop/docs/iteration/release-v1.3.4.md) — prior verified release and limitations.
- [v1.2.0 visual release](Don't%20stop/docs/iteration/release-v1.2.0.md) — visual iteration evidence.
- [Performance & presentation deep pass](Don't%20stop/docs/iteration/deep-pass.md) — rendering/performance engineering notes.

## ⚖️ Credits & license context

**Don't Stop is a derivative project based on [SakuyaCN/TowDownGame](https://github.com/SakuyaCN/TowDownGame).** Its original README describes the project as using the GNU General Public License. This repository does not assert a more specific GPL version than the upstream statement. Original authorship and the upstream license must remain visible when distributing derivative works.
