# FROSTBOUND — A Boss Trial ❄️🗡️

A single-file, browser-based action-RPG boss fight inspired by the fantasy MMORPG aesthetic.
Build a custom character on the fly through roguelite upgrade cards while battling two massive
frost bosses across escalating phases. No build step, no dependencies — just open the file.

## Play

Open `index.html` in any modern browser (Chrome, Edge, Firefox). That's it.

> Tip: double-click the file, or drag it into a browser tab.

## Controls

| Input | Action |
|------|--------|
| `W` `A` `S` `D` / Arrow keys | Move around the arena |
| `1` | **Strike** — your main damage |
| `2` | **Ward** — shield + heal; blocks/reduces telegraphed hits |
| `3` | **Cataclysm** — devastating ultimate |
| Mouse | Click the ability buttons too |

## How it works

- **Earn essence** by dealing damage. Each level, choose **1 of 3 upgrade cards** across
  **Offense / Defense / Arcane** to forge your own build. Choices are random but balanced.
- **Dodge the telegraphs.** Watch for glowing frost danger-zones:
  - **Frost Nova** — move out of the ring.
  - **Glacial Spikes** — 1–3 danger zones at once; **dash to the safe gap** or Ward through.
  - **Frostbolt** — unavoidable chip damage, so keep your HP up.
- **Your build carries over between bosses**, and you heal on victory.

## Bosses

1. **Kel'Thuzad, Archlich of Naxxramas** — 2 phases (*Rimecaller → Frozen Tempest*).
2. **The Lich King (Arthas)** — 3 phases (*Frostmourne Hungers → Remorseless Winter → The Scourge Unleashed*), tougher and faster, with triple Glacial Spike volleys.

## Tech

Vanilla HTML / CSS / JavaScript with HTML5 Canvas for rendering (boss art, particles,
telegraphs, screen shake) and a DOM overlay for the UI (health bars, ability cooldowns,
upgrade cards). Everything lives in one `index.html`.

All boss and arena art is **original hand-drawn Canvas** inspired by the general fantasy
MMORPG style — no copyrighted game assets are used.
