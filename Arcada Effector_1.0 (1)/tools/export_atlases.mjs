// Batch asset export through Arcaidia's real Engine + Atlas, using an isolated
// local headless Canvas host. No editor UI/workspace state, npm or remote services.
// node tools/export_atlases.mjs --out <existing directory> library/Effect.json [...]
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import net from 'node:net';
import os from 'node:os';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const outIndex = args.indexOf('--out');
if (outIndex < 0 || !args[outIndex + 1]) throw new Error('Pass --out <existing directory>.');
const output = path.resolve(args.splice(outIndex, 2)[1]);
if (!fs.statSync(output).isDirectory()) throw new Error('Output directory must exist.');
if (!args.length) throw new Error('Pass at least one effect document.');
const TEMP = process.env.AFX_TEMP || path.join(os.tmpdir(), 'opencode');
if (!fs.statSync(TEMP).isDirectory()) throw new Error('AFX_TEMP must be an existing temporary directory.');
const browserPath = process.env.AFX_BROWSER || 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const profile = fs.mkdtempSync(path.join(TEMP, 'arcada-export-'));
const modules = ['utils', 'i18n', 'track', 'curve', 'path', 'sprites', 'model', 'sim', 'engine', 'atlas'];
const page = '<!doctype html><meta charset="utf-8"><title>Arcaidia batch export</title>' +
    modules.map(name => `<script src="/js/core/${name}.js"></script>`).join('');
const server = http.createServer((req, res) => {
    const name = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
    if (name === '/') { res.writeHead(200, { 'Content-Type': 'text/html' }); res.end(page); return; }
    const filename = path.resolve(ROOT, '.' + name);
    if (!filename.startsWith(ROOT + path.sep) || !fs.existsSync(filename)) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { 'Content-Type': filename.endsWith('.js') ? 'text/javascript' : 'application/json' });
    fs.createReadStream(filename).pipe(res);
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const base = `http://127.0.0.1:${server.address().port}`;
const portProbe = net.createServer();
await new Promise(resolve => portProbe.listen(0, '127.0.0.1', resolve));
const debugPort = portProbe.address().port;
await new Promise(resolve => portProbe.close(resolve));
const browser = spawn(browserPath, ['--headless=new', '--disable-gpu', '--no-sandbox',
    '--disable-background-networking', '--disable-component-update', '--disable-sync',
    '--disable-extensions', '--no-first-run', '--no-default-browser-check',
    '--host-resolver-rules=MAP * 0.0.0.0, EXCLUDE 127.0.0.1, EXCLUDE localhost',
    `--remote-debugging-port=${debugPort}`, `--user-data-dir=${profile}`, base], { stdio: 'ignore' });
let socket;
let sequence = 0;
const waiting = new Map();
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
function send(method, params = {}) {
    const id = ++sequence;
    return new Promise((resolve, reject) => {
        const timer = setTimeout(() => { waiting.delete(id); reject(new Error(method + ' timed out')); }, 110000);
        waiting.set(id, { resolve, reject, timer });
        socket.send(JSON.stringify({ id, method, params }));
    });
}
async function evaluate(expression) {
    const response = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true });
    if (response.exceptionDetails) throw new Error(response.exceptionDetails.exception?.description || response.exceptionDetails.text);
    return response.result.value;
}
try {
    let target;
    for (let attempt = 0; attempt < 100; attempt++) {
        try { target = (await (await fetch(`http://127.0.0.1:${debugPort}/json/list`)).json()).find(t => t.type === 'page'); } catch {}
        if (target) break;
        await pause(100);
    }
    if (!target) throw new Error('Headless Canvas host did not start.');
    socket = new WebSocket(target.webSocketDebuggerUrl);
    await new Promise((resolve, reject) => { socket.addEventListener('open', resolve, { once: true }); socket.addEventListener('error', reject, { once: true }); });
    socket.addEventListener('message', event => {
        const message = JSON.parse(event.data);
        const pending = waiting.get(message.id);
        if (!pending) return;
        waiting.delete(message.id); clearTimeout(pending.timer);
        message.error ? pending.reject(new Error(JSON.stringify(message.error))) : pending.resolve(message.result);
    });
    await send('Page.navigate', { url: base });
    let loaded = false;
    for (let attempt = 0; attempt < 100; attempt++) {
        loaded = await evaluate('typeof AFX !== "undefined" && !!AFX.Engine && !!AFX.Atlas');
        if (loaded) break;
        await pause(100);
    }
    if (!loaded) throw new Error('Arcaidia core modules did not load.');
    for (const input of args) {
        const filename = path.resolve(input);
        if (!filename.startsWith(ROOT + path.sep)) throw new Error('Effect document must be inside the editor directory.');
        const relative = path.relative(ROOT, filename).split(path.sep).map(encodeURIComponent).join('/');
        const result = await evaluate(`(async () => {
            const payload = await (await fetch(${JSON.stringify('/' + relative)})).json();
            const doc = AFX.Model.migrate(payload.doc || payload);
            const check = [];
            const time = AFX.Atlas.frameTimes(doc).times[0];
            for (let i = 0; i < 2; i++) {
                const c = document.createElement('canvas'); c.width = doc.comp.w; c.height = doc.comp.h;
                const ctx = c.getContext('2d', { willReadFrequently: true });
                new AFX.Engine().render(doc, time, ctx);
                check.push(ctx.getImageData(0, 0, c.width, c.height).data);
            }
            if (!check[0].every((value, i) => value === check[1][i])) throw new Error('Non-deterministic effect render');
            const built = AFX.Atlas.build(doc);
            // Production cell-edge conditioning (the CBO game pipeline uses this
            // after editor export too): avoid neighbouring frames bleeding under
            // bilinear filtering. The original document/core render is untouched.
            const pixels = built.canvas.getContext('2d').getImageData(0, 0, built.canvas.width, built.canvas.height);
            for (let y = 0; y < pixels.height; y++) for (let x = 0; x < pixels.width; x++) {
                const cx = x % built.info.frameWidth, cy = y % built.info.frameHeight;
                const edge = Math.min(cx, cy, built.info.frameWidth - 1 - cx, built.info.frameHeight - 1 - cy);
                if (edge >= 3) continue;
                const t = edge / 3;
                pixels.data[(y * pixels.width + x) * 4 + 3] *= t * t * (3 - 2 * t);
            }
            built.canvas.getContext('2d').putImageData(pixels, 0, 0);
            const preview = document.createElement('canvas'); preview.width = 1080; preview.height = 230;
            const ctx = preview.getContext('2d'); ctx.fillStyle = '#241e19'; ctx.fillRect(0, 0, 1080, 230);
            ctx.fillStyle = '#dfd1ac'; ctx.font = '14px sans-serif'; ctx.fillText(doc.name, 8, 20);
            for (let i = 0; i < 6; i++) {
                const frame = Math.round(i * (built.info.frames - 1) / 5);
                const w = built.info.frameWidth, h = built.info.frameHeight;
                const zoom = Math.min(172 / w, 190 / h);
                ctx.drawImage(built.canvas, (frame % built.info.cols) * w, Math.floor(frame / built.info.cols) * h, w, h,
                    i * 180 + (180 - w * zoom) / 2, 32 + (190 - h * zoom) / 2, w * zoom, h * zoom);
            }
            return { name: doc.name, info: built.info, deterministic: true,
                png: built.canvas.toDataURL('image/png'), preview: preview.toDataURL('image/jpeg', 0.86) };
        })()`);
        const slug = result.name.replace(/^CBO /, '').toLowerCase().replace(/[^a-z0-9]+/g, '_');
        const png = Buffer.from(result.png.split(',')[1], 'base64');
        fs.writeFileSync(path.join(output, slug + '.png'), png);
        fs.writeFileSync(path.join(TEMP, slug + '_arcada_preview.jpg'), Buffer.from(result.preview.split(',')[1], 'base64'));
        fs.writeFileSync(path.join(TEMP, slug + '_atlas_info.json'), JSON.stringify(result.info, null, 2));
        console.log(`${slug}: ${png.length} bytes, ${JSON.stringify(result.info)}, deterministic render verified`);
    }
} finally {
    if (socket?.readyState === WebSocket.OPEN) {
        try { await send('Browser.close'); } catch {}
        socket.close();
    }
    browser.kill();
    server.closeAllConnections(); server.close();
    for (const pending of waiting.values()) { clearTimeout(pending.timer); pending.reject(new Error('Exporter closed')); }
    await pause(500);
    try { fs.rmSync(profile, { recursive: true, force: true }); } catch {}
}
