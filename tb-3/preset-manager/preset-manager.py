#!/usr/bin/env python3
"""
TB-3 TouchOSC Preset Manager
=============================
Saves and restores Roland TB-3 patches exchanged with the TouchOSC TB-3 controller.

Pull flow (Python → TouchOSC → Python):
  1. Press "Pull Current Patch" in the Individual Patches panel.
  2. The app sends OSC /tb3/request_patch_export to TouchOSC.
  3. TouchOSC snapshots its current state and replies with /tb3/backup (JSON).
  4. This app receives the JSON and prompts for a name to save as a .syx file.

Restore flow (Python → TouchOSC → TB-3):
  1. Select a bank (left), then a slot (middle), and press "Restore Slot".
  2. The app reads the slot's blocks from the bank JSON and sends each as a
     comma-separated hex string to TouchOSC via OSC /tb3/restore.
  3. TouchOSC parses each message, updates its own UI, and forwards the raw
     SysEx to the TB-3 hardware.

Bank format (v2):
  {"version": 2, "name": "...", "slots": {"1": {"name": "...", "blocks": [...]}, "2": null, ...}}

Requirements: pip install python-osc PyQt5
"""

import sys, os, json, time, threading
from pathlib import Path
from datetime import datetime

try:
    from PyQt5.QtWidgets import (
        QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
        QPushButton, QListWidget, QListWidgetItem, QLabel, QLineEdit,
        QStatusBar, QGroupBox, QFormLayout, QFileDialog, QMessageBox,
        QInputDialog, QSplitter
    )
    from PyQt5.QtCore import QByteArray, Qt, QThread, pyqtSignal
    from PyQt5.QtGui import QFont, QColor
except ImportError:
    print("PyQt5 not found. Install with: pip install PyQt5")
    sys.exit(1)

try:
    from pythonosc import udp_client, dispatcher, osc_server
except ImportError:
    print("python-osc not found. Install with: pip install python-osc")
    sys.exit(1)


# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

SETTINGS_FILE = Path.home() / ".tb3_preset_manager" / "settings.json"
DEFAULT_SETTINGS = {
    "listen_ip":      "0.0.0.0",
    "listen_port":    9000,
    "touchosc_ip":    "127.0.0.1",
    "touchosc_port":  9001,
    "patches_dir":    str(Path.home() / "tb3_patches"),
}


def load_settings():
    if SETTINGS_FILE.exists():
        try:
            with open(SETTINGS_FILE) as f:
                s = json.load(f)
            return {**DEFAULT_SETTINGS, **s}
        except Exception:
            pass
    return dict(DEFAULT_SETTINGS)


def save_settings(s):
    SETTINGS_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(SETTINGS_FILE, "w") as f:
        json.dump(s, f, indent=2)


# ---------------------------------------------------------------------------
# SysEx utilities
# ---------------------------------------------------------------------------

def parse_syx(data: bytes) -> list[bytes]:
    """Split a binary .syx blob into individual F0…F7 messages."""
    messages = []
    i = 0
    while i < len(data):
        if data[i] == 0xF0:
            j = i + 1
            while j < len(data) and data[j] != 0xF7:
                j += 1
            j += 1  # include F7
            messages.append(data[i:j])
            i = j
        else:
            i += 1
    return messages


def hex_string_to_bytes(hex_str: str) -> bytes:
    """Convert a contiguous hex string ('F04110…F7') to bytes."""
    return bytes.fromhex(hex_str)


def bytes_to_csv_hex(data: bytes) -> str:
    """Convert bytes to comma-separated hex for /tb3/restore ('F0,41,10,…,F7')."""
    return ",".join(f"{b:02X}" for b in data)


def json_to_syx(json_str: str) -> bytes:
    """
    Parse the JSON blob sent by TouchOSC /tb3/backup and return
    the raw binary .syx content.
    """
    obj = json.loads(json_str)
    blocks = obj.get("blocks", [])
    out = b""
    for hex_str in blocks:
        out += hex_string_to_bytes(hex_str)
    return out


def upgrade_bank_to_v2(bank_data: dict) -> dict:
    """Add name='''' to filled slots that don't have a name field (v1 → v2)."""
    for slot in (bank_data.get("slots") or {}).values():
        if slot is not None and isinstance(slot, dict) and "name" not in slot:
            slot["name"] = ""
    bank_data["version"] = 2
    return bank_data


# ---------------------------------------------------------------------------
# OSC listener thread
# ---------------------------------------------------------------------------

class OSCListenerThread(QThread):
    backup_received      = pyqtSignal(str, bytes)  # (suggested_name, syx_bytes)
    bank_backup_received = pyqtSignal(str)          # raw JSON string from TouchOSC
    status_update        = pyqtSignal(str)
    listening            = pyqtSignal(bool, str)    # (is_listening, address_or_error)

    def __init__(self, ip, port):
        super().__init__()
        self.ip   = ip
        self.port = port
        self._server = None

    def handle_backup(self, addr, *args):
        if not args:
            self.status_update.emit("Received /tb3/backup but no arguments.")
            return
        json_str = args[0]
        try:
            syx = json_to_syx(json_str)
        except Exception as e:
            self.status_update.emit(f"Parse error: {e}")
            return
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        suggested = f"tb3_patch_{ts}"
        self.status_update.emit(f"Received patch ({len(syx)} bytes) — prompting save…")
        self.backup_received.emit(suggested, syx)

    def handle_bank_backup(self, addr, *args):
        if not args:
            self.status_update.emit("Received /tb3/patchgrid/backup but no arguments.")
            return
        self.status_update.emit("Received bank from TouchOSC — prompting save…")
        self.bank_backup_received.emit(str(args[0]))

    def run(self):
        d = dispatcher.Dispatcher()
        d.map("/tb3/backup",           self.handle_backup)
        d.map("/tb3/patchgrid/backup", self.handle_bank_backup)
        try:
            self._server = osc_server.BlockingOSCUDPServer(
                (self.ip, self.port), d
            )
            addr = f"{self.ip}:{self.port}"
            self.status_update.emit(f"Listening on {addr}")
            self.listening.emit(True, addr)
            self._server.serve_forever()
        except Exception as e:
            self.status_update.emit(f"OSC listener error: {e}")
            self.listening.emit(False, str(e))

    def stop(self):
        if self._server:
            self._server.shutdown()


# ---------------------------------------------------------------------------
# Main window
# ---------------------------------------------------------------------------

EMPTY_COLOUR = QColor(150, 150, 150)

class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.settings = load_settings()
        self._listener = None
        self._client   = None

        self.setWindowTitle("TB-3 Preset Manager")
        if not self._restore_window_geometry():
            self.resize(1100, 550)
        self._build_ui()
        self._refresh_bank_list()
        self._refresh_patch_list()
        self._start_listener()

    # ------------------------------------------------------------------
    # Window geometry persistence
    # ------------------------------------------------------------------

    def _restore_window_geometry(self) -> bool:
        encoded = self.settings.get("windowGeometry")
        if not isinstance(encoded, str) or not encoded:
            return False
        return self.restoreGeometry(QByteArray.fromBase64(encoded.encode("ascii")))

    def _save_window_geometry(self):
        self.settings["windowGeometry"] = bytes(self.saveGeometry().toBase64()).decode("ascii")

    # ------------------------------------------------------------------
    # UI construction
    # ------------------------------------------------------------------

    def _build_ui(self):
        central = QWidget()
        self.setCentralWidget(central)
        root_layout = QVBoxLayout(central)
        root_layout.setContentsMargins(8, 8, 8, 8)

        splitter = QSplitter(Qt.Horizontal)

        # ── Left: bank list ──────────────────────────────────────────────
        left = QWidget()
        left_v = QVBoxLayout(left)
        left_v.setContentsMargins(0, 0, 0, 0)

        lbl_b = QLabel("Banks")
        lbl_b.setFont(QFont("", 11, QFont.Bold))
        left_v.addWidget(lbl_b)

        self.bank_list = QListWidget()
        self.bank_list.currentRowChanged.connect(self._on_bank_selection_changed)
        left_v.addWidget(self.bank_list)

        bank_osc_row = QHBoxLayout()
        self.btn_pull_bank = QPushButton("Pull from TouchOSC")
        self.btn_pull_bank.clicked.connect(self._pull_bank)
        self.btn_push_bank = QPushButton("Push to TouchOSC")
        self.btn_push_bank.clicked.connect(self._push_bank)
        self.btn_push_bank.setEnabled(False)
        bank_osc_row.addWidget(self.btn_pull_bank)
        bank_osc_row.addWidget(self.btn_push_bank)
        left_v.addLayout(bank_osc_row)

        bank_btn_row = QHBoxLayout()
        self.btn_rename_bank = QPushButton("Rename")
        self.btn_rename_bank.clicked.connect(self._rename_bank)
        self.btn_rename_bank.setEnabled(False)
        self.btn_delete_bank = QPushButton("Delete")
        self.btn_delete_bank.clicked.connect(self._delete_bank)
        self.btn_delete_bank.setEnabled(False)
        bank_btn_row.addWidget(self.btn_rename_bank)
        bank_btn_row.addWidget(self.btn_delete_bank)
        left_v.addLayout(bank_btn_row)

        bank_file_row = QHBoxLayout()
        btn_import_bank = QPushButton("Import JSON…")
        btn_import_bank.clicked.connect(self._import_bank)
        self.btn_export_bank = QPushButton("Export JSON…")
        self.btn_export_bank.clicked.connect(self._export_bank)
        self.btn_export_bank.setEnabled(False)
        bank_file_row.addWidget(btn_import_bank)
        bank_file_row.addWidget(self.btn_export_bank)
        left_v.addLayout(bank_file_row)

        splitter.addWidget(left)

        # ── Middle: slot list (for selected bank) ────────────────────────
        mid = QWidget()
        mid_v = QVBoxLayout(mid)
        mid_v.setContentsMargins(0, 0, 0, 0)

        self.lbl_slots = QLabel("Slots")
        self.lbl_slots.setFont(QFont("", 11, QFont.Bold))
        mid_v.addWidget(self.lbl_slots)

        self.slot_list = QListWidget()
        self.slot_list.currentRowChanged.connect(self._on_slot_selection_changed)
        mid_v.addWidget(self.slot_list)

        slot_btn_row = QHBoxLayout()
        self.btn_restore_slot = QPushButton("Restore Slot")
        self.btn_restore_slot.clicked.connect(self._restore_slot)
        self.btn_restore_slot.setEnabled(False)
        self.btn_rename_slot = QPushButton("Rename Slot")
        self.btn_rename_slot.clicked.connect(self._rename_slot)
        self.btn_rename_slot.setEnabled(False)
        slot_btn_row.addWidget(self.btn_restore_slot)
        slot_btn_row.addWidget(self.btn_rename_slot)
        mid_v.addLayout(slot_btn_row)

        splitter.addWidget(mid)

        # ── Right: settings + individual patches ─────────────────────────
        right = QWidget()
        right_v = QVBoxLayout(right)
        right_v.setContentsMargins(0, 0, 0, 0)

        settings_box = QGroupBox("Settings")
        form = QFormLayout(settings_box)

        self.le_listen_ip   = QLineEdit(self.settings["listen_ip"])
        self.le_listen_port = QLineEdit(str(self.settings["listen_port"]))
        self.le_tosc_ip     = QLineEdit(self.settings["touchosc_ip"])
        self.le_tosc_port   = QLineEdit(str(self.settings["touchosc_port"]))
        self.le_patches_dir = QLineEdit(self.settings["patches_dir"])
        self.le_patches_dir.setToolTip(self.settings["patches_dir"])
        self.le_patches_dir.textChanged.connect(self.le_patches_dir.setToolTip)

        form.addRow("Listen IP:",      self.le_listen_ip)
        form.addRow("Listen port:",    self.le_listen_port)
        form.addRow("TouchOSC IP:",    self.le_tosc_ip)
        form.addRow("TouchOSC port:",  self.le_tosc_port)
        form.addRow("Patches folder:", self.le_patches_dir)

        btn_browse = QPushButton("Browse…")
        btn_browse.clicked.connect(self._browse_dir)
        form.addRow("", btn_browse)

        btn_save_settings = QPushButton("Restart listener")
        btn_save_settings.clicked.connect(self._apply_settings)
        form.addRow("", btn_save_settings)

        self.lbl_listener_status = QLabel("○ Starting…")
        form.addRow("Status:", self.lbl_listener_status)

        right_v.addWidget(settings_box)

        patches_box = QGroupBox("Individual Patches")
        patches_v = QVBoxLayout(patches_box)

        self.patch_list = QListWidget()
        self.patch_list.setMaximumHeight(130)
        self.patch_list.currentRowChanged.connect(self._on_selection_changed)
        patches_v.addWidget(self.patch_list)

        pull_row = QHBoxLayout()
        btn_pull_patch = QPushButton("Pull Current Patch from TB-3")
        btn_pull_patch.clicked.connect(self._pull_patch)
        pull_row.addWidget(btn_pull_patch)
        patches_v.addLayout(pull_row)

        patch_btn_row = QHBoxLayout()
        self.btn_restore = QPushButton("Restore")
        self.btn_restore.clicked.connect(self._restore_patch)
        self.btn_restore.setEnabled(False)
        self.btn_delete = QPushButton("Delete")
        self.btn_delete.clicked.connect(self._delete_patch)
        self.btn_delete.setEnabled(False)
        patch_btn_row.addWidget(self.btn_restore)
        patch_btn_row.addWidget(self.btn_delete)
        patches_v.addLayout(patch_btn_row)

        import_row = QHBoxLayout()
        btn_import = QPushButton("Import .syx…")
        btn_import.clicked.connect(self._import_syx)
        self.btn_export = QPushButton("Export .syx…")
        self.btn_export.clicked.connect(self._export_syx)
        self.btn_export.setEnabled(False)
        import_row.addWidget(btn_import)
        import_row.addWidget(self.btn_export)
        patches_v.addLayout(import_row)

        right_v.addWidget(patches_box)
        right_v.addStretch()

        splitter.addWidget(right)
        splitter.setSizes([320, 380, 340])
        root_layout.addWidget(splitter)

        self.statusBar().showMessage("Ready.")

    # ------------------------------------------------------------------
    # Bank list management
    # ------------------------------------------------------------------

    def _banks_dir(self) -> Path:
        p = Path(self.settings["patches_dir"]) / "banks"
        p.mkdir(parents=True, exist_ok=True)
        return p

    def _bank_name_from_path(self, p: Path) -> str:
        """Return the user-facing bank name from a .tb3bank.json path."""
        return p.name.removesuffix(".tb3bank.json")

    def _current_bank_path(self) -> Path | None:
        item = self.bank_list.currentItem()
        if not item:
            return None
        return self._banks_dir() / (item.text() + ".tb3bank.json")

    def _refresh_bank_list(self):
        self.bank_list.clear()
        for f in sorted(self._banks_dir().glob("*.tb3bank.json")):
            self.bank_list.addItem(self._bank_name_from_path(f))
        self._on_bank_selection_changed(self.bank_list.currentRow())

    def _on_bank_selection_changed(self, row):
        has = row >= 0 and self.bank_list.item(row) is not None
        self.btn_push_bank.setEnabled(has)
        self.btn_rename_bank.setEnabled(has)
        self.btn_delete_bank.setEnabled(has)
        self.btn_export_bank.setEnabled(has)
        bank_name = self.bank_list.item(row).text() if has else ""
        self.lbl_slots.setText(f"Slots — {bank_name}" if bank_name else "Slots")
        self._refresh_slot_list()

    def _pull_bank(self):
        """Request the current patch grid state from TouchOSC."""
        client = self._get_client()
        if not client:
            return
        try:
            client.send_message("/tb3/patchgrid/request_backup", "")
            self.statusBar().showMessage("Requested bank from TouchOSC — waiting for response…")
        except Exception as e:
            self.statusBar().showMessage(f"Send error: {e}")

    def _handle_bank_backup_received(self, json_str: str):
        """Called (in main thread) when /tb3/patchgrid/backup arrives."""
        try:
            bank_data = json.loads(json_str)
        except Exception as e:
            self.statusBar().showMessage(f"Bank parse error: {e}")
            return
        upgrade_bank_to_v2(bank_data)
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        name, ok = QInputDialog.getText(
            self, "Save Bank", "Bank name:", text=f"bank_{ts}"
        )
        if not (ok and name.strip()):
            return
        bank_data["name"]      = name.strip()
        bank_data["createdAt"] = datetime.now().isoformat()
        path = self._banks_dir() / f"{name.strip()}.tb3bank.json"
        with open(path, "w") as f:
            json.dump(bank_data, f, indent=2)
        self._refresh_bank_list()
        items = self.bank_list.findItems(name.strip(), Qt.MatchExactly)
        if items:
            self.bank_list.setCurrentItem(items[0])
        self.statusBar().showMessage(f"Saved bank: {path.name}")

    def _push_bank(self):
        """Send the selected bank to TouchOSC (/tb3/patchgrid/restore)."""
        path = self._current_bank_path()
        if not path or not path.exists():
            return
        with open(path) as f:
            bank_data = json.load(f)
        client = self._get_client()
        if not client:
            return
        try:
            client.send_message("/tb3/patchgrid/restore", json.dumps(bank_data))
            self.statusBar().showMessage(f"Pushed bank '{path.stem}' to TouchOSC.")
        except Exception as e:
            self.statusBar().showMessage(f"Send error: {e}")

    def _rename_bank(self):
        path = self._current_bank_path()
        if not path:
            return
        old_name = self._bank_name_from_path(path)
        name, ok = QInputDialog.getText(self, "Rename Bank", "New name:", text=old_name)
        if not (ok and name.strip() and name.strip() != old_name):
            return
        new_path = path.parent / f"{name.strip()}.tb3bank.json"
        try:
            with open(path) as f:
                data = json.load(f)
            data["name"] = name.strip()
            with open(path, "w") as f:
                json.dump(data, f, indent=2)
        except Exception:
            pass
        path.rename(new_path)
        self._refresh_bank_list()
        items = self.bank_list.findItems(name.strip(), Qt.MatchExactly)
        if items:
            self.bank_list.setCurrentItem(items[0])

    def _delete_bank(self):
        path = self._current_bank_path()
        if not path:
            return
        name = self._bank_name_from_path(path)
        r = QMessageBox.question(
            self, "Delete Bank", f"Delete bank '{name}'?",
            QMessageBox.Yes | QMessageBox.No
        )
        if r == QMessageBox.Yes:
            path.unlink(missing_ok=True)
            self._refresh_bank_list()

    def _import_bank(self):
        path, _ = QFileDialog.getOpenFileName(
            self, "Import bank file", str(Path.home()),
            "TB-3 Bank (*.tb3bank.json);;JSON (*.json);;All (*)"
        )
        if not path:
            return
        src = Path(path)
        default_name = src.name.removesuffix(".tb3bank.json").removesuffix(".json")
        name, ok = QInputDialog.getText(
            self, "Import Bank", "Bank name:", text=default_name
        )
        if not (ok and name.strip()):
            return
        import shutil
        dst = self._banks_dir() / f"{name.strip()}.tb3bank.json"
        shutil.copy2(src, dst)
        self._refresh_bank_list()
        items = self.bank_list.findItems(name.strip(), Qt.MatchExactly)
        if items:
            self.bank_list.setCurrentItem(items[0])
        self.statusBar().showMessage(f"Imported bank: {dst.name}")

    def _export_bank(self):
        path = self._current_bank_path()
        if not path or not path.exists():
            return
        dst, _ = QFileDialog.getSaveFileName(
            self, "Export bank file", str(Path.home() / path.name),
            "TB-3 Bank (*.tb3bank.json);;All (*)"
        )
        if dst:
            import shutil
            shutil.copy2(path, dst)
            self.statusBar().showMessage(f"Exported bank to {dst}")

    # ------------------------------------------------------------------
    # Slot list (slots within the selected bank)
    # ------------------------------------------------------------------

    def _refresh_slot_list(self):
        self.slot_list.clear()
        path = self._current_bank_path()
        if not path or not path.exists():
            self._on_slot_selection_changed(-1)
            return
        try:
            with open(path) as f:
                bank_data = json.load(f)
        except Exception:
            self._on_slot_selection_changed(-1)
            return
        slots = bank_data.get("slots", {})
        for i in range(1, 17):
            slot = slots.get(str(i))
            filled = slot is not None and isinstance(slot, dict) and slot.get("blocks")
            if filled:
                name = (slot.get("name") or "").strip()
                label = f"Slot {i:2d}:  {name}" if name else f"Slot {i:2d}:  [unnamed]"
            else:
                label = f"Slot {i:2d}:  (empty)"
            item = QListWidgetItem(label)
            if not filled:
                item.setForeground(EMPTY_COLOUR)
            self.slot_list.addItem(item)
        self._on_slot_selection_changed(self.slot_list.currentRow())

    def _on_slot_selection_changed(self, row):
        # Only enable actions for filled slots.
        filled = False
        if row >= 0 and self.slot_list.item(row) is not None:
            item = self.slot_list.item(row)
            filled = item.foreground().color() != EMPTY_COLOUR
        self.btn_restore_slot.setEnabled(filled)
        self.btn_rename_slot.setEnabled(filled)

    def _current_slot_info(self):
        """Return (slot_num, slot_dict, bank_path, bank_data) or None."""
        bank_path = self._current_bank_path()
        if not bank_path or not bank_path.exists():
            return None
        row = self.slot_list.currentRow()
        if row < 0:
            return None
        slot_num = row + 1
        try:
            with open(bank_path) as f:
                bank_data = json.load(f)
        except Exception:
            return None
        slot = bank_data.get("slots", {}).get(str(slot_num))
        if not slot or not isinstance(slot, dict) or not slot.get("blocks"):
            return None
        return slot_num, slot, bank_path, bank_data

    def _restore_slot(self):
        info = self._current_slot_info()
        if info is None:
            return
        _, slot, _, _ = info
        blocks = slot.get("blocks", [])
        if not blocks:
            return
        client = self._get_client()
        if not client:
            return
        sent = 0
        for hex_str in blocks:
            msg_bytes = hex_string_to_bytes(hex_str)
            csv = bytes_to_csv_hex(msg_bytes)
            try:
                client.send_message("/tb3/restore", csv)
                sent += 1
                self.statusBar().showMessage(f"Restoring block {sent}/{len(blocks)}…")
                QApplication.processEvents()
                time.sleep(0.015)
            except Exception as e:
                self.statusBar().showMessage(f"Send error: {e}")
                return
        self.statusBar().showMessage(f"Restored {sent} blocks to TouchOSC.")

    def _rename_slot(self):
        info = self._current_slot_info()
        if info is None:
            return
        slot_num, slot, bank_path, bank_data = info
        current_name = (slot.get("name") or "").strip()
        name, ok = QInputDialog.getText(
            self, "Rename Slot", f"Name for slot {slot_num}:", text=current_name
        )
        if not ok:
            return
        bank_data["slots"][str(slot_num)]["name"] = name.strip()
        bank_data["version"] = 2
        with open(bank_path, "w") as f:
            json.dump(bank_data, f, indent=2)
        self._refresh_slot_list()
        self.slot_list.setCurrentRow(slot_num - 1)

    # ------------------------------------------------------------------
    # Individual patch management (.syx files)
    # ------------------------------------------------------------------

    def _patches_dir(self) -> Path:
        p = Path(self.settings["patches_dir"])
        p.mkdir(parents=True, exist_ok=True)
        return p

    def _refresh_patch_list(self):
        self.patch_list.clear()
        for f in sorted(self._patches_dir().glob("*.syx")):
            self.patch_list.addItem(f.stem)
        self._on_selection_changed(self.patch_list.currentRow())

    def _current_syx_path(self) -> Path | None:
        item = self.patch_list.currentItem()
        if not item:
            return None
        return self._patches_dir() / (item.text() + ".syx")

    def _on_selection_changed(self, row):
        has = row >= 0 and self.patch_list.item(row) is not None
        self.btn_restore.setEnabled(has)
        self.btn_delete.setEnabled(has)
        self.btn_export.setEnabled(has)

    def _pull_patch(self):
        """Request a snapshot of the current TB-3 patch via TouchOSC."""
        client = self._get_client()
        if not client:
            return
        try:
            client.send_message("/tb3/request_patch_export", "")
            self.statusBar().showMessage("Requested current patch from TouchOSC — waiting…")
        except Exception as e:
            self.statusBar().showMessage(f"Send error: {e}")

    def _save_patch(self, name: str, syx_bytes: bytes):
        """Save bytes to <patches_dir>/<name>.syx"""
        path = self._patches_dir() / f"{name}.syx"
        with open(path, "wb") as f:
            f.write(syx_bytes)
        self._refresh_patch_list()
        items = self.patch_list.findItems(name, Qt.MatchExactly)
        if items:
            self.patch_list.setCurrentItem(items[0])
        self.statusBar().showMessage(f"Saved: {path.name}")

    def _handle_backup_received(self, suggested_name: str, syx_bytes: bytes):
        """Called (in main thread) when /tb3/backup arrives."""
        name, ok = QInputDialog.getText(
            self, "Save Patch", "Patch name:", text=suggested_name
        )
        if ok and name.strip():
            self._save_patch(name.strip(), syx_bytes)

    def _restore_patch(self):
        path = self._current_syx_path()
        if not path or not path.exists():
            return
        with open(path, "rb") as f:
            syx_data = f.read()
        messages = parse_syx(syx_data)
        if not messages:
            QMessageBox.warning(self, "Restore", "No SysEx messages found in file.")
            return
        client = self._get_client()
        if not client:
            return
        sent = 0
        for msg in messages:
            csv = bytes_to_csv_hex(msg)
            try:
                client.send_message("/tb3/restore", csv)
                sent += 1
                self.statusBar().showMessage(f"Restoring block {sent}/{len(messages)}…")
                QApplication.processEvents()
                time.sleep(0.015)
            except Exception as e:
                self.statusBar().showMessage(f"Send error: {e}")
                return
        self.statusBar().showMessage(
            f"Restored {sent} SysEx blocks to TouchOSC ({path.name})"
        )

    def _import_syx(self):
        path, _ = QFileDialog.getOpenFileName(
            self, "Import SysEx file", str(Path.home()), "SysEx (*.syx);;All (*)"
        )
        if not path:
            return
        src = Path(path)
        with open(src, "rb") as f:
            syx_bytes = f.read()
        name, ok = QInputDialog.getText(
            self, "Import Patch", "Patch name:", text=src.stem
        )
        if ok and name.strip():
            self._save_patch(name.strip(), syx_bytes)

    def _export_syx(self):
        path = self._current_syx_path()
        if not path or not path.exists():
            return
        dst, _ = QFileDialog.getSaveFileName(
            self, "Export SysEx file", str(Path.home() / path.name), "SysEx (*.syx)"
        )
        if dst:
            import shutil
            shutil.copy2(path, dst)
            self.statusBar().showMessage(f"Exported to {dst}")

    def _delete_patch(self):
        path = self._current_syx_path()
        if not path:
            return
        r = QMessageBox.question(
            self, "Delete", f"Delete '{path.stem}'?",
            QMessageBox.Yes | QMessageBox.No
        )
        if r == QMessageBox.Yes:
            path.unlink(missing_ok=True)
            self._refresh_patch_list()

    # ------------------------------------------------------------------
    # Settings
    # ------------------------------------------------------------------

    def _browse_dir(self):
        d = QFileDialog.getExistingDirectory(
            self, "Select patches folder", self.settings["patches_dir"]
        )
        if d:
            self.le_patches_dir.setText(d)

    def _apply_settings(self):
        self.settings.update({
            "listen_ip":     self.le_listen_ip.text().strip(),
            "listen_port":   int(self.le_listen_port.text().strip()),
            "touchosc_ip":   self.le_tosc_ip.text().strip(),
            "touchosc_port": int(self.le_tosc_port.text().strip()),
            "patches_dir":   self.le_patches_dir.text().strip(),
        })
        save_settings(self.settings)
        self._client = None
        self._start_listener()
        self._refresh_patch_list()
        self._refresh_bank_list()
        self.statusBar().showMessage("Settings saved. Listener restarted.")

    # ------------------------------------------------------------------
    # OSC client / listener
    # ------------------------------------------------------------------

    def _get_client(self):
        if self._client is None:
            try:
                self._client = udp_client.SimpleUDPClient(
                    self.settings["touchosc_ip"],
                    self.settings["touchosc_port"]
                )
            except Exception as e:
                QMessageBox.critical(self, "OSC Error", str(e))
                return None
        return self._client

    def _start_listener(self):
        if self._listener and self._listener.isRunning():
            self._listener.stop()
            self._listener.wait()
        self.lbl_listener_status.setText("○ Starting…")
        self.lbl_listener_status.setStyleSheet("color: palette(text);")
        self._listener = OSCListenerThread(
            self.settings["listen_ip"],
            self.settings["listen_port"]
        )
        self._listener.backup_received.connect(self._handle_backup_received)
        self._listener.bank_backup_received.connect(self._handle_bank_backup_received)
        self._listener.status_update.connect(self.statusBar().showMessage)
        self._listener.listening.connect(self._on_listener_state_changed)
        self._listener.start()

    def _on_listener_state_changed(self, ok, info):
        if ok:
            self.lbl_listener_status.setText(f"● Listening on {info}")
            self.lbl_listener_status.setStyleSheet("color: #2a8a2a;")
        else:
            self.lbl_listener_status.setText(f"● Error: {info}")
            self.lbl_listener_status.setStyleSheet("color: #c0392b;")

    def closeEvent(self, event):
        if self._listener:
            self._listener.stop()
            self._listener.wait()
        self._save_window_geometry()
        save_settings(self.settings)
        event.accept()


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    app = QApplication(sys.argv)
    app.setApplicationName("TB-3 Preset Manager")
    win = MainWindow()
    win.show()
    sys.exit(app.exec_())
