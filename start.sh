#!/usr/bin/env bash
# ==============================================================================
# Offline IPTV Launch Tool (Pure Shell + Node.js Bridge)
# ==============================================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}==============================================${NC}"
echo -e "${BLUE} Local IPTV Launch Agent ${NC}"
echo -e "${BLUE}==============================================${NC}"

# Cleanup function to kill children on exit
cleanup() {
    echo -e "\n${YELLOW}[*] Shutting down bridge and cleaning up...${NC}"
    # Kill the entire process group if possible, or just children
    [ -n "$BRIDGE_PID" ] && kill $BRIDGE_PID 2>/dev/null
    exit
}
trap cleanup SIGINT SIGTERM EXIT

# 0. Detect Operating System
OS_TYPE="$(uname -s)"
case "${OS_TYPE}" in
    Linux*)     OS_SYS="Linux";;
    Darwin*)    OS_SYS="Mac";;
    CYGWIN*)    OS_SYS="Windows";;
    MINGW*)     OS_SYS="Windows";;
    MSYS*)      OS_SYS="Windows";;
    *)          OS_SYS="UNKNOWN"
esac

# 1. Check if VLC is installed (Cross-Platform)
VLC_PATH=""
if [ "$OS_SYS" == "Mac" ]; then
    if [ -x "/Applications/VLC.app/Contents/MacOS/VLC" ]; then
        VLC_PATH="/Applications/VLC.app/Contents/MacOS/VLC"
    elif command -v vlc >/dev/null 2>&1; then
        VLC_PATH="vlc"
    fi
elif [ "$OS_SYS" == "Windows" ]; then
    if [ -f "/c/Program Files/VideoLAN/VLC/vlc.exe" ]; then
        VLC_PATH="/c/Program Files/VideoLAN/VLC/vlc.exe"
    elif [ -f "/c/Program Files (x86)/VideoLAN/VLC/vlc.exe" ]; then
        VLC_PATH="/c/Program Files (x86)/VideoLAN/VLC/vlc.exe"
    elif command -v vlc.exe >/dev/null 2>&1; then
        VLC_PATH="vlc.exe"
    fi
elif [ "$OS_SYS" == "Linux" ]; then
    if command -v vlc >/dev/null 2>&1; then
        VLC_PATH="vlc"
    fi
fi

if [ -n "$VLC_PATH" ]; then
    echo -e "${GREEN}[+] VLC Media Player found.${NC}\n"
else
    echo -e "${RED}[Warning] VLC Media Player was not found in standard locations or PATH.${NC}"
    echo -e "${YELLOW}The bridge relies on VLC being installed to pass the live streams to it.${NC}"
fi


# 2. Load Channels and Start Local Node.js Bridge
echo -e "${BLUE}[*] Checking for offline channels library...${NC}"
if [ ! -f "channels.json" ]; then
    echo -e "${RED}[Error] channels.json not found! Exiting.${NC}"
    exit 1
fi
JSON_DB=$(cat channels.json)

# Count how many channels we loaded using a simple grep
CHANNEL_COUNT=$(grep -o '"name":' channels.json | wc -l | tr -d ' ')
echo -e "${GREEN}[+] Successfully loaded ${CHANNEL_COUNT} live TV channels from channels.json!${NC}"

echo -e "${BLUE}[*] Starting Local Node.js HLS Bridge...${NC}"
rm -f .bridge_port
export VLC_PATH="$VLC_PATH"
npx --yes tsx scripts/bridge.ts &
BRIDGE_PID=$!
USE_BRIDGE=true

# Wait for the port file to be created
echo -e "${BLUE}[*] Waiting for bridge to initialize...${NC}"
for i in {1..15}; do
    if [ -f .bridge_port ]; then
        break
    fi
    sleep 1
done

if [ ! -f .bridge_port ]; then
    echo -e "${RED}[Error] Failed to start Node.js HLS Bridge (timeout).${NC}"
    kill $BRIDGE_PID 2>/dev/null
    exit 1
fi

BRIDGE_PORT=$(cat .bridge_port)
echo -e "${GREEN}[+] Bridge is running on port ${BRIDGE_PORT}${NC}"

trap "kill $BRIDGE_PID 2>/dev/null; rm -f .bridge_port" EXIT

# 3. Generate the Web UI
echo -e "${BLUE}[*] Building offline user interface...${NC}"
cat > iptv-ui.html <<UI_EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>IPTV | Native Bridge</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;600&display=swap" rel="stylesheet">
    <style>
        :root {
            --bg: #000000;
            --surface: #0a0a0a;
            --accent: #ff3e00;
            --text: #ffffff;
            --text-dim: #888888;
            --border: #1a1a1a;
            --border-hover: #333333;
        }
        body { 
            font-family: 'Outfit', sans-serif; 
            background: var(--bg); 
            color: var(--text); 
            margin: 0; 
            padding: 40px 20px; 
            overflow-x: hidden;
        }
        .container { max-width: 1100px; margin: 0 auto; }
        
        header { text-align: center; margin-bottom: 50px; }
        h1 { 
            font-weight: 600; 
            font-size: 2.5rem; 
            letter-spacing: -1px; 
            margin-bottom: 8px;
            background: linear-gradient(135deg, #fff 0%, #888 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .subtitle { color: var(--text-dim); font-size: 15px; font-weight: 300; }
        
        .search-container {
            position: sticky;
            top: 20px;
            z-index: 100;
            margin-bottom: 40px;
        }
        .search-box { 
            width: 100%; 
            padding: 20px 24px; 
            font-size: 18px; 
            border-radius: 16px; 
            border: 1px solid var(--border); 
            background: rgba(10, 10, 10, 0.8); 
            backdrop-filter: blur(12px);
            color: #fff; 
            box-sizing: border-box; 
            outline: none; 
            transition: all 0.3s cubic-bezier(0.16, 1, 0.3, 1);
            font-family: inherit;
        }
        .search-box:focus { 
            border-color: var(--accent); 
            background: #000;
            box-shadow: 0 0 30px rgba(255, 62, 0, 0.15);
        }
        
        .grid { 
            display: grid; 
            grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); 
            gap: 20px; 
        }
        .card { 
            background: var(--surface); 
            padding: 24px; 
            border-radius: 16px; 
            border: 1px solid var(--border); 
            cursor: pointer; 
            transition: all 0.4s cubic-bezier(0.16, 1, 0.3, 1); 
            text-align: left;
            position: relative;
            overflow: hidden;
        }
        .card::after {
            content: '';
            position: absolute;
            top: 0; left: 0; right: 0; bottom: 0;
            background: linear-gradient(135deg, rgba(255,62,0,0.1), transparent);
            opacity: 0;
            transition: opacity 0.4s ease;
        }
        .card:hover { 
            border-color: var(--border-hover); 
            background: #0e0e0e; 
            transform: translateY(-4px) scale(1.02);
            box-shadow: 0 10px 40px rgba(0,0,0,0.5);
        }
        .card:hover::after { opacity: 1; }
        
        .card h3 { 
            margin: 0 0 10px 0; 
            font-size: 18px; 
            font-weight: 600;
            color: #efefef;
            transition: color 0.3s ease;
        }
        .card:hover h3 { color: var(--accent); }
        .card p { 
            margin: 0; 
            font-size: 12px; 
            color: var(--text-dim); 
            text-transform: uppercase; 
            letter-spacing: 1.5px;
            font-weight: 400;
        }
        
        #status { 
            margin-bottom: 25px; 
            padding: 20px; 
            text-align: center; 
            font-weight: 400; 
            color: var(--accent); 
            background: rgba(255, 62, 0, 0.05); 
            border: 1px solid rgba(255, 62, 0, 0.1);
            border-radius: 16px; 
            display: none;
            animation: fadeIn 0.4s ease;
        }
        
        @keyframes fadeIn {
            from { opacity: 0; transform: translateY(-10px); }
            to { opacity: 1; transform: translateY(0); }
        }

        ::-webkit-scrollbar { width: 8px; }
        ::-webkit-scrollbar-track { background: #000; }
        ::-webkit-scrollbar-thumb { background: #222; border-radius: 4px; }
        ::-webkit-scrollbar-thumb:hover { background: #333; }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>IPTV LIBRARY</h1>
            <p class="subtitle">Secure Native Bridge | 900+ Premium Channels</p>
        </header>

        <div class="search-container">
            <input type="text" id="searchInput" class="search-box" placeholder="Search by name or category...">
        </div>
        
        <div id="status"></div>
        <div id="grid" class="grid"></div>
    </div>

    <script>
        const db = ${JSON_DB};
        console.log("DB Loaded with channels: ", db.channels ? db.channels.length : 0);
        const channels = db.channels || [];
        const grid = document.getElementById('grid');
        const searchInput = document.getElementById('searchInput');
        const statusEl = document.getElementById('status');

        function renderChannels(list) {
            grid.innerHTML = '';
            list.forEach(channel => {
                const card = document.createElement('div');
                card.className = 'card';
                card.innerHTML = \`
                    <h3>\${channel.name}</h3>
                    <p>\${channel.category || 'Live TV'}</p>
                \`;
                card.onclick = () => generateM3U(channel.name, channel.source);
                grid.appendChild(card);
            });
        }

        searchInput.addEventListener('input', (e) => {
            const term = e.target.value.toLowerCase();
            const filtered = channels.filter(c => c.name.toLowerCase().includes(term) || (c.category && c.category.toLowerCase().includes(term)));
            renderChannels(filtered);
        });

        function generateM3U(name, source) {
            statusEl.style.display = 'block';
            statusEl.style.color = 'var(--accent)';
            statusEl.style.background = 'rgba(255, 62, 0, 0.05)';
            statusEl.style.borderColor = 'rgba(255, 62, 0, 0.1)';
            
            statusEl.innerText = "Extracting stream: " + name + "...";
            
            fetch('http://127.0.0.1:${BRIDGE_PORT}/api/start', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ url: source })
            })
            .then(res => res.json())
            .then(data => {
                if (data.error) {
                    statusEl.innerText = "Error: " + data.error;
                    statusEl.style.color = '#ff4444';
                    statusEl.style.background = 'rgba(255, 68, 68, 0.05)';
                    statusEl.style.borderColor = 'rgba(255, 68, 68, 0.1)';
                } else {
                    statusEl.innerText = "Stream captured! Syncing with VLC...";
                    statusEl.style.color = '#00ff88';
                    statusEl.style.background = 'rgba(0, 255, 136, 0.05)';
                    statusEl.style.borderColor = 'rgba(0, 255, 136, 0.1)';
                    setTimeout(() => {
                        statusEl.style.display = 'none';
                    }, 5000);
                }
            })
            .catch(err => {
                statusEl.innerText = "Error contacting bridge. Please ensure start.sh is active.";
                statusEl.style.color = '#ff4444';
                statusEl.style.background = 'rgba(255, 68, 68, 0.05)';
                statusEl.style.borderColor = 'rgba(255, 68, 68, 0.1)';
            });
        }

        // Render all channels on page load
        renderChannels(channels);
    </script>
</body>
</html>
UI_EOF

# 4. Open the UI in the native default browser
echo -e "${GREEN}[*] Launching User Interface in your default browser...${NC}"

if [ "$OS_SYS" == "Mac" ]; then
    open "iptv-ui.html"
elif [ "$OS_SYS" == "Windows" ]; then
    start "iptv-ui.html" || cmd.exe /c start "iptv-ui.html"
elif [ "$OS_SYS" == "Linux" ]; then
    xdg-open "iptv-ui.html"
else
    echo -e "${YELLOW}[Warning] Could not detect OS launcher. Please manually open 'iptv-ui.html' in your browser.${NC}"
fi

echo -e "${YELLOW}=================================================================${NC}"
echo -e "Search and click any channel in the browser."
echo -e "${YELLOW}=================================================================${NC}"

if [ "$USE_BRIDGE" = true ]; then
    echo -e "${RED}[!] KEEP THIS TERMINAL OPEN. Local Node.js HLS Bridge is running...${NC}"
    echo -e "${RED}[!] Press Ctrl+C to close the bridge when you are done watching TV.${NC}"
    wait $BRIDGE_PID
fi
