#!/usr/bin/env bash
# Browser-accessible Debian/XFCE desktop via noVNC.
# Pipeline:  Xvfb -> xfce4 + Chromium -> x11vnc -> websockify(noVNC HTTP+WS) -> $PORT
#
# IMPORTANT: Xvfb must start and be READY before any X client (autocutsel,
# x11vnc, xfce4, chromium) connects. No daemon failure may exit the script,
# or Railway will restart-loop it. So: NO `set -e`; guard every daemon.

export DISPLAY="${DISPLAY:-:0}"
VNC_PORT="${VNC_PORT:-5900}"
# Railway injects $PORT (the public HTTP port it routes to the container).
WEB_PORT="${PORT:-6080}"
VNC_PASSWORD="${VNC_PASSWORD:-debian}"
# 16-bit color = ~half the bandwidth of 24-bit, big noVNC speedup.
RESOLUTION="${RESOLUTION:-1280x720x16}"

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
(service dbus start 2>/dev/null || dbus-daemon --system --fork 2>/dev/null || true)

# --- Swap (best-effort, never fatal). RAM-light Railway plans benefit. ---
if [ ! -f /swapfile ]; then
    { dd if=/dev/zero of=/swapfile bs=1M count=1024 status=none
      chmod 600 /swapfile
      mkswap /swapfile; } >/dev/null 2>&1 || true
fi
swapon /swapfile 2>/dev/null || true

# --- Virtual framebuffer: MUST start first and be ready before X clients ---
Xvfb "${DISPLAY}" -screen 0 "${RESOLUTION}" -ac +extension RANDR \
    > /var/log/xvfb.log 2>&1 &
XVFB_PID=$!

# Wait until the X server is actually accepting connections.
echo "==> Waiting for Xvfb to be ready..."
READY=0
for i in $(seq 1 40); do
    if xdpyinfo -display "${DISPLAY}" >/dev/null 2>&1; then
        READY=1
        break
    fi
    sleep 0.5
done
if [ "${READY}" -ne 1 ]; then
    echo "==> WARNING: Xvfb not ready after 20s, continuing anyway. Xvfb log:"
    tail -n 20 /var/log/xvfb.log 2>/dev/null || true
else
    echo "==> Xvfb ready (pid ${XVFB_PID})"
fi

# --- Clipboard sync: now safe (display exists). Non-fatal. ---
autocutsel -fork >/dev/null 2>&1 || true
autocutsel -selection PRIMARY -fork >/dev/null 2>&1 || true
autocutsel -selection CLIPBOARD -fork >/dev/null 2>&1 || true

# --- VNC server (shares the Xvfb display) ---
# Performance tuning for noVNC: threaded, tight encoding, no xdamage.
x11vnc -display "${DISPLAY}" -forever -shared -bg \
    -rfbport "${VNC_PORT}" "${VNC_AUTH[@]}" \
    -threads -threadperclient \
    -noxdamage -norepeat \
    -speeds modem,4,2 -tightfilexfer off \
    -o /var/log/x11vnc.log || true

# --- Desktop session ---
export XDG_SESSION_TYPE=x11
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/dbus/system_bus_socket"
# Run xfce4 WITHOUT the compositor (shadows/transparency cause full-screen
# redraws every frame over VNC = lag). Biggest noVNC speedup.
export XFCE_COMPOSITOR=0
mkdir -p /root/.config/xfce4/xfconf/xfce-perchannel-xml
cat > /root/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4">
  <property name="general" type="empty">
    <property name="use_compositing" type="bool" value="false"/>
    <property name="theme" type="string" value="Default"/>
    <property name="box_move" type="bool" value="true"/>
    <property name="box_resize" type="bool" value="true"/>
  </property>
</channel>
XML
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
        --disable-software-rasterizer \
        --disable-background-networking \
        --disable-default-apps \
        --disable-component-update \
        --disable-sync \
        --disable-translate \
        --disable-background-timer-throttling \
        --disable-renderer-backgrounding \
        --disable-backgrounding-occluded-windows \
        --memory-pressure-off \
        --start-maximized \
        "about:blank"
) > /var/log/chromium.log 2>&1 &

# --- noVNC over HTTP/WebSocket (this is what Railway exposes) ---
echo "==> Starting noVNC on http://0.0.0.0:${WEB_PORT}/  (click Connect, enter password)"
exec websockify --web /usr/share/novnc/ 0.0.0.0:"${WEB_PORT}" "localhost:${VNC_PORT}"
