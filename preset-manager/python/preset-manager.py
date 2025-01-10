import sys
import socket
import json
import os
from PyQt5.QtWidgets import (
    QApplication, QMainWindow, QVBoxLayout, QWidget, QLabel, QPushButton, QLineEdit, QTextEdit, QFileDialog
)
from PyQt5.QtCore import QThread, pyqtSignal
from pythonosc.dispatcher import Dispatcher
from pythonosc.osc_server import BlockingOSCUDPServer
from pythonosc.udp_client import SimpleUDPClient


SETTINGS_FILE = "settings.json"


class OSCListenerThread(QThread):
    message_received = pyqtSignal(str)

    def __init__(self, port, message_type, save_file):
        super().__init__()
        self.ip = "127.0.0.1"  # Always listen on localhost
        self.port = port
        self.message_type = message_type
        self.save_file = save_file
        self.server = None
        self.running = True

    def save_message(self, address, *args):
        message = {"address": address, "args": args}
        self.message_received.emit(str(message))
        with open(self.save_file, "a") as f:
            json.dump(message, f)
            f.write("\n")

    def run(self):
        dispatcher = Dispatcher()
        dispatcher.map(self.message_type, self.save_message)

        self.server = BlockingOSCUDPServer((self.ip, self.port), dispatcher)
        while self.running:
            self.server.handle_request()

    def stop(self):
        self.running = False
        if self.server:
            self.server.server_close()


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("OSC Listener and Sender")
        self.resize(600, 500)

        # Load settings
        self.settings = self.load_settings()

        # Layout
        layout = QVBoxLayout()

        # Display current IP address
        current_ip = self.get_current_ip()
        layout.addWidget(QLabel(f"Your Current IP Address: {current_ip}"))

        # Listener Inputs
        layout.addWidget(QLabel("Listener Configuration"))

        layout.addWidget(QLabel("Listener Port:"))
        self.listener_port_input = QLineEdit(self.settings.get("listener_port", "5005"))
        layout.addWidget(self.listener_port_input)

        layout.addWidget(QLabel("OSC Message Type (e.g., /example):"))
        self.listener_message_type_input = QLineEdit(self.settings.get("listener_message_type", "/example"))
        layout.addWidget(self.listener_message_type_input)

        layout.addWidget(QLabel("Save File for Messages:"))
        self.listener_save_file_input = QLineEdit(self.settings.get("listener_save_file", "messages.json"))
        layout.addWidget(self.listener_save_file_input)

        self.listener_browse_button = QPushButton("Browse Save File")
        self.listener_browse_button.clicked.connect(self.browse_save_file)
        layout.addWidget(self.listener_browse_button)

        self.listener_output = QTextEdit()
        self.listener_output.setReadOnly(True)
        layout.addWidget(self.listener_output)

        self.listener_start_button = QPushButton("Start Listener")
        self.listener_start_button.clicked.connect(self.start_listener)
        layout.addWidget(self.listener_start_button)

        # Sender Inputs
        layout.addWidget(QLabel("Sender Configuration"))

        layout.addWidget(QLabel("Target IP Address:"))
        self.sender_ip_input = QLineEdit(self.settings.get("sender_ip", current_ip))
        layout.addWidget(self.sender_ip_input)

        layout.addWidget(QLabel("Target Port:"))
        self.sender_port_input = QLineEdit(self.settings.get("sender_port", "5005"))
        layout.addWidget(self.sender_port_input)

        layout.addWidget(QLabel("Load File with Messages:"))
        self.sender_load_file_input = QLineEdit(self.settings.get("sender_load_file", "messages.json"))
        layout.addWidget(self.sender_load_file_input)

        self.sender_browse_button = QPushButton("Browse Load File")
        self.sender_browse_button.clicked.connect(self.browse_load_file)
        layout.addWidget(self.sender_browse_button)

        self.sender_start_button = QPushButton("Send Messages")
        self.sender_start_button.clicked.connect(self.send_messages)
        layout.addWidget(self.sender_start_button)

        self.save_settings_button = QPushButton("Save Settings")
        self.save_settings_button.clicked.connect(self.save_settings)
        layout.addWidget(self.save_settings_button)

        # Set main widget
        container = QWidget()
        container.setLayout(layout)
        self.setCentralWidget(container)

        # OSC Listener Thread
        self.listener_thread = None

    def get_current_ip(self):
        try:
            return socket.gethostbyname(socket.gethostname())
        except socket.error:
            return "127.0.0.1"  # Fallback to localhost if unable to fetch

    def browse_save_file(self):
        file_name, _ = QFileDialog.getSaveFileName(self, "Select Save File", "", "JSON Files (*.json);;All Files (*)")
        if file_name:
            self.listener_save_file_input.setText(file_name)

    def browse_load_file(self):
        file_name, _ = QFileDialog.getOpenFileName(self, "Select Load File", "", "JSON Files (*.json);;All Files (*)")
        if file_name:
            self.sender_load_file_input.setText(file_name)

    def start_listener(self):
        if self.listener_thread and self.listener_thread.isRunning():
            self.listener_thread.stop()
            self.listener_thread = None
            self.listener_start_button.setText("Start Listener")
            return

        port = int(self.listener_port_input.text())
        message_type = self.listener_message_type_input.text()
        save_file = self.listener_save_file_input.text()

        self.listener_thread = OSCListenerThread(port, message_type, save_file)
        self.listener_thread.message_received.connect(self.display_message)
        self.listener_thread.start()
        self.listener_start_button.setText("Stop Listener")

    def display_message(self, message):
        self.listener_output.append(message)

    def send_messages(self):
        ip = self.sender_ip_input.text()
        port = int(self.sender_port_input.text())
        load_file = self.sender_load_file_input.text()

        client = SimpleUDPClient(ip, port)
        try:
            with open(load_file, "r") as f:
                for line in f:
                    message = json.loads(line.strip())
                    address = message["address"]
                    args = message["args"]
                    client.send_message(address, args)
                    self.listener_output.append(f"Sent: {message}")
        except FileNotFoundError:
            self.listener_output.append(f"File not found: {load_file}")

    def save_settings(self):
        settings = {
            "listener_port": self.listener_port_input.text(),
            "listener_message_type": self.listener_message_type_input.text(),
            "listener_save_file": self.listener_save_file_input.text(),
            "sender_ip": self.sender_ip_input.text(),
            "sender_port": self.sender_port_input.text(),
            "sender_load_file": self.sender_load_file_input.text(),
        }
        with open(SETTINGS_FILE, "w") as f:
            json.dump(settings, f)
        self.listener_output.append("Settings saved.")

    def load_settings(self):
        if os.path.exists(SETTINGS_FILE):
            with open(SETTINGS_FILE, "r") as f:
                return json.load(f)
        return {}


if __name__ == "__main__":
    app = QApplication(sys.argv)
    window = MainWindow()
    window.show()
    sys.exit(app.exec_())
