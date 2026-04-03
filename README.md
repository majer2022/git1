# 📋 LAN Clipboard Sync System

A lightweight clipboard synchronization system for local networks (LAN), enabling fast text sharing between multiple machines and virtual machines.

---

# ⚙️ How it works

The system consists of two main components:

- 🌐 **Server (Pascal / FreePascal HTTP Server)**
- 💻 **Client (Linux + xclip)**

and an optional:
- 🌍 **Web UI (HTML + JavaScript browser interface)**

---

# 🔁 Synchronization flow

## 📤 Client → Server
- the client monitors the system clipboard (`xclip`)
- when a change is detected:
  - it sends the text to the server via HTTP POST

---

## 📥 Server → Client
- the server stores the current clipboard value in a variable (`s`)
- clients periodically request data via HTTP GET
- if a change is detected:
  - the local clipboard is updated automatically

---

## 🌐 Web UI
The server also provides a simple web interface accessible via:
