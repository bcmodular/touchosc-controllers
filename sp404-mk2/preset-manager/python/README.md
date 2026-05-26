# SP-404 backup utility

## Run

`run-backup.sh` uses **system `python3`** by default (user-site PyQt5). The project `.venv` is optional and often broken on macOS for Qt.

```bash
cd sp404-mk2/preset-manager/python
python3 -m pip install --user -r requirements.txt   # once
./run-backup.sh
```

Recommended alias:

```bash
alias sp404-backup='/Users/willellis/Documents/Development/Github/touchosc-controllers/sp404-mk2/preset-manager/python/run-backup.sh'
```

## Workflow

1. **First launch** opens the **Settings** tab — set listen/send ports to match TouchOSC, click **Continue to Backup**.
2. **Backup** tab listens continuously for `/sp404/backup`.
3. In TouchOSC: **Export** → confirm config name → saved under `dumps/` (filename is internal; library uses JSON `name`, `configVersion`, `createdAt`).
4. In TouchOSC: **Import** → select config + version in the utility (double-click to replay) → **IMPORT** on the overlay.

Right-click a **version** or **config** to rename or delete (config delete removes all versions).

| Utility | TouchOSC |
|---------|----------|
| Listen (capture) | Outgoing → same host:port |
| Send (replay) | Incoming ← same port |

Default: listen **5005**, send **5006**.

Settings auto-save to `settings.json` (no Save button). Each dump JSON must include `name`, `configVersion`, and `createdAt` (plus `version: 1` format marker). `configVersion` increments per config. Lists are sorted newest-first. Any `.json` in `dumps/` with those fields appears in the library regardless of filename.

## macOS: “Python quit unexpectedly”

Use `./run-backup.sh` (system `python3`). See prior troubleshooting if Qt **cocoa** fails; avoid broken `.venv` unless fixed.
