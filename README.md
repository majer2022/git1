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



🚀 How to run the system
🖥️ 1. Run the server (Linux)

First, copy and run the server application (project1) on a Linux machine.

After starting the server, it will listen on a selected IP address and port, for example:

http://192.168.1.50:8080

👉 Replace 192.168.1.50 with the IP address of the machine running the server.

🌐 2. Access via browser (Web UI)

Once the server is running, you can open the following address on any device in the same local network:

http://<SERVER_IP>:8080

Example:

http://192.168.1.50:8080

This will open the web interface, allowing you to:

view clipboard content
copy text between machines
edit and synchronize data in real-time

Works on:

Windows ✔
Linux ✔
Android ✔
any modern web browser ✔
💻 3. Optional Linux client (recommended)

The client is a separate application that extends system functionality by enabling automatic clipboard synchronization.

⚠️ It is not required, but strongly recommended for full real-time syncing.

📦 Install required dependency

Before running the client, install xclip:

sudo apt install xclip
▶️ Run the client

Start the clipboard synchronization client with:

./ClipboardSyncLinux -a 192.168.1.50 -p 8080

Replace:

192.168.1.50 → your server IP address
8080 → your server port
🔁 How it works

Once the client is running:

clipboard changes are automatically detected
text is sent to the server
server updates are synchronized across all connected devices
browser interface reflects real-time updates
⚡ Summary
Server runs on Linux (project1)
Web interface available via IP:PORT
Client (ClipboardSyncLinux) enables full automatic sync
Requires xclip on Linux client
