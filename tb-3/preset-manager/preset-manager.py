#!/usr/bin/env python3
"""
TB-3 TouchOSC Preset Manager
=============================
Saves and restores Roland TB-3 patches exchanged with the TouchOSC TB-3 controller.

Library layout:
  Left  — Bank list.  First entry "(individual patches)" shows standalone .syx files
           in the top-level patches folder.  Real banks show 16 numbered slots.
  Right — Slot list for the selected bank / orphan patches.

OSC paths:
  Python → TouchOSC:
    /tb3/request_patch_export       Request snapshot of current patch → /tb3/backup
    /tb3/patchgrid/request_backup   Request all 16 grid slots → /tb3/patchgrid/backup
    /tb3/patchgrid/restore          Load 16 slots into grid (grid only, no TB-3 SysEx)
    /tb3/restore                    Restore one SysEx block to UI + TB-3 hardware

  TouchOSC → Python:
    /tb3/backup                     Single-patch JSON snapshot
    /tb3/patchgrid/backup           Bank JSON snapshot

Bank format (v2):
  {"version": 2, "name": "...", "slots": {"1": {"name": "...", "blocks": [...]}, ...}}

Requirements: pip install python-osc PyQt5
"""

import sys, json, time, shutil
from pathlib import Path
from datetime import datetime

try:
    from PyQt5.QtWidgets import (
        QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
        QPushButton, QListWidget, QListWidgetItem, QLabel, QLineEdit,
        QGroupBox, QFormLayout, QFileDialog, QMessageBox, QInputDialog,
        QSplitter, QTabWidget
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
    "listen_ip":     "0.0.0.0",
    "listen_port":   9000,
    "touchosc_ip":   "127.0.0.1",
    "touchosc_port": 9001,
    "patches_dir":   str(Path.home() / "tb3_patches"),
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

def parse_syx(data: bytes) -> list:
    messages, i = [], 0
    while i < len(data):
        if data[i] == 0xF0:
            j = i + 1
            while j < len(data) and data[j] != 0xF7:
                j += 1
            j += 1
            messages.append(data[i:j])
            i = j
        else:
            i += 1
    return messages


def hex_string_to_bytes(hex_str: str) -> bytes:
    return bytes.fromhex(hex_str)


def bytes_to_csv_hex(data: bytes) -> str:
    return ",".join(f"{b:02X}" for b in data)


def syx_bytes_to_block_list(syx_data: bytes) -> list:
    """Convert raw .syx bytes to the list-of-hex-strings format used in bank JSON."""
    return [m.hex().upper() for m in parse_syx(syx_data)]


def json_to_syx(json_str: str) -> bytes:
    obj = json.loads(json_str)
    return b"".join(hex_string_to_bytes(h) for h in obj.get("blocks", []))


def upgrade_bank_to_v2(bank_data: dict) -> dict:
    for slot in (bank_data.get("slots") or {}).values():
        if slot is not None and isinstance(slot, dict) and "name" not in slot:
            slot["name"] = ""
    bank_data["version"] = 2
    return bank_data


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

EMPTY_COLOUR  = QColor(150, 150, 150)
ORPHAN_COLOUR = QColor(100, 130, 200)
ORPHAN_KEY    = "__orphan__"


# ---------------------------------------------------------------------------
# OSC listener thread
# ---------------------------------------------------------------------------

class OSCListenerThread(QThread):
    backup_received      = pyqtSignal(str, bytes)   # suggested_name, syx_bytes
    bank_backup_received = pyqtSignal(str)           # raw JSON string
    status_update        = pyqtSignal(str)
    listening            = pyqtSignal(bool, str)

    def __init__(self, ip, port):
        super().__init__()
        self.ip, self.port = ip, port
        self._server = None

    def handle_backup(self, addr, *args):
        if not args:
            self.status_update.emit("Received /tb3/backup but no arguments.")
            return
        try:
            obj = json.loads(args[0])
            syx = b"".join(hex_string_to_bytes(h) for h in obj.get("blocks", []))
        except Exception as e:
            self.status_update.emit(f"Parse error: {e}")
            return
        # Emit the raw preset name (may be ""); callers generate a fallback if needed.
        preset_name = (obj.get("name") or "").strip()
        self.status_update.emit(f"Received patch ({len(syx)} bytes).")
        self.backup_received.emit(preset_name, syx)

    def handle_bank_backup(self, addr, *args):
        if not args:
            self.status_update.emit("Received /tb3/patchgrid/backup but no arguments.")
            return
        self.status_update.emit("Received bank from TouchOSC.")
        self.bank_backup_received.emit(str(args[0]))

    def run(self):
        d = dispatcher.Dispatcher()
        d.map("/tb3/backup",           self.handle_backup)
        d.map("/tb3/patchgrid/backup", self.handle_bank_backup)
        try:
            self._server = osc_server.BlockingOSCUDPServer((self.ip, self.port), d)
            addr = f"{self.ip}:{self.port}"
            self.listening.emit(True, addr)
            self.status_update.emit(f"Listening on {addr}")
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

class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.settings  = load_settings()
        self._listener = None
        self._client   = None
        # Snapshot of pull target at the moment "Pull Current Patch" is pressed.
        # None → orphan (add new file); int → bank slot number to write into.
        self._pending_pull_slot      = None
        self._pending_pull_bank_path = None

        self.setWindowTitle("TB-3 Preset Manager")
        if not self._restore_window_geometry():
            self.resize(900, 560)
        self._build_ui()
        self._refresh_bank_list()
        self._start_listener()

    # ------------------------------------------------------------------
    # Geometry persistence
    # ------------------------------------------------------------------

    def _restore_window_geometry(self) -> bool:
        encoded = self.settings.get("windowGeometry")
        if not isinstance(encoded, str) or not encoded:
            return False
        return self.restoreGeometry(QByteArray.fromBase64(encoded.encode("ascii")))

    def _save_window_geometry(self):
        self.settings["windowGeometry"] = (
            bytes(self.saveGeometry().toBase64()).decode("ascii")
        )

    # ------------------------------------------------------------------
    # UI
    # ------------------------------------------------------------------

    def _build_ui(self):
        tabs = QTabWidget()
        self.setCentralWidget(tabs)

        # ── Library tab ──────────────────────────────────────────────────
        library = QWidget()
        lib_layout = QVBoxLayout(library)
        lib_layout.setContentsMargins(8, 8, 8, 8)

        splitter = QSplitter(Qt.Horizontal)

        # Left — bank list
        left = QWidget()
        lv = QVBoxLayout(left)
        lv.setContentsMargins(0, 0, 0, 0)

        lv.addWidget(self._bold_label("Banks"))

        self.bank_list = QListWidget()
        self.bank_list.currentRowChanged.connect(self._on_bank_changed)
        lv.addWidget(self.bank_list)

        row = QHBoxLayout()
        self.btn_pull_bank = QPushButton("Pull Bank")
        self.btn_pull_bank.clicked.connect(self._pull_bank)
        self.btn_push_bank = QPushButton("Send Bank")
        self.btn_push_bank.clicked.connect(self._push_bank)
        self.btn_push_bank.setEnabled(False)
        row.addWidget(self.btn_pull_bank)
        row.addWidget(self.btn_push_bank)
        lv.addLayout(row)

        row2 = QHBoxLayout()
        self.btn_rename_bank = QPushButton("Rename Bank")
        self.btn_rename_bank.clicked.connect(self._rename_bank)
        self.btn_rename_bank.setEnabled(False)
        self.btn_delete_bank = QPushButton("Delete Bank")
        self.btn_delete_bank.clicked.connect(self._delete_bank)
        self.btn_delete_bank.setEnabled(False)
        row2.addWidget(self.btn_rename_bank)
        row2.addWidget(self.btn_delete_bank)
        lv.addLayout(row2)

        row3 = QHBoxLayout()
        btn_new_bank = QPushButton("New Bank")
        btn_new_bank.clicked.connect(self._new_bank)
        btn_import_bank = QPushButton("Import JSON…")
        btn_import_bank.clicked.connect(self._import_bank)
        self.btn_export_bank = QPushButton("Export JSON…")
        self.btn_export_bank.clicked.connect(self._export_bank)
        self.btn_export_bank.setEnabled(False)
        row3.addWidget(btn_new_bank)
        row3.addWidget(btn_import_bank)
        row3.addWidget(self.btn_export_bank)
        lv.addLayout(row3)

        splitter.addWidget(left)

        # Right — slot list
        right = QWidget()
        rv = QVBoxLayout(right)
        rv.setContentsMargins(0, 0, 0, 0)

        self.lbl_slots = self._bold_label("Slots")
        rv.addWidget(self.lbl_slots)

        self.slot_list = QListWidget()
        self.slot_list.currentRowChanged.connect(self._on_slot_changed)
        rv.addWidget(self.slot_list)

        # Restore / rename / export / delete (require a filled slot)
        slot_row1 = QHBoxLayout()
        self.btn_restore_slot = QPushButton("Send Patch")
        self.btn_restore_slot.clicked.connect(self._restore_slot)
        self.btn_restore_slot.setEnabled(False)
        self.btn_rename_slot = QPushButton("Rename Preset")
        self.btn_rename_slot.clicked.connect(self._rename_slot)
        self.btn_rename_slot.setEnabled(False)
        self.btn_export_syx = QPushButton("Export .syx…")
        self.btn_export_syx.clicked.connect(self._export_syx)
        self.btn_export_syx.setEnabled(False)
        self.btn_delete_slot = QPushButton("Empty Slot")
        self.btn_delete_slot.clicked.connect(self._delete_slot)
        self.btn_delete_slot.setEnabled(False)
        slot_row1.addWidget(self.btn_restore_slot)
        slot_row1.addWidget(self.btn_rename_slot)
        slot_row1.addWidget(self.btn_export_syx)
        slot_row1.addWidget(self.btn_delete_slot)
        rv.addLayout(slot_row1)

        # Pull / Import — write into the selected slot (or orphan folder)
        # Bank mode: requires a slot selected; orphan mode: always enabled.
        slot_row2 = QHBoxLayout()
        self.btn_pull_patch = QPushButton("Pull Patch")
        self.btn_pull_patch.setToolTip(
            "Request the current TB-3 patch from TouchOSC and write it into "
            "the selected slot (bank mode) or the orphan patches folder."
        )
        self.btn_pull_patch.clicked.connect(self._pull_patch)
        self.btn_pull_patch.setEnabled(False)
        self.btn_import_syx = QPushButton("Import .syx…")
        self.btn_import_syx.setToolTip(
            "Import a .syx file and write it into the selected slot (bank mode) "
            "or the orphan patches folder."
        )
        self.btn_import_syx.clicked.connect(self._import_syx)
        self.btn_import_syx.setEnabled(False)
        slot_row2.addWidget(self.btn_pull_patch)
        slot_row2.addWidget(self.btn_import_syx)
        rv.addLayout(slot_row2)

        splitter.addWidget(right)
        splitter.setSizes([340, 520])
        lib_layout.addWidget(splitter)
        tabs.addTab(library, "Library")

        # ── Settings tab ─────────────────────────────────────────────────
        settings_tab = QWidget()
        sv = QVBoxLayout(settings_tab)
        sv.setContentsMargins(12, 12, 12, 12)

        box = QGroupBox("Network")
        form = QFormLayout(box)
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
        btn_restart = QPushButton("Restart listener")
        btn_restart.clicked.connect(self._apply_settings)
        form.addRow("", btn_restart)
        self.lbl_listener_status = QLabel("○ Starting…")
        form.addRow("Status:", self.lbl_listener_status)
        sv.addWidget(box)
        sv.addStretch()

        tabs.addTab(settings_tab, "Settings")

        self.statusBar().showMessage("Ready.")

    @staticmethod
    def _bold_label(text: str) -> QLabel:
        lbl = QLabel(text)
        lbl.setFont(QFont("", 11, QFont.Bold))
        return lbl

    # ------------------------------------------------------------------
    # Bank list
    # ------------------------------------------------------------------

    def _banks_dir(self) -> Path:
        p = Path(self.settings["patches_dir"]) / "banks"
        p.mkdir(parents=True, exist_ok=True)
        return p

    def _patches_dir(self) -> Path:
        p = Path(self.settings["patches_dir"])
        p.mkdir(parents=True, exist_ok=True)
        return p

    def _bank_name_from_path(self, p: Path) -> str:
        return p.name.removesuffix(".tb3bank.json")

    def _current_bank_path(self):
        item = self.bank_list.currentItem()
        if not item:
            return None
        data = item.data(Qt.UserRole)
        return None if data == ORPHAN_KEY else (Path(data) if data else None)

    def _is_orphan_mode(self) -> bool:
        item = self.bank_list.currentItem()
        return item is not None and item.data(Qt.UserRole) == ORPHAN_KEY

    def _refresh_bank_list(self):
        prev_key = None
        cur = self.bank_list.currentItem()
        if cur:
            prev_key = cur.data(Qt.UserRole)

        self.bank_list.clear()

        orphan = QListWidgetItem("(individual patches)")
        orphan.setData(Qt.UserRole, ORPHAN_KEY)
        orphan.setForeground(ORPHAN_COLOUR)
        self.bank_list.addItem(orphan)

        for f in sorted(self._banks_dir().glob("*.tb3bank.json")):
            item = QListWidgetItem(self._bank_name_from_path(f))
            item.setData(Qt.UserRole, str(f))
            self.bank_list.addItem(item)

        restored = False
        if prev_key:
            for i in range(self.bank_list.count()):
                if self.bank_list.item(i).data(Qt.UserRole) == prev_key:
                    self.bank_list.setCurrentRow(i)
                    restored = True
                    break
        if not restored:
            self.bank_list.setCurrentRow(0)

    def _on_bank_changed(self, row):
        is_bank = (row > 0 and
                   self.bank_list.item(row) is not None and
                   self.bank_list.item(row).data(Qt.UserRole) != ORPHAN_KEY)
        self.btn_push_bank.setEnabled(is_bank)
        self.btn_rename_bank.setEnabled(is_bank)
        self.btn_delete_bank.setEnabled(is_bank)
        self.btn_export_bank.setEnabled(is_bank)

        if self._is_orphan_mode():
            self.lbl_slots.setText("Individual Patches")
        elif is_bank:
            self.lbl_slots.setText(f"Slots — {self.bank_list.item(row).text()}")
        else:
            self.lbl_slots.setText("Slots")

        self._refresh_slot_list()

    def _pull_bank(self):
        client = self._get_client()
        if not client:
            return
        try:
            client.send_message("/tb3/patchgrid/request_backup", "")
            self.statusBar().showMessage("Requested bank from TouchOSC…")
        except Exception as e:
            self.statusBar().showMessage(f"Send error: {e}")

    def _handle_bank_backup_received(self, json_str: str):
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
        for i in range(self.bank_list.count()):
            if self.bank_list.item(i).data(Qt.UserRole) == str(path):
                self.bank_list.setCurrentRow(i)
                break
        self.statusBar().showMessage(f"Saved bank: {path.name}")

    def _push_bank(self):
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
            self.statusBar().showMessage(f"Pushed bank '{self._bank_name_from_path(path)}' to TouchOSC.")
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
        for i in range(self.bank_list.count()):
            if self.bank_list.item(i).data(Qt.UserRole) == str(new_path):
                self.bank_list.setCurrentRow(i)
                break

    def _delete_bank(self):
        path = self._current_bank_path()
        if not path:
            return
        r = QMessageBox.question(
            self, "Delete Bank",
            f"Delete bank '{self._bank_name_from_path(path)}'?",
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
        default = src.name.removesuffix(".tb3bank.json").removesuffix(".json")
        name, ok = QInputDialog.getText(self, "Import Bank", "Bank name:", text=default)
        if not (ok and name.strip()):
            return
        dst = self._banks_dir() / f"{name.strip()}.tb3bank.json"
        shutil.copy2(src, dst)
        self._refresh_bank_list()
        for i in range(self.bank_list.count()):
            if self.bank_list.item(i).data(Qt.UserRole) == str(dst):
                self.bank_list.setCurrentRow(i)
                break
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
            shutil.copy2(path, dst)
            self.statusBar().showMessage(f"Exported bank to {dst}")

    def _new_bank(self):
        name, ok = QInputDialog.getText(self, "New Bank", "Bank name:")
        if not (ok and name.strip()):
            return
        path = self._banks_dir() / f"{name.strip()}.tb3bank.json"
        if path.exists():
            r = QMessageBox.question(
                self, "Overwrite?",
                f"A bank named '{name.strip()}' already exists.\nOverwrite it?",
                QMessageBox.Yes | QMessageBox.No
            )
            if r != QMessageBox.Yes:
                return
        bank_data = {
            "version":   2,
            "name":      name.strip(),
            "createdAt": datetime.now().isoformat(),
            "slots":     {str(i): None for i in range(1, 17)},
        }
        with open(path, "w") as f:
            json.dump(bank_data, f, indent=2)
        self._refresh_bank_list()
        for i in range(self.bank_list.count()):
            if self.bank_list.item(i).data(Qt.UserRole) == str(path):
                self.bank_list.setCurrentRow(i)
                break
        self.statusBar().showMessage(f"Created bank: {name.strip()}")

    # ------------------------------------------------------------------
    # Slot list
    # ------------------------------------------------------------------

    def _refresh_slot_list(self):
        self.slot_list.clear()
        if self._is_orphan_mode():
            self._populate_orphan_slots()
        else:
            self._populate_bank_slots()
        self._on_slot_changed(self.slot_list.currentRow())

    def _populate_orphan_slots(self):
        for f in sorted(self._patches_dir().glob("*.syx")):
            item = QListWidgetItem(f.stem)
            item.setData(Qt.UserRole, str(f))
            self.slot_list.addItem(item)

    def _populate_bank_slots(self):
        path = self._current_bank_path()
        if not path or not path.exists():
            return
        try:
            with open(path) as f:
                bank_data = json.load(f)
        except Exception:
            return
        slots = bank_data.get("slots", {})
        for i in range(1, 17):
            slot   = slots.get(str(i))
            filled = slot is not None and isinstance(slot, dict) and slot.get("blocks")
            if filled:
                name  = (slot.get("name") or "").strip()
                label = f"Slot {i:2d}:  {name}" if name else f"Slot {i:2d}:  [unnamed]"
            else:
                label = f"Slot {i:2d}:  (empty)"
            item = QListWidgetItem(label)
            item.setData(Qt.UserRole,     i)       # int slot number
            item.setData(Qt.UserRole + 1, filled)  # bool
            if not filled:
                item.setForeground(EMPTY_COLOUR)
            self.slot_list.addItem(item)

    def _slot_is_filled(self, row: int) -> bool:
        item = self.slot_list.item(row)
        if not item:
            return False
        if self._is_orphan_mode():
            return True  # every listed orphan item is a real file
        return bool(item.data(Qt.UserRole + 1))

    def _on_slot_changed(self, row):
        has_item = row >= 0 and self.slot_list.item(row) is not None
        filled   = has_item and self._slot_is_filled(row)

        # Actions that require a filled slot
        self.btn_restore_slot.setEnabled(filled)
        self.btn_rename_slot.setEnabled(filled)
        self.btn_export_syx.setEnabled(filled)
        self.btn_delete_slot.setEnabled(filled)

        # Pull / Import:
        #   orphan mode → always enabled (adds new file to folder)
        #   bank mode   → require a slot selection (any row, even empty)
        if self._is_orphan_mode():
            self.btn_pull_patch.setEnabled(True)
            self.btn_import_syx.setEnabled(True)
        else:
            self.btn_pull_patch.setEnabled(has_item)
            self.btn_import_syx.setEnabled(has_item)

    # ------------------------------------------------------------------
    # Pull / Import — write into the selected slot or orphan folder
    # ------------------------------------------------------------------

    def _pull_patch(self):
        client = self._get_client()
        if not client:
            return
        # Snapshot the target now so the async callback knows where to write.
        if self._is_orphan_mode():
            self._pending_pull_slot      = None
            self._pending_pull_bank_path = None
        else:
            row = self.slot_list.currentRow()
            if row < 0:
                return
            self._pending_pull_slot      = self.slot_list.item(row).data(Qt.UserRole)
            self._pending_pull_bank_path = self._current_bank_path()
        try:
            client.send_message("/tb3/request_patch_export", "")
            self.statusBar().showMessage("Requested current patch from TouchOSC…")
        except Exception as e:
            self.statusBar().showMessage(f"Send error: {e}")

    def _handle_backup_received(self, preset_name: str, syx_bytes: bytes):
        """Called when /tb3/backup arrives. Routes to the pending target."""
        slot_num  = self._pending_pull_slot
        bank_path = self._pending_pull_bank_path
        # Reset immediately so stale callbacks don't double-fire.
        self._pending_pull_slot      = None
        self._pending_pull_bank_path = None

        if slot_num is None:
            self._write_syx_to_orphan(preset_name, syx_bytes)
        else:
            self._write_syx_to_bank_slot(syx_bytes, bank_path, slot_num,
                                         default_name=preset_name)

    def _import_syx(self):
        path, _ = QFileDialog.getOpenFileName(
            self, "Import SysEx file", str(Path.home()), "SysEx (*.syx);;All (*)"
        )
        if not path:
            return
        src = Path(path)
        with open(src, "rb") as f:
            syx_bytes = f.read()

        if self._is_orphan_mode():
            self._write_syx_to_orphan(src.stem, syx_bytes)
        else:
            row = self.slot_list.currentRow()
            if row < 0:
                return
            self._write_syx_to_bank_slot(
                syx_bytes,
                self._current_bank_path(),
                self.slot_list.item(row).data(Qt.UserRole),
                default_name=src.stem,
            )

    def _write_syx_to_orphan(self, suggested_name: str, syx_bytes: bytes):
        if suggested_name:
            # Name came from TouchOSC — save without asking, only warn on collision.
            name = suggested_name
        else:
            # No name available — ask.
            ts = datetime.now().strftime("%Y%m%d_%H%M%S")
            name, ok = QInputDialog.getText(
                self, "Save Patch", "Patch name:", text=f"tb3_patch_{ts}"
            )
            if not (ok and name.strip()):
                return
            name = name.strip()
        dest = self._patches_dir() / f"{name}.syx"
        if dest.exists():
            r = QMessageBox.question(
                self, "Overwrite?",
                f"A patch named '{name}' already exists.\nOverwrite it?",
                QMessageBox.Yes | QMessageBox.No
            )
            if r != QMessageBox.Yes:
                return
        with open(dest, "wb") as f:
            f.write(syx_bytes)
        if self._is_orphan_mode():
            self._refresh_slot_list()
        self.statusBar().showMessage(f"Saved patch: {dest.name}")

    def _write_syx_to_bank_slot(self, syx_bytes: bytes, bank_path, slot_num: int,
                                 default_name: str = ""):
        if not bank_path or not bank_path.exists():
            QMessageBox.warning(self, "Error", "Bank file not found.")
            return
        try:
            with open(bank_path) as f:
                bank_data = json.load(f)
        except Exception as e:
            QMessageBox.warning(self, "Error", f"Could not read bank: {e}")
            return

        slots    = bank_data.setdefault("slots", {})
        existing = slots.get(str(slot_num))
        filled   = existing is not None and isinstance(existing, dict) and existing.get("blocks")

        if filled:
            existing_name = (existing.get("name") or "").strip() or "[unnamed]"
            r = QMessageBox.question(
                self, "Overwrite?",
                f"Slot {slot_num} already contains '{existing_name}'.\nOverwrite it?",
                QMessageBox.Yes | QMessageBox.No
            )
            if r != QMessageBox.Yes:
                return
            current_name = (existing.get("name") or "").strip()
        else:
            current_name = default_name

        name, ok = QInputDialog.getText(
            self, f"Name for Slot {slot_num}", "Preset name:", text=current_name
        )
        if not ok:
            return

        bank_data["slots"][str(slot_num)] = {
            "name":   name.strip(),
            "blocks": syx_bytes_to_block_list(syx_bytes),
        }
        bank_data["version"] = 2
        with open(bank_path, "w") as f:
            json.dump(bank_data, f, indent=2)

        self._refresh_slot_list()
        for i in range(self.slot_list.count()):
            if self.slot_list.item(i).data(Qt.UserRole) == slot_num:
                self.slot_list.setCurrentRow(i)
                break
        self.statusBar().showMessage(
            f"Saved to slot {slot_num} of '{self._bank_name_from_path(bank_path)}'."
        )

    # ------------------------------------------------------------------
    # Slot actions: restore / rename / export .syx / delete
    # ------------------------------------------------------------------

    def _restore_slot(self):
        row = self.slot_list.currentRow()
        if row < 0:
            return
        if self._is_orphan_mode():
            path = Path(self.slot_list.item(row).data(Qt.UserRole))
            if not path.exists():
                return
            with open(path, "rb") as f:
                syx_data = f.read()
            csvs = [bytes_to_csv_hex(m) for m in parse_syx(syx_data)]
        else:
            path = self._current_bank_path()
            if not path or not path.exists():
                return
            slot_num = self.slot_list.item(row).data(Qt.UserRole)
            try:
                with open(path) as f:
                    bank_data = json.load(f)
            except Exception:
                return
            slot = bank_data.get("slots", {}).get(str(slot_num))
            if not slot or not isinstance(slot, dict):
                return
            csvs = [bytes_to_csv_hex(hex_string_to_bytes(b))
                    for b in slot.get("blocks", [])]
        self._send_blocks(csvs)

    def _rename_slot(self):
        row = self.slot_list.currentRow()
        if row < 0:
            return
        if self._is_orphan_mode():
            item = self.slot_list.item(row)
            path = Path(item.data(Qt.UserRole))
            name, ok = QInputDialog.getText(
                self, "Rename Patch", "New name:", text=path.stem
            )
            if not (ok and name.strip() and name.strip() != path.stem):
                return
            path.rename(path.parent / f"{name.strip()}.syx")
            self._refresh_slot_list()
        else:
            bank_path = self._current_bank_path()
            if not bank_path or not bank_path.exists():
                return
            slot_num = self.slot_list.item(row).data(Qt.UserRole)
            try:
                with open(bank_path) as f:
                    bank_data = json.load(f)
            except Exception:
                return
            slot = bank_data.get("slots", {}).get(str(slot_num))
            if not slot or not isinstance(slot, dict):
                return
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
            self.slot_list.setCurrentRow(row)

    def _export_syx(self):
        row = self.slot_list.currentRow()
        if row < 0:
            return
        if self._is_orphan_mode():
            src = Path(self.slot_list.item(row).data(Qt.UserRole))
            dst, _ = QFileDialog.getSaveFileName(
                self, "Export SysEx", str(Path.home() / src.name), "SysEx (*.syx)"
            )
            if dst:
                shutil.copy2(src, dst)
                self.statusBar().showMessage(f"Exported to {dst}")
        else:
            bank_path = self._current_bank_path()
            if not bank_path or not bank_path.exists():
                return
            slot_num = self.slot_list.item(row).data(Qt.UserRole)
            try:
                with open(bank_path) as f:
                    bank_data = json.load(f)
            except Exception:
                return
            slot   = bank_data.get("slots", {}).get(str(slot_num))
            blocks = (slot or {}).get("blocks", []) if isinstance(slot, dict) else []
            if not blocks:
                return
            bank_name = self._bank_name_from_path(bank_path)
            slot_name = (slot.get("name") or "").strip() or f"slot{slot_num}"
            dst, _ = QFileDialog.getSaveFileName(
                self, "Export SysEx",
                str(Path.home() / f"{bank_name}_{slot_name}.syx"),
                "SysEx (*.syx)"
            )
            if not dst:
                return
            syx = b"".join(hex_string_to_bytes(b) for b in blocks)
            with open(dst, "wb") as f:
                f.write(syx)
            self.statusBar().showMessage(f"Exported slot {slot_num} to {dst}")

    def _delete_slot(self):
        row = self.slot_list.currentRow()
        if row < 0:
            return
        if self._is_orphan_mode():
            item = self.slot_list.item(row)
            path = Path(item.data(Qt.UserRole))
            r = QMessageBox.question(
                self, "Delete", f"Delete '{path.stem}'?",
                QMessageBox.Yes | QMessageBox.No
            )
            if r == QMessageBox.Yes:
                path.unlink(missing_ok=True)
                self._refresh_slot_list()
        else:
            bank_path = self._current_bank_path()
            if not bank_path or not bank_path.exists():
                return
            slot_num = self.slot_list.item(row).data(Qt.UserRole)
            r = QMessageBox.question(
                self, "Delete Slot", f"Clear slot {slot_num}?",
                QMessageBox.Yes | QMessageBox.No
            )
            if r != QMessageBox.Yes:
                return
            try:
                with open(bank_path) as f:
                    bank_data = json.load(f)
                bank_data["slots"][str(slot_num)] = None
                with open(bank_path, "w") as f:
                    json.dump(bank_data, f, indent=2)
            except Exception:
                return
            self._refresh_slot_list()
            self.slot_list.setCurrentRow(row)

    def _send_blocks(self, csv_list: list):
        client = self._get_client()
        if not client:
            return
        for i, csv in enumerate(csv_list):
            try:
                client.send_message("/tb3/restore", csv)
                self.statusBar().showMessage(f"Restoring block {i + 1}/{len(csv_list)}…")
                QApplication.processEvents()
                time.sleep(0.015)
            except Exception as e:
                self.statusBar().showMessage(f"Send error: {e}")
                return
        self.statusBar().showMessage(f"Restored {len(csv_list)} blocks to TouchOSC.")

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
        self._refresh_bank_list()
        self.statusBar().showMessage("Settings saved. Listener restarted.")

    # ------------------------------------------------------------------
    # OSC
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
        self._listener.listening.connect(self._on_listener_state)
        self._listener.start()

    def _on_listener_state(self, ok, info):
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
