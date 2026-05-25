from __future__ import annotations

import json
import os
import re
import socket
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from functools import partial
from pathlib import Path

SETTINGS_FILE = "settings.json"
DUMPS_DIR = Path(__file__).resolve().parent / "dumps"
BACKUP_OSC_PATH = "/sp404/backup"
BACKUP_FORMAT_VERSION = 1
DEFAULT_SETTINGS = {
    "listener_ip": "127.0.0.1",
    "listener_port": "5005",
    "sender_ip": "127.0.0.1",
    "sender_port": "5006",
    "lastConfigName": "untitled",
    "nextConfigVersionByKey": {},
    "settingsConfigured": False,
}


def sanitize_config_key(name: str) -> str:
    name = (name or "").strip() or "untitled"
    name = re.sub(r"[^\w\-]+", "_", name)
    return name[:64] or "untitled"


@dataclass
class DumpEntry:
    path: Path
    name: str
    config_version: int
    created_at: str

    @property
    def config_key(self) -> str:
        return sanitize_config_key(self.name)


def _configure_qt_platform_plugins():
    """macOS: Qt aborts if plugin path is wrong or Qt frameworks are not on the loader path."""
    try:
        import PyQt5
        from PyQt5.QtCore import QCoreApplication
    except ImportError:
        return

    qt5_root = os.path.join(os.path.dirname(PyQt5.__file__), "Qt5")
    plugins_root = os.path.join(qt5_root, "plugins")
    platforms = os.path.join(plugins_root, "platforms")
    cocoa = os.path.join(platforms, "libqcocoa.dylib")
    if not os.path.isfile(cocoa):
        return

    os.environ["QT_QPA_PLATFORM_PLUGIN_PATH"] = platforms
    os.environ["QT_PLUGIN_PATH"] = plugins_root

    if sys.platform == "darwin":
        qt_lib = os.path.join(qt5_root, "lib")
        if os.path.isdir(qt_lib):
            existing = os.environ.get("DYLD_FRAMEWORK_PATH", "")
            if qt_lib not in existing.split(":"):
                os.environ["DYLD_FRAMEWORK_PATH"] = (
                    qt_lib + (":" + existing if existing else "")
                )

    QCoreApplication.addLibraryPath(plugins_root)
    if sys.platform == "darwin":
        qt_lib = os.path.join(qt5_root, "lib")
        if os.path.isdir(qt_lib):
            QCoreApplication.addLibraryPath(qt_lib)


_configure_qt_platform_plugins()

import psutil
from PyQt5.QtCore import QByteArray, Qt, QThread, QTimer, pyqtSignal
from PyQt5.QtGui import QIntValidator
from PyQt5.QtWidgets import (
    QApplication,
    QDialog,
    QHBoxLayout,
    QInputDialog,
    QLabel,
    QLineEdit,
    QListWidget,
    QListWidgetItem,
    QMainWindow,
    QMenu,
    QPushButton,
    QTabWidget,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)
from pythonosc.dispatcher import Dispatcher
from pythonosc.osc_message_builder import OscMessageBuilder
from pythonosc.osc_server import BlockingOSCUDPServer
from pythonosc.udp_client import SimpleUDPClient


def _suppress_mac_focus_ring(widget: QWidget) -> None:
    if sys.platform == "darwin":
        widget.setAttribute(Qt.WA_MacShowFocusRect, False)


class DeleteConfirmDialog(QDialog):
    """Qt-drawn confirm sheet — avoids macOS native QMessageBox Yes/No mapping."""

    def __init__(self, parent: QWidget | None, title: str, message: str):
        super().__init__(parent)
        self.setWindowTitle(title)
        self.setModal(True)
        self.setMinimumWidth(360)

        layout = QVBoxLayout(self)
        label = QLabel(message)
        label.setWordWrap(True)
        layout.addWidget(label)

        row = QHBoxLayout()
        row.addStretch()
        cancel_btn = QPushButton("Cancel")
        delete_btn = QPushButton("Delete")
        _suppress_mac_focus_ring(cancel_btn)
        _suppress_mac_focus_ring(delete_btn)
        cancel_btn.setDefault(True)
        cancel_btn.setAutoDefault(True)
        delete_btn.setDefault(False)
        cancel_btn.clicked.connect(self.reject)
        delete_btn.clicked.connect(self.accept)
        row.addWidget(cancel_btn)
        row.addWidget(delete_btn)
        layout.addLayout(row)
        cancel_btn.setFocus()


class BackupListenerThread(QThread):
    backup_received = pyqtSignal(dict)

    def __init__(self, ip: str, port: int):
        super().__init__()
        self.ip = ip
        self.port = port
        self.server = None
        self.running = True

    def handle_backup(self, address, *args):
        if not args:
            return
        raw = args[0]
        if isinstance(raw, bytes):
            raw = raw.decode("utf-8", errors="replace")
        try:
            data = json.loads(raw)
        except (TypeError, json.JSONDecodeError):
            return
        self.backup_received.emit(data)

    def run(self):
        dispatcher = Dispatcher()
        dispatcher.map(BACKUP_OSC_PATH, self.handle_backup)

        try:
            self.server = BlockingOSCUDPServer((self.ip, self.port), dispatcher)
            self.server.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            while self.running:
                self.server.handle_request()
        except OSError as e:
            self.backup_received.emit({"_error": str(e)})

    def stop(self):
        self.running = False
        if self.server:
            self.server.server_close()


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("SP-404 Backup Utility")
        self.settings = self.load_settings()
        if not self._restore_window_geometry():
            self.resize(560, 420)
        self.listener_thread = None
        self.dump_entries: list[DumpEntry] = []
        self._settings_save_timer = QTimer(self)
        self._settings_save_timer.setSingleShot(True)
        self._settings_save_timer.setInterval(500)
        self._settings_save_timer.timeout.connect(self._persist_settings)

        self.tabs = QTabWidget()
        self.backup_tab = QWidget()
        self.settings_tab = QWidget()
        self.tabs.addTab(self.backup_tab, "Backup")
        self.tabs.addTab(self.settings_tab, "Settings")
        self.setCentralWidget(self.tabs)

        self._build_backup_tab()
        self._build_settings_tab()

        self.tabs.currentChanged.connect(self._on_tab_changed)
        if not self.settings.get("settingsConfigured"):
            self.tabs.setCurrentWidget(self.settings_tab)
        else:
            self.tabs.setCurrentWidget(self.backup_tab)

        self.refresh_library()
        self._start_listener()

    def _build_backup_tab(self):
        layout = QVBoxLayout()

        browser = QHBoxLayout()
        configs_col = QVBoxLayout()
        configs_col.addWidget(QLabel("Configs"))
        self.config_list = QListWidget()
        self.config_list.setContextMenuPolicy(Qt.CustomContextMenu)
        self.config_list.customContextMenuRequested.connect(self._show_config_context_menu)
        self.config_list.currentItemChanged.connect(self._on_config_selected)
        configs_col.addWidget(self.config_list)
        browser.addLayout(configs_col)

        versions_col = QVBoxLayout()
        versions_col.addWidget(QLabel("Versions — double-click replay, right-click delete"))
        self.version_list = QListWidget()
        self.version_list.setContextMenuPolicy(Qt.CustomContextMenu)
        self.version_list.customContextMenuRequested.connect(self._show_version_context_menu)
        self.version_list.itemDoubleClicked.connect(self._on_version_double_clicked)
        versions_col.addWidget(self.version_list)
        browser.addLayout(versions_col, stretch=2)

        layout.addLayout(browser)

        self.log_toggle = QPushButton("Show log")
        self.log_toggle.setCheckable(True)
        self.log_toggle.toggled.connect(self._toggle_log)
        layout.addWidget(self.log_toggle)

        self.log = QTextEdit()
        self.log.setReadOnly(True)
        self.log.setMaximumHeight(120)
        self.log.setVisible(False)
        layout.addWidget(self.log)

        self.backup_tab.setLayout(layout)

    def _build_settings_tab(self):
        layout = QVBoxLayout()

        layout.addWidget(QLabel("Match TouchOSC OSC receive (capture) and send (replay) ports."))

        conn = QHBoxLayout()
        conn.addWidget(QLabel("Listen (capture):"))
        self.listener_ip = QLineEdit(self.settings.get("listener_ip", DEFAULT_SETTINGS["listener_ip"]))
        self.listener_port = QLineEdit(self.settings.get("listener_port", DEFAULT_SETTINGS["listener_port"]))
        self.listener_port.setValidator(QIntValidator(1, 65535))
        conn.addWidget(self.listener_ip)
        conn.addWidget(self.listener_port)
        layout.addLayout(conn)

        conn2 = QHBoxLayout()
        conn2.addWidget(QLabel("Send (replay):"))
        self.sender_ip = QLineEdit(self.settings.get("sender_ip", DEFAULT_SETTINGS["sender_ip"]))
        self.sender_port = QLineEdit(self.settings.get("sender_port", DEFAULT_SETTINGS["sender_port"]))
        self.sender_port.setValidator(QIntValidator(1, 65535))
        conn2.addWidget(self.sender_ip)
        conn2.addWidget(self.sender_port)
        layout.addLayout(conn2)

        layout.addWidget(QLabel("Your IP addresses (click to set Listen IP):"))
        for ip in self.get_current_ips():
            ip_address = ip.split(": ")[-1]
            link = QLabel(f"<a href='#'>{ip}</a>")
            link.linkActivated.connect(partial(self.listener_ip.setText, ip_address))
            layout.addWidget(link)

        self.settings_done_btn = QPushButton("Continue to Backup")
        self.settings_done_btn.clicked.connect(self._finish_settings_setup)
        layout.addWidget(self.settings_done_btn)

        layout.addStretch()
        self.settings_tab.setLayout(layout)

        for widget in (self.listener_ip, self.listener_port, self.sender_ip, self.sender_port):
            widget.textChanged.connect(self._schedule_settings_save)

    def _on_tab_changed(self, index: int):
        if self.tabs.widget(index) is self.settings_tab:
            self._schedule_settings_save()
        elif self.tabs.widget(index) is self.backup_tab:
            self.refresh_library()

    def _sync_settings_from_ui(self):
        self.settings["listener_ip"] = self.listener_ip.text()
        self.settings["listener_port"] = self.listener_port.text()
        self.settings["sender_ip"] = self.sender_ip.text()
        self.settings["sender_port"] = self.sender_port.text()

    def _write_settings_file(self):
        with open(SETTINGS_FILE, "w", encoding="utf-8") as f:
            json.dump(self.settings, f, indent=2)

    def _restore_window_geometry(self) -> bool:
        encoded = self.settings.get("windowGeometry")
        if not isinstance(encoded, str) or not encoded:
            return False
        return self.restoreGeometry(QByteArray.fromBase64(encoded.encode("ascii")))

    def _save_window_geometry(self):
        self.settings["windowGeometry"] = bytes(self.saveGeometry().toBase64()).decode("ascii")

    def _finish_settings_setup(self):
        self.settings_done_btn.setEnabled(False)
        self._sync_settings_from_ui()
        self.settings["settingsConfigured"] = True
        self._write_settings_file()
        self.tabs.setCurrentWidget(self.backup_tab)
        self.log_message("Settings saved.")
        self.log_message("Starting capture listener…")
        QTimer.singleShot(0, self._restart_listener)

    def _schedule_settings_save(self):
        self._settings_save_timer.start()

    def _persist_settings(self):
        old_listen = (
            self.settings.get("listener_ip"),
            self.settings.get("listener_port"),
        )
        self._sync_settings_from_ui()
        self._write_settings_file()
        new_listen = (self.settings["listener_ip"], self.settings["listener_port"])
        if new_listen != old_listen:
            QTimer.singleShot(0, self._restart_listener)

    def _restart_listener(self):
        self._start_listener()
        if hasattr(self, "settings_done_btn"):
            self.settings_done_btn.setEnabled(True)

    def _toggle_log(self, visible: bool):
        self.log.setVisible(visible)
        self.log_toggle.setText("Hide log" if visible else "Show log")

    def _version_counters(self) -> dict:
        counters = self.settings.get("nextConfigVersionByKey")
        if not isinstance(counters, dict):
            counters = {}
            self.settings["nextConfigVersionByKey"] = counters
        return counters

    def _allocate_config_version(self, config_key: str) -> int:
        counters = self._version_counters()
        version_num = int(counters.get(config_key, 1))
        counters[config_key] = version_num + 1
        return version_num

    @staticmethod
    def _parse_created_at(created_at: str) -> datetime:
        try:
            normalized = created_at.replace("Z", "+00:00")
            dt = datetime.fromisoformat(normalized)
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            return dt
        except (TypeError, ValueError, AttributeError):
            return datetime.min.replace(tzinfo=timezone.utc)

    @staticmethod
    def _format_created_at(created_at: str) -> str:
        if not created_at:
            return "unknown time"
        dt = MainWindow._parse_created_at(created_at)
        if dt == datetime.min.replace(tzinfo=timezone.utc):
            return created_at
        return dt.astimezone().strftime("%Y-%m-%d %H:%M")

    @staticmethod
    def _parse_dump_metadata(path: Path, data: dict) -> DumpEntry | None:
        if not isinstance(data, dict):
            return None
        if data.get("version") != BACKUP_FORMAT_VERSION:
            return None
        if not isinstance(data.get("presets"), dict):
            return None

        name = (data.get("name") or "").strip()
        if not name:
            return None

        try:
            config_version = int(data["configVersion"])
        except (KeyError, TypeError, ValueError):
            return None

        created_at = data.get("createdAt")
        if not isinstance(created_at, str) or not created_at.strip():
            return None

        return DumpEntry(
            path=path,
            name=name,
            config_version=config_version,
            created_at=created_at.strip(),
        )

    def _load_dump_entries(self) -> list[DumpEntry]:
        DUMPS_DIR.mkdir(parents=True, exist_ok=True)
        entries: list[DumpEntry] = []
        for path in DUMPS_DIR.glob("*.json"):
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                continue
            entry = self._parse_dump_metadata(path, data)
            if entry:
                entries.append(entry)
        return entries

    def _rebuild_version_counters_from_dumps(self) -> dict:
        counters: dict[str, int] = {}
        for entry in self._load_dump_entries():
            next_id = max(counters.get(entry.config_key, 1), entry.config_version + 1)
            counters[entry.config_key] = next_id
        return counters

    def _config_names_newest_first(self) -> list[str]:
        latest: dict[str, datetime] = {}
        for entry in self.dump_entries:
            dt = self._parse_created_at(entry.created_at)
            if entry.name not in latest or dt > latest[entry.name]:
                latest[entry.name] = dt
        return sorted(latest.keys(), key=lambda n: latest[n], reverse=True)

    def refresh_library(self):
        previous_config = None
        if self.config_list.currentItem():
            previous_config = self.config_list.currentItem().text()

        self.dump_entries = self._load_dump_entries()
        config_names = self._config_names_newest_first()

        self.config_list.blockSignals(True)
        self.config_list.clear()
        for name in config_names:
            self.config_list.addItem(name)

        if previous_config and previous_config in config_names:
            row = config_names.index(previous_config)
            self.config_list.setCurrentRow(row)
        elif config_names:
            self.config_list.setCurrentRow(0)
        else:
            self.version_list.clear()

        self.config_list.blockSignals(False)
        if self.config_list.currentItem():
            self._populate_versions_for_config(self.config_list.currentItem().text())
        else:
            self.version_list.clear()

    def _entries_for_config(self, config_name: str) -> list[DumpEntry]:
        return [e for e in self.dump_entries if e.name == config_name]

    def _populate_versions_for_config(self, config_name: str):
        self.version_list.clear()
        entries = sorted(
            self._entries_for_config(config_name),
            key=lambda e: (self._parse_created_at(e.created_at), e.config_version),
            reverse=True,
        )
        for entry in entries:
            label = f"#{entry.config_version} ({self._format_created_at(entry.created_at)})"
            item = QListWidgetItem(label)
            item.setData(Qt.UserRole, str(entry.path))
            self.version_list.addItem(item)

    def _on_config_selected(self, current, _previous):
        if not current:
            self.version_list.clear()
            return
        self._populate_versions_for_config(current.text())

    def _sync_version_counters_from_library(self):
        self.settings["nextConfigVersionByKey"] = self._rebuild_version_counters_from_dumps()
        self._write_settings_file()

    def _delete_dump_files(self, paths: list[Path]) -> int:
        deleted = 0
        for path in paths:
            try:
                path.unlink()
                deleted += 1
            except OSError as e:
                self.log_message(f"Could not delete {path.name}: {e}")
        if deleted:
            self.refresh_library()
            self._sync_version_counters_from_library()
        return deleted

    def _entry_for_path(self, path: Path) -> DumpEntry | None:
        path_str = str(path.resolve())
        for entry in self.dump_entries:
            if str(entry.path.resolve()) == path_str:
                return entry
        return None

    def _prompt_config_name(self, title: str, label: str, current: str) -> str | None:
        new_name, ok = QInputDialog.getText(self, title, label, text=current)
        if not ok:
            return None
        new_name = new_name.strip()
        if not new_name:
            return None
        return new_name

    def _write_dump_name(self, path: Path, new_name: str) -> bool:
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as e:
            self.log_message(f"Could not read {path.name}: {e}")
            return False
        data["name"] = new_name
        try:
            path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        except OSError as e:
            self.log_message(f"Could not update {path.name}: {e}")
            return False
        return True

    def _rename_config_group(self, old_name: str, new_name: str) -> int:
        if new_name == old_name:
            return 0
        updated = 0
        for entry in self._entries_for_config(old_name):
            if self._write_dump_name(entry.path, new_name):
                updated += 1

        if not updated:
            return 0

        old_key = sanitize_config_key(old_name)
        new_key = sanitize_config_key(new_name)
        counters = self._version_counters()
        old_next = int(counters.pop(old_key, 1))
        counters[new_key] = max(int(counters.get(new_key, 1)), old_next)

        if self.settings.get("lastConfigName") == old_name:
            self.settings["lastConfigName"] = new_name
        self._write_settings_file()
        self.refresh_library()
        for row in range(self.config_list.count()):
            if self.config_list.item(row).text() == new_name:
                self.config_list.setCurrentRow(row)
                break
        return updated

    def _rename_version(self, path: Path):
        entry = self._entry_for_path(path)
        current = entry.name if entry else ""
        new_name = self._prompt_config_name(
            "Rename backup",
            "Config name for this version:",
            current,
        )
        if not new_name or new_name == current:
            return
        if not self._write_dump_name(path, new_name):
            return
        self.refresh_library()
        self._sync_version_counters_from_library()
        for row in range(self.config_list.count()):
            if self.config_list.item(row).text() == new_name:
                self.config_list.setCurrentRow(row)
                break
        if entry:
            self.log_message(
                f'Renamed v{entry.config_version} from "{current}" to "{new_name}"'
            )
        else:
            self.log_message(f'Renamed backup to "{new_name}"')

    def _rename_config(self, config_name: str):
        new_name = self._prompt_config_name(
            "Rename config",
            "Config name:",
            config_name,
        )
        if not new_name:
            return
        count = self._rename_config_group(config_name, new_name)
        if count:
            self.log_message(f'Renamed config "{config_name}" → "{new_name}" ({count} file(s))')

    def _show_version_context_menu(self, pos):
        item = self.version_list.itemAt(pos)
        if not item:
            return
        path_str = item.data(Qt.UserRole)
        if not path_str:
            return

        menu = QMenu(self)
        rename_action = menu.addAction("Rename…")
        delete_action = menu.addAction("Delete version…")
        chosen = menu.exec_(self.version_list.mapToGlobal(pos))
        path = Path(path_str)
        if chosen == rename_action:
            self._rename_version(path)
        elif chosen == delete_action:
            self._delete_version(path, item.text())

    def _show_config_context_menu(self, pos):
        item = self.config_list.itemAt(pos)
        if not item:
            return
        config_name = item.text()
        count = len(self._entries_for_config(config_name))
        if count == 0:
            return

        menu = QMenu(self)
        rename_action = menu.addAction("Rename config…")
        delete_action = menu.addAction(f"Delete all versions ({count})…")
        chosen = menu.exec_(self.config_list.mapToGlobal(pos))
        if chosen == rename_action:
            self._rename_config(config_name)
        elif chosen == delete_action:
            self._delete_config_all(config_name, count)

    def _confirm_delete(self, title: str, message: str) -> bool:
        return DeleteConfirmDialog(self, title, message).exec_() == QDialog.Accepted

    def _delete_version(self, path: Path, label: str):
        entry = self._entry_for_path(path)
        if entry:
            detail = (
                f'Delete "{entry.name}" v{entry.config_version} '
                f"({self._format_created_at(entry.created_at)})?\n"
                "This cannot be undone."
            )
        else:
            detail = f"Delete {label}?\nThis cannot be undone."

        if not self._confirm_delete("Delete version", detail):
            return

        if self._delete_dump_files([path]):
            self.log_message(f"Deleted {path.name}")

    def _delete_config_all(self, config_name: str, count: int):
        if not self._confirm_delete(
            "Delete config",
            f'Delete all {count} version(s) of "{config_name}"?\nThis cannot be undone.',
        ):
            return

        paths = [entry.path for entry in self._entries_for_config(config_name)]
        deleted = self._delete_dump_files(paths)
        if deleted:
            self.log_message(f'Deleted config "{config_name}" ({deleted} file(s))')

    def log_message(self, text: str):
        self.log.append(text)

    def get_current_ips(self):
        ip_list = []
        for interface, addrs in psutil.net_if_addrs().items():
            for addr in addrs:
                if addr.family == socket.AF_INET:
                    kind = "Wireless" if ("wlan" in interface or "wifi" in interface) else "Wired"
                    ip_list.append(f"{interface} ({kind}): {addr.address}")
        return ip_list

    @staticmethod
    def validate_backup(data):
        if not isinstance(data, dict):
            return "Payload is not a JSON object"
        if data.get("version") != BACKUP_FORMAT_VERSION:
            return f"Unsupported backup format (expected {BACKUP_FORMAT_VERSION})"
        for key in ("presets", "scenes", "defaults", "recent", "buses"):
            if key in data and not isinstance(data[key], dict):
                return f"Section '{key}' must be an object"
        if "presets" not in data:
            return "Missing presets section"
        return None

    def _stop_listener(self, timeout_ms: int = 400):
        if self.listener_thread and self.listener_thread.isRunning():
            self.listener_thread.stop()
            self.listener_thread.wait(timeout_ms)

    def _start_listener(self):
        self._stop_listener()
        ip = self.listener_ip.text()
        port = int(self.listener_port.text())
        self.listener_thread = BackupListenerThread(ip, port)
        self.listener_thread.backup_received.connect(self.on_backup_received)
        self.listener_thread.start()
        self.log_message(f"Listening on {ip}:{port} for {BACKUP_OSC_PATH}")

    def on_backup_received(self, data: dict):
        if "_error" in data:
            self.log_message(f"Listener error: {data['_error']}")
            return

        err = self.validate_backup(data)
        if err:
            self.log_message(f"Rejected backup: {err}")
            return

        prefill = (
            self.settings.get("lastConfigName")
            or data.get("name")
            or DEFAULT_SETTINGS["lastConfigName"]
        )
        if not isinstance(prefill, str) or not prefill.strip():
            prefill = "untitled"

        config_name, ok = QInputDialog.getText(
            self,
            "Save backup",
            "Config name for this capture:",
            text=str(prefill).strip(),
        )
        if not ok:
            self.log_message("Capture discarded.")
            return

        config_name = config_name.strip() or "untitled"
        config_key = sanitize_config_key(config_name)
        self.settings["lastConfigName"] = config_name
        config_version = self._allocate_config_version(config_key)
        created_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        self._sync_settings_from_ui()
        self._write_settings_file()

        dump = dict(data)
        dump["name"] = config_name
        dump["configVersion"] = config_version
        dump["version"] = BACKUP_FORMAT_VERSION
        dump["createdAt"] = created_at

        DUMPS_DIR.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"{config_key}_{config_version:04d}_{stamp}.json"
        path = DUMPS_DIR / filename
        path.write_text(json.dumps(dump, indent=2), encoding="utf-8")

        self.refresh_library()
        for row in range(self.config_list.count()):
            if self.config_list.item(row).text() == config_name:
                self.config_list.setCurrentRow(row)
                break
        self.log_message(
            f'Saved "{config_name}" v{config_version} ({self._format_created_at(created_at)})'
        )

    def _on_version_double_clicked(self, item):
        path_str = item.data(Qt.UserRole)
        if path_str:
            self.replay_file(Path(path_str))

    def replay_file(self, path: Path):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as e:
            self.log_message(f"Could not read backup: {e}")
            return

        err = self.validate_backup(data)
        if err:
            self.log_message(f"Invalid backup: {err}")
            return

        entry = self._parse_dump_metadata(path, data)
        client = SimpleUDPClient(self.sender_ip.text(), int(self.sender_port.text()))
        payload = json.dumps(data, separators=(",", ":"))
        builder = OscMessageBuilder(address=BACKUP_OSC_PATH)
        builder.add_arg(payload)
        client.send(builder.build())
        if entry:
            self.log_message(
                f'Replayed "{entry.name}" v{entry.config_version} '
                f"({self._format_created_at(entry.created_at)})"
            )
        else:
            self.log_message("Replayed backup.")

    def load_settings(self):
        settings = dict(DEFAULT_SETTINGS)
        if os.path.exists(SETTINGS_FILE):
            with open(SETTINGS_FILE, encoding="utf-8") as f:
                settings.update(json.load(f))
        file_counters = self._rebuild_version_counters_from_dumps()
        counters = settings.get("nextConfigVersionByKey")
        if not isinstance(counters, dict):
            counters = {}
        for name, next_id in file_counters.items():
            counters[name] = max(int(counters.get(name, 1)), int(next_id))
        settings["nextConfigVersionByKey"] = counters
        return settings

    def closeEvent(self, event):
        self._stop_listener(timeout_ms=800)
        self._sync_settings_from_ui()
        self._save_window_geometry()
        self._write_settings_file()
        super().closeEvent(event)


if __name__ == "__main__":
    app = QApplication(sys.argv)
    if sys.platform == "darwin":
        app.setAttribute(Qt.AA_DontUseNativeDialogs, True)
    window = MainWindow()
    window.show()
    sys.exit(app.exec_())
