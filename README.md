# Offline IPTV Launch Tool v2 (Infinite Stream)

A professional-grade, local-first IPTV bridge designed to bypass aggressive CDN firewalls and AES-128 encryption. Version 2 introduces **Infinite Streaming** logic to handle long-term viewing without interruptions.

## Key Features

### Infinite Streaming (Key Rotation)
Live HLS streams rotate their encryption keys frequently. Version 2 of the bridge includes an intelligent proxy that:
- **Detects Missing Keys**: When VLC requests a key that has rotated out, the bridge detects it instantly.
- **Background Auto-Refresh**: The bridge launches a hidden browser session in the background to "grab" the latest keys from the source session.
- **Zero-Interruption**: The playback continues seamlessly as the proxy fulfills the request once the new key is captured.

### VLC Buffer Optimization
Launched VLC with advanced streaming flags to ensure maximum stability on fluctuating network conditions:
- `--network-caching=5000`: Maintains a 5-second buffer (up from the 300ms default).
- `--clock-jitter=0`: Professional-grade sync for live HLS streams.
- `--no-video-title-show`: Removes overlay text for a cleaner, "Premium TV" feel.

---

## Prerequisites

1. **Operating System**: macOS (optimized), Linux, or Windows (WSL).
2. **Node.js**: v18+ recommended.
3. **VLC Media Player**: Must be installed.
4. **Dependencies**:
    * Run `pnpm install`
    * Run `npx playwright install chromium`

---

## Quick Start

**Step 1: Install Dependencies**
```bash
npm install
npx playwright install chromium
```

**Step 2: Run the application**
```bash
./start.sh
```

**Step 3: Watch!**
Select your channel from the **Pure Black** web interface. VLC will open with optimized buffers and the bridge will manage key rotation in the background.

---

## Technical Details

- **Proxy Bridge**: Rewrites `.m3u8` playlists and appends `&ext=.ts` to bypass VLC/FFmpeg extension blocklists.
- **Deduplication**: Uses a `refreshPromise` to prevent "launch storms" when multiple segments request a rotated key simultaneously.
- **Architecture**: Playwright-based decryption interception + Express-based local proxy.
