<h1 align="center">⚡ DON'T STOP</h1>

<p align="center">
  <strong>Keep moving. Make every shot count.</strong>
</p>

<p align="center">
  A top-down 2D survival shooter built around fast decisions, relentless encounters,<br>
  evolving weapons, and one more run into the arena.
</p>

<p align="center">
  <a href="https://seiya058904.github.io/Dont-stop/"><strong>▶ Play in Browser</strong></a>
  &nbsp;·&nbsp;
  <a href="https://github.com/seiya058904/Dont-stop/releases/latest">⬇️ Windows Download</a>
  &nbsp;·&nbsp;
  <a href="#the-survival-loop">🎮 Gameplay</a>
  &nbsp;·&nbsp;
  <a href="#controls">⌨️ Controls</a>
  &nbsp;·&nbsp;
  <a href="#for-developers">⚙️ Development</a>
</p>

<p align="center">
  <sub>GODOT 4 &nbsp;·&nbsp; TOP-DOWN COMBAT &nbsp;·&nbsp; 24 WEAPONS &nbsp;·&nbsp; 30 CORE ENCOUNTERS + HELL STAGES</sub><br>
  <sub>WEB + WINDOWS x64 &nbsp;·&nbsp; CURRENT RELEASE v1.3.5</sub>
</p>

<p align="center">
  <img width="760" alt="Don't Stop — original top-down survival shooter project artwork" src="https://github.com/user-attachments/assets/8ff7c8c7-fc6e-44f0-9ac3-80a178cdcaed" />
</p>

---

> **Standing still is a decision. Usually the wrong one.**
>
> Enter the fight, find a rhythm, build a loadout, and survive long enough to return to camp. Don't Stop is about the space between danger and reaction—where movement, ammunition, positioning, and upgrades meet.

<a id="the-survival-loop"></a>
## 🎮 The Survival Loop

<p align="center"><code>MOVE → FIGHT → COLLECT → RETURN TO CAMP → BUILD → GO AGAIN</code></p>

Every attempt connects moment-to-moment shooting with longer-term preparation. You are not just trying to clear the screen; you are choosing how to face what comes next.

<table>
  <tr>
    <td width="50%" valign="top">
      <h3>🔫 Weapons With Character</h3>
      <p><sub>PROJECTILES · BEAMS · EXPLOSIONS · SPECIAL MECHANICS</sub></p>
      <p>Switch between weapons with distinct firing patterns, reload behavior, recoil, and impact feedback—from conventional guns to energy and experimental weaponry.</p>
    </td>
    <td width="50%" valign="top">
      <h3>⚡ Build Your Next Run</h3>
      <p><sub>UPGRADES · TALENTS · ATTACHMENTS · REWARDS</sub></p>
      <p>Return to camp to inspect your loadout and invest in different kinds of improvements. A stronger build is about combining effects, not merely collecting bigger numbers.</p>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <h3>👾 A Crowded Arena</h3>
      <p><sub>ENEMY WAVES · ELITES · BOSSES</sub></p>
      <p>Respond to shifting enemy density, approaching threats, and readable attack patterns. Later encounters demand more active positioning and sharper choices.</p>
    </td>
    <td width="50%" valign="top">
      <h3>💥 Combat You Can Read</h3>
      <p><sub>MUZZLE FLASH · HIT IMPACT · DAMAGE · STATUS</sub></p>
      <p>Weapon effects, enemy telegraphs, hit feedback, animation, and a focused HUD keep the action expressive without hiding the information needed to survive.</p>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <h3>🗺️ An Escalating Route</h3>
      <p><sub>30 ENCOUNTERS · SIX REGIONS · THREE BOSSES</sub></p>
      <p>Work through the normal encounter route, then face the higher-pressure Hell stage range, 31–40. Its difficulty comes from combined threats rather than an unbounded health multiplier.</p>
    </td>
    <td width="50%" valign="top">
      <h3>💾 Return Without Guesswork</h3>
      <p><sub>CAMP SAVES · RECOVERY · WEB PERSISTENCE</sub></p>
      <p>Persistence is treated as part of gameplay. The Web edition checks whether a saved snapshot actually reached browser storage before reporting durable success.</p>
    </td>
  </tr>
</table>

## 🏁 One More Encounter

The campaign is built around a **30-encounter normal route**, with increasing pressure from enemy waves, equipment decisions, and boss fights. The later **Hell stages (31–40)** extend the challenge with stronger combinations of enemy density, visibility, elite pressure, and arena hazards.

The core project includes **24 weapons**, alongside authored attachments, talents, and rewards. Different builds emphasize different tactics: sustained fire, precise burst damage, crowd control, survival, or mobility.

> [!TIP]
> **Movement is part of the build.** Reloading, dodging, choosing a target, and finding a safe angle matter even when the weapon is powerful. The combat experience is designed to reward active play rather than leaving the character stationary.

<a id="controls"></a>
## ⌨️ Controls

| Input | Action |
| --- | --- |
| **WASD** / **Arrow keys** | Move |
| **Mouse** | Aim |
| **Left mouse button** | Fire |
| **R** | Reload |
| **Shift** | Dash |
| **1–7** | Switch weapons |
| **E** / **Tab** | Camp or loadout interactions |

The desktop game is designed for mouse and keyboard. The Web build may behave differently depending on browser, GPU, and device capabilities; it should not be treated as an identical performance benchmark for the native Windows edition.

<a id="play-and-download"></a>
## 🚀 Play & Download

<table>
  <tr>
    <td width="50%" valign="top">
      <h3>🌐 Web — Play Now</h3>
      <p><sub>GITHUB PAGES · GODOT WEB EXPORT</sub></p>
      <p>Launch the game directly in a desktop browser without installing the Windows executable.</p>
      <p><strong><a href="https://seiya058904.github.io/Dont-stop/">▶ Enter the Web Arena →</a></strong></p>
    </td>
    <td width="50%" valign="top">
      <h3>🖥️ Windows — Native Build</h3>
      <p><sub>WINDOWS x64 · RELEASE ZIP</sub></p>
      <p>Download the published Windows archive, extract it, and launch the packaged game from the extracted files.</p>
      <p><strong><a href="https://github.com/seiya058904/Dont-stop/releases/tag/v1.3.5">⬇️ Get v1.3.5 →</a></strong></p>
    </td>
  </tr>
</table>

The [**v1.3.5 release**](https://github.com/seiya058904/Dont-stop/releases/tag/v1.3.5) also includes a **Web ZIP** and separate SHA-256 checksum files. A downloaded Godot Web export should be served through an appropriate local HTTP server; the live Pages URL is the simplest way to play online.

### 🔒 A Note About Saves

The **v1.3.5** patch specifically improves confirmation of **slow browser save writes** when returning to the menu after a purchase. A successful Web save is reported only after the required snapshot has been committed to and verified in IndexedDB. If persistence fails, the existing retry, export, or discard paths remain available.

> [!IMPORTANT]
> **Local saves are not cloud synchronization.** Browser storage can be cleared or unavailable, and native Windows saves belong to their own local environment. Preserve important progress before resetting storage, changing browser profiles, or removing user data. A save warning should not be mistaken for a successful backup.

<a id="for-developers"></a>
## ⚙️ For Developers

Don't Stop is a **Godot 4.7.2** project. The Git repository root is **not** the Godot project root: open the nested [`Don't stop/project.godot`](Don't%20stop/project.godot), and quote the directory name when using command-line tools.

<details>
<summary><strong>🛠️ Expand source layout, verification &amp; export workflow</strong></summary>

### Source map

| Path | Responsibility |
| --- | --- |
| [`Don't stop/boot/`](Don't%20stop/boot/) | Startup and loading flow |
| [`Don't stop/game/`](Don't%20stop/game/) | Player, weapons, enemies, maps, encounters, and combat |
| [`Don't stop/autoload/`](Don't%20stop/autoload/) | Shared game state and persistence services |
| [`Don't stop/ui/`](Don't%20stop/ui/) | Camp, loadout, HUD, and interface screens |
| [`Don't stop/Sprites/`](Don't%20stop/Sprites/) | Visual assets and sprite resources |
| [`Don't stop/tests/`](Don't%20stop/tests/) | Native regression scenarios |
| [`Don't stop/tools/`](Don't%20stop/tools/) | Verification, Web testing, and build-identity utilities |
| [`Don't stop/web/loader.html`](Don't%20stop/web/loader.html) | Browser export loading presentation |

### Open the project

With a matching Godot 4.7.2 executable available:

```bash
"$GODOT" --path "Don't stop"
```

On Windows, use the corresponding Godot executable path. The repository also contains [`Don't stop/PLAY_GAME.bat`](Don't%20stop/PLAY_GAME.bat), a workspace-specific development launcher that relies on the documented local portable Godot installation; it is **not** a distributable installer.

### Choose the right verification tier

From the Git root, the project provides targeted verification rather than requiring a full release test for every small change:

```bash
python "Don't stop/tools/verify.py" verify-fast --base origin/main
```

For broader product changes, documented tiers include `verify-web`, `verify-native`, `verify-full`, and `verify-release`. They require the appropriate Godot, browser, and test environment. The full native suite and Web stress checks are significantly more extensive; **documentation-only work should not be presented as a completed game-export acceptance**.

The release workflow preserves **the same tested Web artifact** through verification and deployment, and checks the deployed build's identity. Historical test results are evidence for their particular code and asset hashes, not blanket proof for all later revisions.

**Further reading:** [Repository guidance](AGENTS.md) · [Godot project play guide](Don't%20stop/README-PLAY.md) · [v1.3.4 save audit](Don't%20stop/docs/iteration/release-v1.3.4.md) · [Presentation and performance work](Don't%20stop/docs/iteration/deep-pass.md)

</details>

## 📜 Origins & Licensing

**Don't Stop is a derivative of [SakuyaCN/TowDownGame](https://github.com/SakuyaCN/TowDownGame).** Its upstream README identifies the project as using the **GNU General Public License**. This documentation does not assume a specific GPL version without a verified licensing source. Preserve upstream attribution and review applicable upstream and asset licenses before redistributing derivative builds.

---

<p align="center">
  <sub>MOVE. FIGHT. ADAPT. GO AGAIN.</sub><br>
  <sub>Don't Stop · A top-down survival shooter built for the next run.</sub>
</p>
