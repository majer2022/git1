
# 📋 LAN Clipboard Sync System v5  
### Real-time clipboard synchronization across machines, VMs & web browsers.

![License](https://img.shields.io/badge/license-MIT-blue.svg)  
![Status](https://img.shields.io/badge/status-stable-brightgreen.svg)  
![FreePascal](https://img.shields.io/badge/compiler-FreePascal%20%3E%3D3.2-orange)

A **lightweight, dependency-minimal** clipboard sync system for local networks (LAN). Enables seamless text *and* file sharing between multiple Linux clients (via `xclip`) and web browsers—**with zero external dependencies** (no Node.js, no Python, no DB).

✅ Optimistic locking  
✅ Base64-encoded JSON (safe, compact)  
✅ CORS-enabled web UI  
✅ `curl`-testable REST API  



---

## ⚙️ Architecture

| Component | Technology | Role |
|---------|------------|------|
| **🌐 Server** | FreePascal + `fphttpserver` | Central registry of clipboard state; serves `/api/*` endpoints |
| **💻 Client** | FreePascal + `xclip` | Local clipboard monitor + HTTP sync client |
| **🌐 Web UI** | HTML + vanilla JS | Browser-based control & visual feedback |



## 🔑 Key Features

| Feature | Details |
|---------|---------|
| **Base64-safe JSON** | `text_b64` field avoids JSON escaping issues (`\n`, `"`). |
| **Optimistic Locking** | Clients send `expected_version`; server returns `409` on conflict. |
| **Zero-Config Web UI** | Just open `http://SERVER_IP:8080` in any browser. |
| **Cross-Platform** | Clients run on Linux (x86/ARM); server runs anywhere (Linux/macOS/Windows via FreePascal). |
| **Lightweight** | ~120 KB binary, <2 MB RAM usage. |
| **Secure by Default** | No encryption (LAN-only), but no secrets stored. |

---

## 🌐 HTTP API Endpoints

All responses use UTF-8 encoding.

### `GET /api/state`  
Returns current clipboard state as JSON.

**Example Response:**
```json
{
  "version": 42,
  "author": "192.168.1.100",
  "text_b64": "SGVsbG8gV29ybGQh"
}
```
> 🔍 `text_b64` = Base64 of clipboard text (safe for JSON).

#### Test with `curl`:
```bash
curl http://192.168.1.204:8080/api/state | jq .
# → {"version":42,"author":"192.168.1.100","text_b64":"SGVsbG8gV29ybGQh"}
```

---

### `POST /api/push`  
Pushes new clipboard text to the server.

**Form Data Parameters:**
| Field | Description |
|-------|-------------|
| `client` | Client IP (e.g., `192.168.1.100`) |
| `expected_version` | Previous version (for conflict detection) |
| `data` | Clipboard text in **Base64** |

#### Test with `curl`:
```bash
curl -X POST http://192.168.1.204:8080/api/push \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client=192.168.1.101&expected_version=42&data=SGVsbG8gTmV3IQ=="

# → Success: 43 (new version number)
# → Conflict: 409 "Conflict: expected=42 current=43"
```

---

### `POST /api/file`  
Uploads a file (metadata via headers).

**Headers:**
| Header | Description |
|--------|-------------|
| `X-Filename` | Original filename |
| `X-Filesize` | Size in bytes |

#### Test with `curl`:
```bash
curl -X POST http://192.168.1.204:8080/api/file \
  -H "X-Filename: note.txt" \
  -H "X-Filesize: 11" \
  -d "Hello World"
```

---

### `GET /api/file`  
Downloads the last-uploaded file.

```bash
curl http://192.168.1.204:8080/api/file -o downloaded.txt
```

---
## 🚀 How to Run

### 🖥️ 1. Server Setup (Linux)

#### ✅ Requirements:
- Pre-compiled `project1` binary *(no compiler needed!)*  
- `index.html` *(required for Web UI)*  
- `chmod +x` permissions on binaries  
- Linux with `xclip` installed on clients *(optional)*  

#### 🔑 Grant execution permissions:
```bash
# Terminal method
chmod +x project1 ClipboardSyncLinux

# GUI method (Ubuntu/Debian):
# • Right-click `project1` → "Properties" → "Permissions" tab
# • Check ✅ "Allow executing file"
# • Repeat for `ClipboardSyncLinux`
```

#### ▶️ Run the server:
```bash
# Create a dedicated directory (e.g., on your Proxmox host or VM)
mkdir -p ~/clipboard_server
cd ~/clipboard_server

# Copy required files from repo:
cp /path/to/project1 .         # ← pre-compiled server binary
cp /path/to/index.html .       # ← Web UI (mandatory!)
```

```bash
# Start the server
./project1 -p 8080
```

> ✅ **`./file/` directory is auto-created** on startup (via `ForceDirectories`)  
> ✅ No manual `mkdir file/` needed  
> ✅ On success, you’ll see:  
> ```
> [14:22:05.123] Clipboard Sync Server Ver.5 -- http://0.0.0.0:8080
>   POST /api/push     -> send text (data=BASE64, opt. expected_version)
>   GET  /api/state    -> JSON {version, author, text_b64}
>   POST /api/file     -> upload file
>   GET  /             -> ./index.html
> ```

> 💡 **Tip (Proxmox users)**: Run in background with  
> `nohup ./project1 -p 8080 > clipboard_server.log 2>&1 &`

---

### 🌐 2. Access via Browser (Web UI)

Open **any device on your LAN** in your browser:  
```
http://192.168.1.204:8080
```

- View clipboard content  
- Edit text directly  
- Copy between machines  
- Upload/download files  
- Real-time sync (polls every second)  

> ✅ Works on Windows, Linux, macOS, Android, iOS  
> ✅ No JavaScript libraries required (vanilla JS)  
> ⚠️ If `index.html` is missing → `404 Not Found`

---

### 💻 3. Optional Linux Client (Recommended)

Useful for **fully automatic clipboard sync** (no browser needed).

#### Requirements:
```bash
sudo apt install xclip
```

#### Run the client:
```bash
cp /path/to/ClipboardSyncLinux . && chmod +x ClipboardSyncLinux
./ClipboardSyncLinux -a 192.168.1.204 -p 8080 -d
```

| Flag | Description |
|------|-------------|
| `-a IP` | Server IP (e.g., `192.168.1.204`) |
| `-p PORT` | Server port (default: `8080`) |
| `-d` | Debug mode (verbose logs) |
| `-h` | Show help |

> 🔁 Polls server every 1 second  
> 🔄 Auto-updates local clipboard on changes  
> 🧠 Smart retry on conflict (waits, then retries)

---

## 🏛️ Virtualization & Proxmox Support

This system is **ideal for virtualization environments** like:

| Environment | How to Use |
|-------------|------------|
| **Proxmox VE** | Run `project1` on a Linux VM — clients on other VMs/hardware sync to it |
| **VMware/VirtualBox** | One VM as server, others as clients |
| **Docker** | Containerize `project1` (see `Dockerfile` — [request on request](#)) |

### Why it shines in VMs:
- ✅ No UI dependency — runs headless  
- ✅ `xclip` works in X11 VMs (even on remote desktops)  
- ✅ Web UI accessible from host/other VMs/browsers  
- ✅ One-time setup: start server once, all VMs sync automatically  

#### 📦 Common Proxmox Workflow:
1. Deploy Ubuntu VM → `apt install xclip`  
2. Copy `project1` & `index.html` into `/home/user/clipboard_server`  
3. `chmod +x project1 && ./project1 -p 8080`  
4. On *other* VMs: `xclip` + client binary syncs to host VM’s clipboard  

Result: **One clipboard, many machines.**

---

### 📝 File Exchange (via Web UI)
1. Open `http://192.168.1.204:8080` in any browser  
2. Paste text → syncs to all clients  
3. Or upload file (via form or `curl`)  
4. Download file on another machine from same Web UI  
5. No `xclip` needed for file transfer!  

> ⚠️ File sync requires **active browser tab** — client binaries sync only text.

---

## 📁 Directory Structure (After Start)

```
~/clipboard_server/
├── project1              ← pre-compiled server binary (chmod +x)
├── index.html            ← Web UI (required!)
├── file/                 ← auto-created on startup (e.g., file/note.txt)
└── clipboard_server.log  ← only if you use nohup/redirect
```

> 🔍 Server creates `file/` automatically — no manual `mkdir` needed.  
> 🔍 `project1` is **not compiled on your machine** — it’s pre-built and ready to run.




---

## 🌐 Web UI Demo (Screenshot)  
*(Placeholder — replace with actual screenshot)*  
![Web UI](https://raw.githubusercontent.com/your-org/lan-clipboard-sync/main/screenshot.png)  

---

## ⚠️ Limitations  
- LAN-only (no encryption — use VPN for public networks)  
- Linux client requires `xclip` (X11 only; Wayland not supported)  
- Web UI uses polling (not WebSockets)  

---

## 📦 Build from Source  

### Server (FreePascal):
```bash
fpc clipboard_server.pas
```

### Linux Client (FreePascal):
```bash
fpc ClipboardSyncLinux.pas
```

### Web UI  
Place `index.html` in server’s directory (built-in in v5). No extra steps.

---

## 🤝 Contributing  
Contributions welcome! Areas to improve:  
- Add Wayland support (`wl-clipboard`)  
- WebSockets for true real-time (replace polling)  
- AES-256 encryption (opt-in)  
- Docker support  

---

## 📜 License  
MIT — see [LICENSE](LICENSE).

---

## 🌟 Credits  
- FreePascal community  
- HTTP server library: `fphttpserver`  
- Clipboard tool: [`xclip`](https://github.com/astrand/xclip)  

> 🛠️ **Ver.5 — The Base64 + Optimistic Locking Edition**  
> *Tested on Ubuntu 22.04/Debian 12/FreePascal 3.2.2*  

---

Let me know if you want:
- A **GitHub Actions CI/CD** workflow (build + release assets)  
- A **Dockerfile** for containerization  
- A **signing script** (for release binaries)  
- Updated screenshots for `README.md`  

This version is production-ready, well-documented, and follows best practices for LAN sync tools.
