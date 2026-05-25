#!/bin/bash
# Launch SP-404 backup utility.
# Uses system python3 when it has a working PyQt5 (common on macOS).
# The project .venv is optional (set SP404_BACKUP_USE_VENV=1 to force it).
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(pwd)"
SCRIPT="${ROOT}/preset-manager.py"

_pick_python() {
  if [[ "${SP404_BACKUP_USE_VENV:-}" == "1" && -x "${ROOT}/.venv/bin/python" ]]; then
    echo "${ROOT}/.venv/bin/python"
    return
  fi
  if command -v python3 >/dev/null 2>&1 && python3 -c "import PyQt5" >/dev/null 2>&1; then
    echo "python3"
    return
  fi
  if [[ -x "${ROOT}/.venv/bin/python" ]]; then
    echo "${ROOT}/.venv/bin/python"
    return
  fi
  echo "No Python with PyQt5 found. Run: python3 -m pip install --user -r requirements.txt" >&2
  exit 1
}

PY="$(_pick_python)"

# Only set Qt loader hints for the project venv (system installs usually need none).
if [[ "$PY" == *"/.venv/"* ]]; then
  read -r QT5_ROOT PLATFORMS QT_LIB <<EOF
$("$PY" -c "
import os, PyQt5, sys
qt5 = os.path.join(os.path.dirname(PyQt5.__file__), 'Qt5')
print(qt5)
print(os.path.join(qt5, 'plugins', 'platforms'))
print(os.path.join(qt5, 'lib') if sys.platform == 'darwin' else '')
")
EOF
  export QT_PLUGIN_PATH="${QT5_ROOT}/plugins"
  export QT_QPA_PLATFORM_PLUGIN_PATH="$PLATFORMS"
  if [[ -n "$QT_LIB" && -d "$QT_LIB" ]]; then
    export DYLD_FRAMEWORK_PATH="${QT_LIB}${DYLD_FRAMEWORK_PATH:+:$DYLD_FRAMEWORK_PATH}"
  fi
fi

exec "$PY" "$SCRIPT"
