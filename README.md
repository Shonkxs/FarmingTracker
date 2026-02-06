# FarmingTimer

A simple WoW addon that tracks your farming time and stops automatically when all target amounts are reached.

## Features
- Track multiple items at once.
- Set items via drag and drop from your bags or by ItemID/Item Link.
- Define target amounts per item.
- Start / Pause / Resume / Stop / Reset.
- Auto-stop with a success sound when all targets are met.
- Movable main window plus Options panel.
- Minimap button (toggleable).
- Save, load, and delete presets.
- Optional: use target amounts (auto-stop) or just track time and counts.
- Export/import all presets or just a selected preset.
- Import with merge mode (do not overwrite existing presets).

## Installation
1. Copy the `FarmingTimer` folder to `World of Warcraft/_retail_/Interface/AddOns/`.
2. Enable the addon at the character selection screen.

## Quick Start
1. Open with `/ft` or the minimap button.
2. Click **Add Item**.
3. Drag an item into the slot or paste an ItemID/Link into **ItemID / Link**.
4. Enter the target amount in **Target**.
5. Press **Start** and begin farming.

## Main Window Controls
- **Add Item**: adds a new row.
- **Start**: starts the timer and tracking.
- **Pause**: pauses time tracking (progress stays visible).
- **Resume**: appears instead of Start when paused.
- **Stop**: ends the run.
- **Reset**: resets timer and progress.
- **Preset**: dropdown to select saved presets.
- **Preset Name**: enter a name and click **Save**.
- **Load**: loads the selected preset.
- **Delete**: deletes the selected preset.
- **Use target amounts**: if enabled, timer auto-stops when all targets are met. If disabled, the timer runs and only counts items.
- **Export All**: exports all presets into a shareable string.
- **Export Selected**: exports only the currently selected preset.
- **Import**: paste a previously exported string to restore presets.
- **Merge (do not overwrite)**: keeps existing presets and skips duplicates.

## Progress / Counting
- Counts are **net since start**:
  `current bag count - start count`
- If you consume/turn in items during the run, progress can go down.
- Only items in your bags are counted (no bank).

## Options (Interface -> AddOns -> FarmingTimer)
- **Open FarmingTimer**: opens the main window.
- **Show minimap button**: toggle minimap button.
- **Reset frame position**: resets the window position.

## Slash Commands
- `/ft`
- `/farmingtimer`

## FAQ
**Why does my item show a question mark?**
The item may not be cached yet. Wait a moment or open its tooltip so WoW can load the item data.

**Why is progress 0 after Stop?**
Stop ends the run. Starting again creates a new baseline.

## Feedback
Suggestions or bugs are welcome.
