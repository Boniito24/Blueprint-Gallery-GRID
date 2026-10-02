# Blueprint Gallery GRID

A widget for the RTS game **[Beyond All Reason](https://www.beyondallreason.info/)** (BAR).

While you place a blueprint (**Alt+B**), your blueprints **replace the build grid**: same panel, same look,
same tabs (**Economy / Combat / Utility / Build**) and the **same hotkeys** as the grid.

## Installation

1. Close the game.
2. Copy the file `gui_blueprint_gallery.lua` into your Beyond All Reason folder, here:

   ```
   Beyond-All-Reason/data/LuaUI/Widgets/gui_blueprint_gallery/gui_blueprint_gallery.lua
   ```

   (create the `gui_blueprint_gallery` folder; putting the file directly in `Widgets/` also works).
3. Start a game: the widget turns on by itself. If not, press **F11** and enable **Blueprint Gallery GRID**.

## How to use

- **Home page**: all your blueprints. The grid's tab keys (e.g. `Z X C V` on QWERTY, `W X C V` on AZERTY) open a tab.
- **In a tab**: press the cell's letter to pick that blueprint. **Shift** (or Esc) goes back, like the grid.
  The grid's page key goes to the next page.
- **Mouse**: click a thumbnail to pick it, **drag** it onto another cell to arrange your grid, **right-click** to change
  its category (auto → the other tabs → auto).
- **Wheel**: next/previous blueprint, **Ctrl+wheel**: tab, **Alt+wheel**: rotate. You can swap wheel and Alt+wheel in
  *Settings → Plugins* (French: *Personnalisé*) → *Blueprint Gallery GRID* → *Mouse wheel while placing*.
- Outside blueprint placement, the grid works exactly as usual.

Categories are automatic (Build if the blueprint has a factory, otherwise the grid category of its most expensive
building) until you move a blueprint yourself. Your choices are stored in the blueprint's name, so they are saved by
the game with your blueprints.

Texts follow the game language (English, Français, Deutsch, Español, Italiano, Русский, 中文; English otherwise).

## Notes

- UI only: the official *Blueprint* widget still places the blueprints and saves them; nothing else is written to disk.
- It reads the official *Blueprint* and *Grid menu* widgets' internals. Tested with BAR `test-31422` (September 2026).
  If a game update changes them, it says so in the console and falls back to a simple panel or turns itself off —
  the game is never affected.

## Résumé en français

Widget pour le jeu **Beyond All Reason**. Pendant la pose d'un blueprint (Alt+B), tes blueprints prennent la place de
la grille, avec ses onglets et ses touches : la touche de l'onglet, puis la lettre de la case. Shift pour revenir.
Glisser une miniature pour la ranger, clic droit pour changer sa catégorie. Le widget suit la langue du jeu.

Installation : jeu fermé, copier `gui_blueprint_gallery.lua` dans le dossier de Beyond All Reason, ici :
`Beyond-All-Reason/data/LuaUI/Widgets/gui_blueprint_gallery/gui_blueprint_gallery.lua`, puis lancer une partie
(sinon F11 et cocher « Blueprint Gallery GRID »).

Author: Boniito. Developed with the help of Claude (Anthropic's AI assistant).

License: GNU GPL v2 or later.
