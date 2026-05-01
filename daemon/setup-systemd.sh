#!/usr/bin/env bash
set -euo pipefail

# Setup systemd user service for claude-watchdog
# Usage: ./setup-systemd.sh /path/to/project

PROJECT_DIR="${1:-}"

if [[ -z "$PROJECT_DIR" ]]; then
    echo "Usage: $0 /path/to/project"
    echo ""
    echo "Sets up a systemd user service to run the Claude watchdog"
    echo "daemon for the specified project directory."
    exit 1
fi

PROJECT_DIR="$(realpath "$PROJECT_DIR")"

if [[ ! -d "$PROJECT_DIR" ]]; then
    echo "Error: directory does not exist: $PROJECT_DIR" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_SRC="$SCRIPT_DIR/claude-watchdog.service"
SYSTEMD_DIR="$HOME/.config/systemd/user"

if [[ ! -f "$SERVICE_SRC" ]]; then
    echo "Error: service file not found: $SERVICE_SRC" >&2
    exit 1
fi

# Create systemd user directory
mkdir -p "$SYSTEMD_DIR"

# Escape the project path for systemd instance naming
instance_name="$(systemd-escape "$PROJECT_DIR")"

# Install the template service
cp "$SERVICE_SRC" "$SYSTEMD_DIR/claude-watchdog@.service"

# Reload systemd
systemctl --user daemon-reload

# Enable and start the service for this project
systemctl --user enable "claude-watchdog@${instance_name}.service"
systemctl --user start "claude-watchdog@${instance_name}.service"

echo "Watchdog service installed and started."
echo ""
echo "  Project:  $PROJECT_DIR"
echo "  Service:  claude-watchdog@${instance_name}.service"
echo ""
echo "Commands:"
echo "  Status:   systemctl --user status claude-watchdog@${instance_name}.service"
echo "  Logs:     journalctl --user -u claude-watchdog@${instance_name}.service"
echo "  Stop:     systemctl --user stop claude-watchdog@${instance_name}.service"
echo "  Disable:  systemctl --user disable claude-watchdog@${instance_name}.service"
