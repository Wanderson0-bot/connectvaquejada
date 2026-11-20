const { readFileSync } = require("node:fs");
const net = require("node:net");
const path = require("node:path");
const { app, BrowserWindow, Menu, dialog, shell, utilityProcess } = require("electron");

let server;
let window;
let closing = false;
const smokeTest = process.argv.includes("--smoke-test");

function showError() {
  if (closing) return;
  if (smokeTest) {
    server?.kill();
    app.exit(1);
    return;
  }
  dialog.showErrorBox("Connect Vaquejada", "Não foi possível iniciar o aplicativo. Feche e abra novamente.");
  app.quit();
}

function availablePort() {
  return new Promise((resolve, reject) => {
    const socket = net.createServer();
    socket.once("error", reject);
    socket.listen(0, "127.0.0.1", () => {
      const { port } = socket.address();
      socket.close((error) => error ? reject(error) : resolve(port));
    });
  });
}

async function startServer(directory, settings) {
  const port = await availablePort();
  server = utilityProcess.fork(path.join(directory, "server.js"), [], {
    cwd: directory,
    env: { ...process.env, ...settings, NODE_ENV: "production", HOSTNAME: "127.0.0.1", PORT: String(port) },
    stdio: "pipe",
  });

  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("Servidor indisponível")), 30000);
    server.once("exit", () => {
      clearTimeout(timeout);
      reject(new Error("Servidor encerrado"));
      if (window) showError();
    });
    let output = "";
    server.stdout.on("data", (chunk) => {
      output = (output + chunk).slice(-4096);
      if (output.includes("Ready in")) {
        clearTimeout(timeout);
        resolve(`http://127.0.0.1:${port}`);
      }
    });
    server.stderr.resume();
  });
}

async function openApp() {
  const directory = path.join(process.resourcesPath, "server");
  const settings = JSON.parse(readFileSync(path.join(directory, "desktop-settings.json"), "utf8"));
  const origin = await startServer(directory, settings);
  if (smokeTest) {
    const pages = [["/", "Entre na sua conta"], ["/ativar", "Autorizar dispositivo"]];
    for (const [route, title] of pages) {
      const response = await fetch(origin + route, { signal: AbortSignal.timeout(15000) });
      if (!response.ok || !(await response.text()).includes(title)) throw new Error(`Página indisponível: ${route}`);
    }
    app.quit();
    return;
  }
  const activationOrigin = settings.DEVICE_ACTIVATION_ORIGIN
    ? new URL(settings.DEVICE_ACTIVATION_ORIGIN).origin
    : null;
  Menu.setApplicationMenu(null);
  window = new BrowserWindow({
    title: "Connect Vaquejada",
    width: 1280,
    height: 860,
    minWidth: 640,
    minHeight: 540,
    webPreferences: { nodeIntegration: false, contextIsolation: true, sandbox: true },
  });
  window.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
  window.webContents.on("will-navigate", (event, url) => {
    const target = new URL(url);
    if (target.origin === origin) return;
    event.preventDefault();
    if (target.origin === activationOrigin && target.pathname === "/ativar") {
      void shell.openExternal(url).catch(() => {});
    }
  });
  window.webContents.on("will-redirect", (event, url) => {
    if (new URL(url).origin !== origin) event.preventDefault();
  });
  await window.loadURL(origin);
}

if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.setAppUserModelId("br.connectvaquejada.desktop");
  app.on("second-instance", () => {
    if (window?.isMinimized()) window.restore();
    window?.focus();
  });
  app.on("before-quit", () => {
    closing = true;
    server?.kill();
  });
  app.on("window-all-closed", () => app.quit());
  app.whenReady().then(openApp).catch(showError);
}
