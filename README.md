# 📋 LAN Clipboard Sync System

A lightweight clipboard synchronization system for local networks (LAN), enabling fast text sharing between multiple machines and virtual machines.



# ⚙️ How it works

The system consists of two main components:

- 🌐 **Server (Pascal / FreePascal HTTP Server)**
- 💻 **Client (Linux + xclip)**

and an optional:

- 🌍 **Web UI (HTML + JavaScript browser interface)**



# 🔁 Synchronization flow

## 📤 Client → Server

- the client monitors the system clipboard (`xclip`)
- when a change is detected:
  - it sends the text to the server via HTTP POST


## 📥 Server → Client

- the server stores the current clipboard value in a variable (`s`)
- clients periodically request data via HTTP GET
- if a change is detected:
  - the local clipboard is updated automatically



# 🌐 Web UI

The server provides a simple web interface accessible via:


http://SERVER_IP:8080


This interface allows you to:

- 👀 view clipboard content  
- ✏️ edit text  
- 📋 copy between machines  
- 🔄 real-time synchronization  

Works on:

- Windows ✔  
- Linux ✔  
- Android ✔  
- Any modern web browser ✔  



# 🚀 How to run the system


## 🖥️ 1. Run the server (Linux)

First, copy and run the server application (`project1`) on a Linux machine.

After starting, it will listen on:


http://192.168.1.50:8080


👉 Replace `192.168.1.50` with your server machine IP.

---

## 🌐 2. Access via browser (Web UI)

Open in any device in the same network:


http://<SERVER_IP>:8080


Example:


http://192.168.1.50:8080




# 💻 3. Optional Linux client (recommended)

The client is a separate application that enables automatic clipboard synchronization between machines.

⚠️ Not required for basic web usage, but strongly recommended for real-time syncing.



## 📦 Requirements

Before running the client, install dependency:


sudo apt install xclip

▶️ Run client

./ClipboardSyncLinux -a 192.168.1.50 -p 8080

Replace:

192.168.1.50 → server IP address
8080 → server port
🔁 How it works (end-to-end)

Once the client is running:

clipboard changes are automatically detected
text is sent to the server
server syncs updates to all connected devices
web interface reflects changes in real-time

⚡ Summary
🖥️ Server runs on Linux (project1)
🌐 Web UI available via IP:PORT
💻 Client (ClipboardSyncLinux) enables full automation
📦 Requires xclip on Linux client
🔄 Designed for fast LAN clipboard synchronization
