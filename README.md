# Browser Desktop (Debian + XFCE + Chromium via noVNC)

A full Debian/XFCE desktop with **Chromium** that opens **directly in your web browser** — no RDP client needed. Designed to deploy on **Railway** (HTTP-only), Docker, or any Ubuntu VM.

> Browser-based fork of [`hopingboyz/debianxrdp`](https://github.com/hopingboyz/debianxrdp). The original exposes RDP on TCP 3389, which Railway cannot route — so this image serves the desktop over **HTTP/WebSocket via noVNC** instead.

## What you get
- 🖥️ Debian Bookworm + XFCE desktop, in a browser tab
- 🌐 **Chromium** preinstalled (with `--no-sandbox` for containers)
- 🪟 Resolution `1280x720` by default (configurable)
- 🔐 Password-protected VNC session
- ⚡ Single port (`$PORT`) — Railway-ready

## Quick start (local Docker)

```bash
docker build -t browser-desktop .

# 6080 = the port you open in your browser
docker run -d -p 6080:6080 --name desktop browser-desktop
```

Open **http://localhost:6080/** → click **Connect** → enter password `debian`.

## Deploy on Railway

1. Push this folder to a new GitHub repo (see below).
2. On [railway.com](https://railway.com) → **New Project → Deploy from GitHub repo**.
3. Railway auto-detects the Dockerfile (see `railway.json`) and injects `$PORT`.
4. Once deployed, open Railway's generated `*.up.railway.app` URL → **Connect** → password `debian`.

### Environment variables (all optional)

| Variable | Default | Description |
|---|---|---|
| `VNC_PASSWORD` | `debian` | Password to connect to the desktop |
| `RESOLUTION` | `1280x720x24` | Xvfb screen resolution (WxHxD) |
| `PORT` | `6080` | HTTP port (Railway sets this automatically) |
| `VNC_PORT` | `5900` | Internal VNC port (no need to change) |

## Push to GitHub

```bash
git init
git add .
git commit -m "Browser desktop: Debian + XFCE + Chromium via noVNC"
git branch -M main
git remote add origin https://github.com/<YOU>/<REPO>.git
git push -u origin main
```

## Files
- `Dockerfile` — Debian + Xvfb + x11vnc + noVNC + XFCE + Chromium
- `start.sh` — boots Xvfb → XFCE → Chromium → x11vnc → websockify(noVNC)
- `railway.json` — Railway build/deploy config
- `.dockerignore` / `.gitignore` — keep the image & repo clean
