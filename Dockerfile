FROM debian:bookworm

ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:0

# --- Core: virtual X server, VNC, noVNC websocket bridge, desktop, Chromium ---
RUN apt-get update && apt-get install -y --no-install-recommends \
        xvfb \
        x11vnc \
        novnc \
        websockify \
        xfce4 \
        xfce4-terminal \
        dbus \
        x11-xserver-utils \
        x11-utils \
        wmctrl \
        curl \
        ca-certificates \
        fonts-liberation \
        fonts-dejavu-core \
        chromium \
        autocutsel \
        xclip \
        xsel \
        python3 \
        sudo \
    && rm -rf /var/lib/apt/lists/*

# noVNC landing page: auto-connect, scale to browser window, websocket at /websockify
RUN VNC_PAGE="$(ls /usr/share/novnc/vnc.html >/dev/null 2>&1 && echo vnc.html || echo vnc_lite.html)" && \
    printf '<!DOCTYPE html>\n<html><head><meta charset="utf-8">\n<meta http-equiv="refresh" content="0; url=%s?autoconnect=1&resize=scale&reconnect=1&path=websockify">\n<title>Desktop</title></head>\n<body style="background:#111;color:#eee;font-family:sans-serif;text-align:center;padding-top:2em">Opening desktop&hellip;</body></html>\n' "$VNC_PAGE" > /usr/share/novnc/index.html

COPY start.sh /start.sh
# Guard against Windows CRLF line endings breaking the shebang when built
RUN sed -i 's/\r$//' /start.sh && chmod +x /start.sh

EXPOSE 6080

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -fsS "http://127.0.0.1:${PORT:-6080}/" || exit 1

CMD ["/start.sh"]
