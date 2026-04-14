import cors from 'cors';
import express, { Request, Response } from 'express';
import { type Browser, chromium } from 'playwright';
import { spawn } from 'child_process';
import fs from 'fs';
import path from 'path';

const app = express();
app.use(cors());
app.use(express.json());

let PORT = 0;
let streamUrl = '';
let lastTargetUrl = ''; // For background key rotation
let refreshPromise: Promise<void> | null = null; // Prevent multi-launch storms

const streamCookies: Record<string, string> = {};
// Keys captured directly from the browser session (bypasses key server auth)
const capturedKeys: Map<string, Buffer> = new Map();

function getCookieString() {
    return Object.entries(streamCookies)
        .map(([k, v]) => `${k}=${v}`)
        .join('; ');
}

async function refreshStreamToken(targetUrl: string, isInitialLaunch: boolean = false) {
    // If a refresh is already in progress, just await it
    if (refreshPromise) return refreshPromise;

    refreshPromise = (async () => {
        console.log(`[+] ${isInitialLaunch ? 'Starting' : 'Refreshing'} HLS session for decryption keys...`);
        let browser: any | undefined;
        try {
            browser = await chromium.launch({ headless: true });
            const context = await browser.newContext();
            
            // Block heavy assets to speed up loading
            await context.route('**/*', (route: any, request: any) => {
                const type = request.resourceType();
                if (['image', 'stylesheet', 'font', 'media'].includes(type)) {
                    route.abort();
                } else {
                    route.continue();
                }
            });

            // Key interception logic using Playwright's route.fetch()
            await context.route('**/key/**', async (route: any) => {
                const response = await route.fetch();
                const body = await response.body();
                if (body.length === 16) {
                    const keyPath = new URL(route.request().url()).pathname;
                    if (!capturedKeys.has(keyPath)) {
                        capturedKeys.set(keyPath, body);
                        console.log(`[+] Captured AES key: ${keyPath} (size: ${body.length}B)`);
                    }
                }
                await route.fulfill({ response });
            });

            const page = await context.newPage();

            // M3U8 discovery
            page.on('response', (response: any) => {
                const url = response.url();
                if (url.includes('mono.css')) {
                    streamUrl = url;
                }
            });

            const navigateUrl = targetUrl.replace(
                /^https?:\/\/[^/]*daddylive[^/]*/i,
                'https://dlstreams.top'
            );
            
            await page.goto(navigateUrl, { waitUntil: 'load', timeout: 60000 });

            // Wait for M3U8 URL and first key
            for (let i = 0; i < 40; i++) {
                if (streamUrl && capturedKeys.size > 0) break;
                await new Promise((r: any) => setTimeout(r, 500));
            }

            if (streamUrl) {
                const cookies = await context.cookies([streamUrl]);
                for (const c of cookies) {
                    streamCookies[c.name] = c.value;
                }

                if (isInitialLaunch) {
                    launchVLC();
                }
            } else {
                console.error('[-] Failed to discover stream M3U8.');
            }

            await browser.close();
        } catch (e: any) {
            console.error('[-] Error during session extraction:', e.message);
            if (browser) await browser.close();
        } finally {
            refreshPromise = null;
        }
    })();

    return refreshPromise;
}

function launchVLC() {
    const vlcPath = process.env.VLC_PATH;
    if (!vlcPath) {
        console.warn('[!] VLC_PATH not set — skipping launch.');
        return;
    }

    const playlistUrl = `http://localhost:${PORT}/playlist.m3u8`;
    // PROFESSIONAL OPTIMIZATION FLAGS
    const vlcFlags = [
        '--network-caching=5000', // 5s buffer for stability
        '--clock-jitter=0',       // Better HLS sync
        '--no-video-title-show',   // Cleaner look
        '--live-caching=5000',    // Extra live buffer
        '--no-stats'               // Less console noise
    ];

    if (process.platform === 'darwin' && vlcPath.includes('.app/')) {
        const appPath = vlcPath.split('/Contents/')[0];
        console.log(`[+] Launching VLC Optimized: ${appPath}`);
        const vlc = spawn('open', [
            '-n', '-a', appPath, playlistUrl,
            '--args', ...vlcFlags
        ], { detached: true, stdio: 'ignore' });
        vlc.unref();
    } else {
        console.log(`[+] Launching VLC Optimized: ${vlcPath}`);
        const vlc = spawn(vlcPath, [playlistUrl, ...vlcFlags], { 
            detached: true, 
            stdio: ['ignore', 'ignore', 'pipe'] 
        });
        vlc.unref();
    }
}

app.post('/api/start', async (req: Request, res: Response) => {
    const { url } = req.body;
    if (!url) return res.status(400).json({ error: 'Missing url' });
    
    // Reset state for new channel
    streamUrl = '';
    lastTargetUrl = url;
    capturedKeys.clear();
    Object.keys(streamCookies).forEach((k: any) => delete streamCookies[k]);

    refreshStreamToken(url, true);
    res.json({ ok: true, message: 'Extraction started' });
});

const playlistHandler = async (_req: Request, res: Response) => {
    if (!streamUrl) return res.status(503).send('Initializing...');

    try {
        const response = await fetch(streamUrl, {
            headers: {
                Referer: 'https://dlstreams.top/',
                Cookie: getCookieString(),
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/114.0.0.0 Safari/537.36',
            },
        });
        if (!response.ok) throw new Error(`HTTP ${response.status}`);

        let m3u8Text = await response.text();
        const origin = new URL(streamUrl).origin;

        // Rewrite everything to proxy
        m3u8Text = m3u8Text.replace(/(https?:\/\/[^\s"',]+)/g, (match: any) => {
            return `http://localhost:${PORT}/proxy?url=${encodeURIComponent(match)}&ext=.ts`;
        });
        m3u8Text = m3u8Text.replace(/URI="(\/[^\"]+)"/g, (_m: any, p: any) => {
            return `URI="http://localhost:${PORT}/proxy?url=${encodeURIComponent(origin + p)}"`;
        });
        m3u8Text = m3u8Text.replace(/^(\/[^\s]+)$/gm, (_m: any, p: any) => {
            return `http://localhost:${PORT}/proxy?url=${encodeURIComponent(origin + p)}&ext=.ts`;
        });

        res.setHeader('Content-Type', 'application/vnd.apple.mpegurl');
        res.send(m3u8Text);
    } catch (e: any) {
        res.status(500).send(e.message);
    }
};

app.get('/playlist.m3u8', playlistHandler);
app.get('/api/playlist.m3u8', playlistHandler);

app.get('/proxy', async (req: Request, res: Response) => {
    const targetUrl = req.query.url as string;
    if (!targetUrl) return res.status(400).send('Missing url');

    try {
        const parsed = new URL(targetUrl);
        const isKey = parsed.pathname.toLowerCase().includes('/key/');

        if (isKey) {
            // INFINITE STREAM LOGIC: Detect missing/rotated keys
            if (!capturedKeys.has(parsed.pathname)) {
                console.log(`[!] Key MISSING for ${parsed.pathname} - Triggering Rotation Refresh...`);
                refreshStreamToken(lastTargetUrl, false);
                
                // Wait for the key to be captured (20 attempts x 500ms = 10s)
                for (let i = 0; i < 20; i++) {
                    if (capturedKeys.has(parsed.pathname)) break;
                    await new Promise(r => setTimeout(r, 500));
                }
            }

            const key = capturedKeys.get(parsed.pathname);
            if (key) {
                res.setHeader('Content-Type', 'application/octet-stream');
                return res.send(key);
            }
            console.error(`[!] Failed to capture rotated key in time: ${parsed.pathname}`);
        }

        const response = await fetch(targetUrl, {
            headers: {
                Referer: 'https://dlstreams.top/',
                Cookie: getCookieString(),
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/114.0.0.0 Safari/537.36',
            },
        });

        res.status(response.status);
        res.setHeader('Access-Control-Allow-Origin', '*');
        res.setHeader('Content-Type', isKey ? 'application/octet-stream' : 'video/MP2T');

        if (response.body) {
            // @ts-ignore
            const reader = response.body.getReader();
            while (true) {
                const { done, value } = await reader.read();
                if (done) break;
                res.write(value);
            }
            res.end();
        } else {
            res.end();
        }
    } catch (e: any) {
        console.error(`[PROXY ERROR] ${targetUrl}: ${e.message}`);
        res.status(500).send(e.message);
    }
});

const server = app.listen(0, () => {
    const address = server.address();
    PORT = typeof address === 'string' ? 0 : (address?.port || 0);
    fs.writeFileSync(path.join(__dirname, '..', '.bridge_port'), PORT.toString());
    console.log(`[+] IPTV Bridge v2 (Infinite Stream) running on :${PORT}`);
});
