# TBag Remake

A bag and bank replacement for **World of Warcraft: Forever** (interface 16001), inspired by the long-retired
[TBag-Shefki](https://www.curseforge.com/wow/addons/tbag-shefki). This is a rewrite for the modern client API, not a port of the old code.

## Features

- **One window for all bags, auto-sorted into categories.** Categories include Quest Items, Weapons, Armor, Consumables, Trade Goods, Gems & Enhancements, Recipes, Keys, Junk and Free Slots. Items in a category are sorted by quality, then name.
- **Bank window** with Character and Warband tabs, plus Restack and Deposit Reagents buttons.
- **View any character's bags and bank from anywhere.** Use the name button in the top right to switch characters. TBag can only show what it has seen, so log in to each character once and visit a banker.
- **Search.** The search box dims items that don't match. `/tbag find <text>` searches every character's bags, bank, equipped gear and mail.
- **Tooltip counts.** Item tooltips show how many of that item each character has.
- **Gold summary.** Hover over the gold display to see every character's gold and the total.
- **Pinned items.** Alt+Left-click an item, or choose "Pin to top" from its Alt+Right-click menu, to keep it in a Pinned category at the top. Pinned items show a star in the corner.
- **Gear Upgrades category.** Gear in your bags or bank that scores better than what you're wearing is listed near the top and marked with a green arrow. Its tooltip shows the score difference and which equipped item it beats.
  - The score uses stat weights for your class. For example, Strength counts most for Warriors and Intellect for Mages.
  - An item only counts if you can use it. It's skipped if its tooltip has red text, which is how the game marks wrong level, armor type, weapon skill or class.
  - Stats come from the game's item stats. If those are empty, the item's tooltip text is used instead.
  - Run `/tbag upgrades` to see the score for each piece of gear in your bags, or why it was skipped.
  - To turn the feature off (category, arrows and tooltip line), use `/tbag upgrades off`, right-click the Gear Upgrades header, or untick "Gear upgrades category" in settings. Use `/tbag upgrades on` to turn it back on.
  - Rings, trinkets and dual-wielded weapons are compared against the weaker of your two equipped items. A two-hander is compared against both hands combined.
- **Adjustable transparency.** Use the "Background opacity" slider in settings or `/tbag alpha <0-1>`. The default is 30%.
- **Category editing**, similar to TBag's edit mode:
  - Click a category header to collapse or expand it.
  - Right-click a header to move the category earlier or later, hide it, or create a new one.
  - Alt+Right-click an item to assign it to any category, including ones you created.
- **New-item highlighting**, with an optional "New Items" category at the top.
- **Compact free slots.** All empty slots of one kind show as a single button with a count, and you can drop items onto it.
- Item buttons use Blizzard's own bag item buttons, so using, selling, banking, splitting stacks and dragging work the same as in the default bags.

## Install

Copy or clone this folder into:

```
World of Warcraft\_forever_\Interface\AddOns\Tbag-Remake
```

The folder must be named `Tbag-Remake` to match `Tbag-Remake.toc`.

## Commands

| Command | What it does |
|---|---|
| `/tbag` | Toggle your bags |
| `/tbag bank` | Toggle the bank window |
| `/tbag find <text>` | Search all characters |
| `/tbag upgrades` | Explain the upgrade decision for each piece of gear in your bags |
| `/tbag upgrades on\|off` | Turn the gear upgrades feature on or off |
| `/tbag cols <n>` | Items per row (4-24) |
| `/tbag scale <n>` | Window scale (0.5-2) |
| `/tbag alpha <n>` | Background opacity (0-1) |
| `/tbag newcat <name>` | Create a custom category |
| `/tbag lock` | Lock or unlock window dragging |
| `/tbag reset` | Reset window positions |
| `/tbag config` | Open settings |

Settings are also under Options > AddOns > TBag Remake.

## Files

| File | Purpose |
|---|---|
| `Core.lua` | Namespace, saved variables, event dispatch, slash commands |
| `Categories.lua` | Category list, item classification, sorting, custom categories |
| `Upgrades.lua` | Stat scoring and gear upgrade detection |
| `Cache.lua` | Reads bags and bank, keeps the per-character cache, cross-character search and counts |
| `ItemButtons.lua` | Live (Blizzard template) and cached (read-only) item buttons, assign menu |
| `Window.lua` | Inventory and bank windows: layout, search, menus, footer |
| `Blizzard.lua` | Hides the default bag and bank frames and keeps open and close in sync |
| `Tooltip.lua` | Cross-character counts in item tooltips |
| `Options.lua` | Settings panel |
