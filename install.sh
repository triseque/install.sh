#!/usr/bin/env bash
# ProofPulse agent install script for Ubuntu.
# Usage: Get install token from pairing page and run the one-line command shown there.
# With GitHub: PROOFPULSE_INSTALL_TOKEN=xxx PROOFPULSE_GITHUB_REPO=user/repo curl -sSL https://raw.githubusercontent.com/user/repo/main/install.sh | sudo bash

set -e
INSTALL_TOKEN="${PROOFPULSE_INSTALL_TOKEN:-}"
API_URL="${PROOFPULSE_API_URL:-https://proofpulse.app}"
# If one-liner has /api but API is at root (e.g. direct :3001), strip so agent doesn't 404
[[ "$API_URL" == */api ]] && API_URL="${API_URL%/api}"
GITHUB_REPO="${PROOFPULSE_GITHUB_REPO:-}"
# Binary: GitHub Releases if repo set, else custom URL or default
if [ -n "$GITHUB_REPO" ]; then
  BINARY_URL="${PROOFPULSE_BINARY_URL:-https://github.com/${GITHUB_REPO}/releases/latest/download/proofpulse-agent-linux-amd64}"
else
  BINARY_URL="${PROOFPULSE_BINARY_URL:-}"
fi
if [ -z "$BINARY_URL" ]; then
  echo "Error: Set PROOFPULSE_GITHUB_REPO=user/repo (or PROOFPULSE_BINARY_URL) so the script can download the agent binary."
  exit 1
fi
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/proofpulse"
CONFIG_FILE="${CONFIG_DIR}/agent.json"
SERVICE_NAME="proofpulse-agent"

if [ -z "$INSTALL_TOKEN" ]; then
  echo "Error: PROOFPULSE_INSTALL_TOKEN is required."
  echo "Get your install token from the ProofPulse pairing page, then run the one-line command shown there."
  exit 1
fi

# Create system user if not exists
if ! id -u proofpulse &>/dev/null; then
  useradd -r -s /bin/false -d /var/lib/proofpulse proofpulse
fi

mkdir -p "$CONFIG_DIR"

# Download to /tmp first to avoid curl (23) when writing directly to /usr/local/bin under piped sudo
echo "Downloading agent from $BINARY_URL ..."
TMP_BINARY="/tmp/proofpulse-agent-$$"
if ! curl -sSLf -o "$TMP_BINARY" "$BINARY_URL"; then
  echo "Error: could not download binary. Ensure a release exists with asset proofpulse-agent-linux-amd64."
  exit 1
fi
chmod +x "$TMP_BINARY"
mv -f "$TMP_BINARY" "${INSTALL_DIR}/proofpulse-agent"
chown root:root "${INSTALL_DIR}/proofpulse-agent"

# Write config (agent will register on first run and update config with server_id)
cat > "$CONFIG_FILE" << EOF
{
  "api_url": "$API_URL",
  "install_token": "$INSTALL_TOKEN",
  "server_id": ""
}
EOF
chmod 600 "$CONFIG_FILE"
chown proofpulse:proofpulse "$CONFIG_FILE" 2>/dev/null || true

# Systemd service
cat > "/etc/systemd/system/${SERVICE_NAME}.service" << 'SVCEOF'
[Unit]
Description=ProofPulse Agent
After=network.target

[Service]
Type=simple
User=root
Group=root
ExecStart=/usr/local/bin/proofpulse-agent
Restart=on-failure
RestartSec=5
Environment=PROOFPULSE_CONFIG=/etc/proofpulse/agent.json

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl start "$SERVICE_NAME"
echo "ProofPulse agent installed and started."
echo "Config: $CONFIG_FILE"
echo "Status: systemctl status $SERVICE_NAME"
