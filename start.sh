#!/usr/bin/env bash
# Browser-accessible Debian/XFCE desktop via noVNC.
# Pipeline:  Xvfb -> xfce4 + Chromium -> x11vnc -> websockify(noVNC HTTP+WS) -> $PORT
set -e

export DISPLAY="${DISPLAY:-:0}"
VNC_PORT="${VNC_PORT:-5900}"
# Railway injects $PORT (the public HTTP port it routes to the container).
WEB_PORT="${PORT:-6080}"
VNC_PASSWORD="${VNC_PASSWORD:-debian}"
RESOLUTION="${RESOLUTION:-1280x720x24}"

echo "==> Display=${DISPLAY} Resolution=${RESOLUTION}"
echo "==> VNC port=${VNC_PORT} Web(HTTP) port=${WEB_PORT}"
echo "==> VNC password: ${VNC_PASSWORD}"

# --- VNC password ---
mkdir -p /root/.vnc
if [ -n "${VNC_PASSWORD}" ]; then
    x11vnc -storepasswd "${VNC_PASSWORD}" /root/.vnc/passwd
    VNC_AUTH=(-rfbauth /root/.vnc/passwd)
else
    VNC_AUTH=(-nopw)
fi

# --- D-Bus (system bus for xfce4) ---
mkdir -p /run/dbus
service dbus start 2>/dev/null || dbus-daemon --system --fork 2>/dev/null || true

# --- Virtual framebuffer ---
Xvfb "${DISPLAY}" -screen 0 "${RESOLUTION}" -ac +extension RANDR +extension GLX \
    > /var/log/xvfb.log 2>&1 &
sleep 1

# --- VNC server (shares the Xvfb display) ---
x11vnc -display "${DISPLAY}" -forever -shared -bg \
    -rfbport "${VNC_PORT}" "${VNC_AUTH[@]}" \
    -o /var/log/x11vnc.log

# --- Desktop session ---
export XDG_SESSION_TYPE=x11
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/dbus/system_bus_socket"
startxfce4 > /var/log/xfce4.log 2>&1 &

# --- Chromium, launched once the desktop is up ---
(
    sleep 4
    exec chromium \
        --no-sandbox \
        --no-first-run \
        --no-default-browser-check \
        --disable-gpu \
        --disable-dev-shm-usage \
        --start-maximized \
        "about:blank"
) > /var/log/chromium.log 2>&1 &

# --- noVNC over HTTP/WebSocket (this is what Railway exposes) ---
echo "==> Starting noVNC on http://0.0.0.0:${WEB_PORT}/  (click Connect, enter password)"
exec websockify --web /usr/share/novnc/ 0.0.0.0:"${WEB_PORT}" "localhost:${VNC_PORT}"
