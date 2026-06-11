# TB-3 Preset Manager

Desktop companion app for the TB-3 TouchOSC layout. Saves full patch dumps
(`.syx`) and 16-slot preset banks exchanged with TouchOSC over OSC.

![TB-3 Preset Manager](../screenshots/preset-manager.png)

## Setup (once)

```bash
cd tb-3/preset-manager
python3 -m pip install --user -r requirements.txt
./run-preset-manager.sh
```

`run-preset-manager.sh` uses **system `python3`** (it checks for a working
PyQt5 first). A project `.venv` is supported as a fallback — set
`TB3_PRESET_MANAGER_USE_VENV=1` to force it.

### macOS + Homebrew Python: "externally-managed-environment"

Homebrew's `python3` blocks plain `pip install --user`. If you hit that error,
install with:

```bash
python3 -m pip install --user --break-system-packages -r requirements.txt
```

`--break-system-packages` paired with `--user` only touches your user
site-packages — it does not modify the Homebrew Python install itself.

Recommended alias:

```bash
alias tb3-preset-manager='/path/to/touchosc-controllers/tb-3/preset-manager/run-preset-manager.sh'
```

## Window layout

The app opens at **900×560** with two tabs:

| Tab | Contents |
|-----|----------|
| **Library** | Bank list (left) + slot list (right), split by a draggable divider |
| **Settings** | Network ports, patches folder, listener status |

Window size and position are saved to `~/.tb3_preset_manager/settings.json` and
restored on next launch.

## Library tab

### Banks (left column)

The first entry, **(individual patches)**, shows standalone `.syx` files in the
top-level patches folder. Real banks appear below it as named entries.

| Button | Action |
|--------|--------|
| **Pull Bank** | Requests all 16 preset-grid slots from TouchOSC; prompts for a name; saves as `<name>.tb3bank.json` |
| **Send Bank** | Sends the selected bank back to TouchOSC, restoring all 16 slots in the layout |
| **Rename Bank** | Renames the bank file |
| **Delete Bank** | Removes the bank file from disk |
| **New Bank** | Creates an empty 16-slot bank file |
| **Import JSON…** | Copies a `.tb3bank.json` from anywhere on disk into the banks folder |
| **Export JSON…** | Saves a copy of the selected bank to a location you choose |

Banks are stored in a `banks/` subfolder of your patches folder.

### Slots (right column)

When a bank is selected, the right column lists slots **1–16** with their
stored preset names (empty slots shown in grey). In **(individual patches)**
mode, the column lists standalone `.syx` files instead.

| Button | Action |
|--------|--------|
| **Send Patch** | Reads the selected slot's patch and sends each SysEx block to TouchOSC via `/tb3/restore` (forwards to TB-3 hardware and updates the layout UI) |
| **Rename Preset** | Edits the display name stored in the slot |
| **Export .syx…** | Writes the slot's patch to a standalone `.syx` file |
| **Empty Slot** | Clears the selected bank slot |
| **Pull Patch** | Requests the current patch from TouchOSC (`/tb3/request_patch_export`) and writes it into the selected slot (bank mode) or the orphan patches folder |
| **Import .syx…** | Imports a `.syx` file into the selected slot or the orphan folder |

> **Pull Patch** is the desktop-driven equivalent of the old TouchOSC "Save to
> Library" button. TouchOSC no longer has an on-screen export button — the app
> initiates the request.

## Settings tab

| Field | Default | Purpose |
|-------|---------|---------|
| Listen IP / port | `0.0.0.0:9000` | Where the app receives OSC from TouchOSC |
| TouchOSC IP / port | `127.0.0.1:9001` | Where the app sends OSC to TouchOSC |
| Patches folder | `~/tb3_patches/` | Root for `.syx` files and `banks/` subfolder |

Press **Restart listener** after changing network settings. Settings auto-save
when the window closes.

## OSC protocol

| Path | Direction | Purpose |
|------|-----------|---------|
| `/tb3/request_patch_export` | app → TouchOSC | Request current patch snapshot |
| `/tb3/backup` | TouchOSC → app | Single-patch JSON (`{"blocks": [...], "name": "..."}`) |
| `/tb3/restore` | app → TouchOSC | One SysEx block as hex CSV; forwarded to TB-3 |
| `/tb3/patchgrid/request_manifest` | app → TouchOSC | Request bank manifest (filled slot keys) |
| `/tb3/patchgrid/manifest` | TouchOSC → app | `{"version":2,"name":…,"slots":["1",…]}` |
| `/tb3/patchgrid/request_slot` | app → TouchOSC | Request one slot (arg = slot key) |
| `/tb3/patchgrid/slot` | TouchOSC → app | `{"slot":"N","data":{"blocks":[…],"name":…}}` |
| `/tb3/patchgrid/restore_begin` | app → TouchOSC | Begin chunked bank push (`{"version":2,"name":…}`) |
| `/tb3/patchgrid/restore_slot` | app → TouchOSC | Push one slot (`{"slot":"N","data":{…}}`) |
| `/tb3/patchgrid/restore_end` | app → TouchOSC | Commit the pushed bank (replaces all 16 slots) |

Bank pull/push transfer **one slot per OSC message** (manifest-driven pull; begin/slot/end push). A full 16-slot bank is ~15 KB, but macOS caps a single UDP datagram at ~9 KB (`net.inet.udp.maxdgram`), so a one-shot transfer silently truncates and drops.

## Bank file format (v2)

`.tb3bank.json` files are plain JSON:

```jsonc
{
  "version": 2,
  "name": "Live Set 1",
  "createdAt": "2026-01-01T12:00:00",
  "slots": {
    "1":  {"name": "Bass 1", "blocks": ["F041...F7", "F041...F7", ...]},
    "2":  null,
    ...
    "16": {"name": "", "blocks": [...]}
  }
}
```

Each `"blocks"` array contains 11 hex-encoded Roland DT1 SysEx messages (the same
blocks as a `.syx` file). Empty slots are `null`. The per-slot `"name"` field
(v2) is shown in the slot list and on the TouchOSC preset name label after
recall.

v1 bank files (slots without `"name"`) are upgraded automatically on import.

## Patch file format

`.syx` files are raw binary SysEx dumps — 11 contiguous `F0…F7` Roland DT1
messages, exactly as received from the TB-3 (via TouchOSC's `/tb3/backup` JSON
blob, decoded back to bytes).

## Workflow example

1. **First launch** — open the **Settings** tab; confirm ports match your
   TouchOSC OSC configuration and pick a patches folder.
2. In TouchOSC: press **SYNC FROM TB-3** to load the current hardware patch.
3. In the app: select a bank slot → **Pull Patch** → the patch is saved into
   that slot.
4. To restore later: select the slot → **Send Patch** → TouchOSC sends all
   blocks to the TB-3 and updates the on-screen controls (including BCR2000 LED
   rings if connected).

## Troubleshooting

- **"PyQt5 not found" / "python-osc not found"** — re-run the setup step
  above; see the Homebrew note if `pip install --user` errors out.
- **"Python quit unexpectedly" on macOS** — use `./run-preset-manager.sh`
  (system `python3`); avoid a broken `.venv` unless you've fixed it (see the
  `TB3_PRESET_MANAGER_USE_VENV` override above).
- **Pull Patch returns nothing** — confirm TouchOSC is running, OSC ports match
  Settings, and the TB-3 layout is loaded (root script must be active to handle
  `/tb3/request_patch_export`).
