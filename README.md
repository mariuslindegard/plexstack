# 📦 Deployable Plex Stack (Docker-Based)

A fully automated and easily deployable Plex media server stack powered by Docker Compose. This setup includes:

- Plex Media Server
- Sonarr (TV shows)
- Radarr (Movies)
- Prowlarr (Indexer management)
- qBittorrent (Downloader)
- Rclone (Google Drive mount)
- Portainer (Optional container manager)
- Nginx Proxy Manager (Optional domain routing)

---

## ⚙️ Requirements

- Ubuntu 24.04 LTS or similar
- Docker & Docker Compose
- A Google Drive account (for Rclone)
- Plex.tv account

---

## 🚀 Installation

### 1. Update your system

```bash
sudo apt update && sudo apt upgrade
```

### 2. Clone the repository

It’s recommended to clone into `/opt/`:

```bash
cd /opt
git clone https://github.com/yourusername/plexstack.git
cd plexstack
```

### 3. Install Docker

```bash
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/keyrings/docker.asc > /dev/null
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

### 4. Install Rclone

```bash
sudo apt install rclone
```

---

## 🔗 Rclone Configuration

Run `rclone config` and follow the steps to add a new remote (e.g. Google Drive).

**Tips:**

- If on a headless server, press `n` during auto config. Follow the instructions to authorize on a local machine.
- Optionally, use your own Google API credentials for quota control.
- To avoid mixing personal files, set a `root_folder_id` (found in your Drive folder URL).

Once complete, move the config file:

```bash
mkdir -p rclone-config
mv ~/.config/rclone/rclone.conf rclone-config/
```

---

## 📄 Environment Setup

Copy and edit the `.env` file:

```bash
cp .env.example .env
nano .env
```

Update the following fields:

- `PLEX_CLAIM=<your plex.tv claim token>`
- `SONARR_API_KEY=`
- `RADARR_API_KEY=`
- `PROWLARR_API_KEY=`

You can retrieve these API keys after launching the services (next step).

---

## 🐳 Launch the Stack

```bash
docker compose up -d
```

Ignore any initial errors from the `autoconfig` container — they’re expected until keys are populated.

---

## 🔑 Get Your API Keys

Open a browser and visit your server's IP with the following ports:

- **Sonarr**: `http://<IP>:8989`
- **Radarr**: `http://<IP>:7878`
- **Prowlarr**: `http://<IP>:9696`

Navigate to **Settings → General**, copy each API key, and paste into your `.env` file.

Then restart your stack:

```bash
docker compose restart
```

---

## 🧩 Final Configuration

- Open Prowlarr and add your favorite indexers.
- Open Plex, add your media libraries (from `/media/movies` and `/media/tv`).
- Done! 🎉

---

## 🌐 Optional: Nginx Proxy Manager Setup

If you'd like to route your services through subdomains like `plex.yourdomain.com`, instructions for configuring Nginx Proxy Manager will be added soon.

---

## 📬 Contributions & Feedback

If you find a bug or want to contribute, feel free to open an issue or submit a PR. Your feedback is appreciated!

---
