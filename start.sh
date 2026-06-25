#!/usr/bin/env bash
# Browser-accessible Debian/XFCE desktop via noVNC.
# Pipeline:  Xvfb -> xfce4 + Chromium -> x11vnc -> websockify(noVNC HTTP+WS) -> $PORT
set -e

export DISPLAY="${DISPLAY:-:0}"
VNC_PORT="${VNC_PORT:-5900}"
# Railway injects $PORT (the public HTTP port it routes to the container).
WEB_PORT="${PORT:-6080}"
VNC_PASSWORD="${VNC_PASSWORD:-debian}"
# 16-bit color = ~half the bandwidth of 24-bit, big noVNC speedup with little visible loss.
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
service dbus start 2>/dev/null || dbus-daemon --system --fork 2>/dev/null || true

# --- Swap: many Railway plans are RAM-light. A 1GB swap file prevents
#     thrashing/OOM-kills when Chromium + XFCE peak together. ---
if [ ! -f /swapfile ]; then
    dd if=/dev/zero of=/swapfile bs=1M count=1024 status=none 2>/dev/null && \
    chmod 600 /swapfile && mkswap /swapfile >/dev/null 2>&1
fi
swapon /swapfile 2>/dev/null || true

# --- Clipboard sync: keep PRIMARY/CLIPBOARD selections in sync so that
#     text copied on the VNC client side and the desktop side stays mirrored.
#     autoselection = copy on mouse-select; autocut = sync CLIPBOARD <-> PRIMARY ---
autocutsel -fork
autocutsel -selection PRIMARY -fork
autocutsel -selection CLIPBOARD -fork

# --- Virtual framebuffer ---
Xvfb "${DISPLAY}" -screen 0 "${RESOLUTION}" -ac +extension RANDR \
    > /var/log/xvfb.log 2>&1 &
sleep 1

# --- VNC server (shares the Xvfb display) ---
# Performance tuning for noVNC:
#   -threads -threadperclient : handle each viewer on its own thread
#   -tightfilexfer off        : skip file transfer (not used by noVNC)
#   -noxdamage                : X DAMAGE extension is unreliable under Xvfb; off = smoother
#   -norepeat                 : avoid auto-repeat key floods over the link
#   -nowf / -nowcr            : no wireframe / cursor tracking (less back-and-forth)
#   -speeds modem,4,2         : hint heavy compression (LAN=4, modem=slowest link type)
#   -tight encoding            : best compression for slow links
x11vnc -display "${DISPLAY}" -forever -shared -bg \
    -rfbport "${VNC_PORT}" "${VNC_AUTH[@]}" \
    -threads -threadperclient \
    -noxdamage -norepeat \
    -speeds modem,4,2 -tightfilexfer off \
    -o /var/log/x11vnc.log

# --- Desktop session ---
export XDG_SESSION_TYPE=x11
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/dbus/system_bus_socket"
# Run xfce4 without the compositor (shadows/transparency cause full-screen redraws
# every frame over VNC = lag). This is the single biggest noVNC speedup.
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
    <property name="wrap_windows" type="bool" value="false"/>
    <property name="wrap_workspaces" type="bool" value="false"/>
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
