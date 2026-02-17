#!/usr/bin/env node

"use strict";

const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const https = require("node:https");
const crypto = require("node:crypto");
const { promisify } = require("node:util");
const { execFile } = require("node:child_process");
const { pipeline } = require("node:stream/promises");

const execFileAsync = promisify(execFile);

const REPO = process.env.QDOCK_REPO || "altansaid/QDock";
const GITHUB_API = `https://api.github.com/repos/${REPO}`;
const GITHUB_WEB = `https://github.com/${REPO}`;

const FALLBACK_DOWNLOAD_URL = `${GITHUB_WEB}/releases/latest`;

function parseArgs(argv) {
  const opts = {
    channel: "stable",
    installDir: "/Applications",
    launch: true,
    verbose: false,
    help: false
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--help" || arg === "-h") {
      opts.help = true;
      continue;
    }
    if (arg === "--verbose") {
      opts.verbose = true;
      continue;
    }
    if (arg === "--no-launch") {
      opts.launch = false;
      continue;
    }
    if (arg === "--channel") {
      const value = argv[i + 1];
      if (!value || value.startsWith("--")) {
        throw new Error("Missing value for --channel. Expected: stable | beta");
      }
      if (value !== "stable" && value !== "beta") {
        throw new Error("Invalid --channel value. Use stable or beta.");
      }
      opts.channel = value;
      i += 1;
      continue;
    }
    if (arg === "--dir") {
      const value = argv[i + 1];
      if (!value || value.startsWith("--")) {
        throw new Error("Missing value for --dir. Example: --dir /Applications");
      }
      opts.installDir = path.resolve(value);
      i += 1;
      continue;
    }
    throw new Error(`Unknown argument: ${arg}`);
  }

  return opts;
}

function printHelp() {
  console.log(`
QDock Installer

Usage:
  npx @qdock/installer [options]

Options:
  --channel stable|beta    Release channel (default: stable)
  --dir <path>             Install directory (default: /Applications)
  --no-launch              Do not open QDock after installation
  --verbose                Enable detailed logs
  -h, --help               Show help
`);
}

function log(opts, message) {
  if (opts.verbose) {
    console.log(`[qdock-installer] ${message}`);
  }
}

function info(message) {
  console.log(`[QDock] ${message}`);
}

function warn(message) {
  console.warn(`[QDock] ${message}`);
}

function withTimeout(promise, ms, message) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(message)), ms);
  });
  return Promise.race([
    promise.finally(() => clearTimeout(timer)),
    timeout
  ]);
}

async function fetchJson(url, opts) {
  log(opts, `Fetching ${url}`);
  const response = await withTimeout(fetch(url, {
    headers: {
      "User-Agent": "qdock-installer",
      "Accept": "application/vnd.github+json"
    }
  }), 20000, "Timed out while contacting GitHub API");

  if (!response.ok) {
    throw new Error(`GitHub API request failed (${response.status})`);
  }
  return response.json();
}

async function resolveRelease(opts) {
  const releases = await fetchJson(`${GITHUB_API}/releases?per_page=30`, opts);
  if (!Array.isArray(releases) || releases.length === 0) {
    throw new Error("No releases found in repository");
  }

  const stableRelease = releases.find((r) => !r.draft && !r.prerelease);
  const betaRelease = releases.find((r) => !r.draft && r.prerelease);

  let release;
  if (opts.channel === "beta") {
    release = betaRelease || stableRelease;
  } else {
    release = stableRelease;
  }

  if (!release) {
    throw new Error(`No suitable release found for channel: ${opts.channel}`);
  }
  log(opts, `Selected release ${release.tag_name}`);
  return release;
}

function pickAssets(release) {
  const assets = Array.isArray(release.assets) ? release.assets : [];
  const dmg = assets.find((asset) => {
    const name = String(asset.name || "").toLowerCase();
    return name.endsWith(".dmg");
  });
  const checksums = assets.find((asset) => {
    const name = String(asset.name || "").toLowerCase();
    return name === "checksums.txt";
  });
  return { dmg, checksums };
}

function downloadFile(url, destination, opts) {
  return new Promise((resolve, reject) => {
    const request = https.get(url, {
      headers: {
        "User-Agent": "qdock-installer",
        "Accept": "application/octet-stream"
      }
    }, (response) => {
      if ([301, 302, 303, 307, 308].includes(response.statusCode)) {
        response.resume();
        const location = response.headers.location;
        if (!location) {
          reject(new Error("Redirected without location header"));
          return;
        }
        log(opts, `Redirected to ${location}`);
        downloadFile(location, destination, opts).then(resolve, reject);
        return;
      }

      if (response.statusCode !== 200) {
        response.resume();
        reject(new Error(`Download failed (${response.statusCode})`));
        return;
      }

      const file = fs.createWriteStream(destination);
      pipeline(response, file).then(resolve, reject);
    });

    request.on("error", reject);
    request.setTimeout(20000, () => {
      request.destroy(new Error("Download timed out"));
    });
  });
}

async function sha256File(filePath) {
  return new Promise((resolve, reject) => {
    const hash = crypto.createHash("sha256");
    const stream = fs.createReadStream(filePath);
    stream.on("error", reject);
    stream.on("data", (chunk) => hash.update(chunk));
    stream.on("end", () => resolve(hash.digest("hex")));
  });
}

async function verifyChecksum(artifactPath, checksumsAsset, opts) {
  if (!checksumsAsset) {
    throw new Error("checksums.txt asset not found. Aborting for safety.");
  }

  const checksumsPath = `${artifactPath}.checksums.txt`;
  await downloadFile(checksumsAsset.browser_download_url, checksumsPath, opts);
  const checksumsContent = fs.readFileSync(checksumsPath, "utf8");
  fs.unlinkSync(checksumsPath);

  const artifactName = path.basename(artifactPath);
  const line = checksumsContent
    .split(/\r?\n/)
    .map((l) => l.trim())
    .find((l) => l.endsWith(`  ${artifactName}`) || l.endsWith(` *${artifactName}`));

  if (!line) {
    throw new Error("No checksum entry for DMG in checksums.txt. Aborting for safety.");
  }

  const expected = line.split(/\s+/)[0].toLowerCase();
  const actual = (await sha256File(artifactPath)).toLowerCase();

  if (expected !== actual) {
    throw new Error("Checksum verification failed. Downloaded file does not match release checksum.");
  }
  info("Checksum verification passed.");
}

function parseMountPoint(attachOutput) {
  const lines = String(attachOutput || "").split(/\r?\n/);
  for (const line of lines) {
    if (!line.includes("/Volumes/")) continue;
    const parts = line.split(/\t+/).filter(Boolean);
    const maybePath = parts[parts.length - 1];
    if (maybePath && maybePath.startsWith("/Volumes/")) {
      return maybePath;
    }
  }
  return null;
}

async function attachDmg(dmgPath, opts) {
  log(opts, "Mounting DMG...");
  const { stdout } = await execFileAsync("hdiutil", ["attach", "-nobrowse", dmgPath]);
  const mountPoint = parseMountPoint(stdout);
  if (!mountPoint) {
    throw new Error("Unable to resolve mounted DMG volume path.");
  }
  log(opts, `Mounted at ${mountPoint}`);
  return mountPoint;
}

async function detachDmg(mountPoint, opts) {
  try {
    log(opts, `Detaching ${mountPoint}`);
    await execFileAsync("hdiutil", ["detach", mountPoint, "-quiet"]);
  } catch (error) {
    warn(`Could not detach DMG cleanly: ${error.message}`);
  }
}

function ensureAppPath(volumePath) {
  const directPath = path.join(volumePath, "QDock.app");
  if (fs.existsSync(directPath)) {
    return directPath;
  }
  const entries = fs.readdirSync(volumePath);
  const appName = entries.find((entry) => entry.endsWith(".app"));
  if (!appName) {
    throw new Error("No .app bundle found inside downloaded DMG.");
  }
  return path.join(volumePath, appName);
}

async function copyApp(appSource, targetAppPath, opts) {
  fs.mkdirSync(path.dirname(targetAppPath), { recursive: true });
  if (fs.existsSync(targetAppPath)) {
    log(opts, `Removing existing app at ${targetAppPath}`);
    fs.rmSync(targetAppPath, { recursive: true, force: true });
  }
  await execFileAsync("ditto", [appSource, targetAppPath]);
}

function fallbackInstallDir(currentDir) {
  if (currentDir === "/Applications") {
    return path.join(os.homedir(), "Applications");
  }
  return null;
}

async function installFromDmg(dmgPath, installDir, opts) {
  let mountPoint = null;
  try {
    mountPoint = await attachDmg(dmgPath, opts);
    const appSource = ensureAppPath(mountPoint);
    const appTarget = path.join(installDir, "QDock.app");
    await copyApp(appSource, appTarget, opts);
    return appTarget;
  } catch (error) {
    const fallbackDir = fallbackInstallDir(installDir);
    const permissionLike =
      /operation not permitted|permission denied|eacces/i.test(String(error.message || ""));

    if (!fallbackDir || !permissionLike || !mountPoint) {
      throw error;
    }

    warn(`Install to ${installDir} failed (${error.message}). Retrying in ${fallbackDir}.`);
    const appSource = ensureAppPath(mountPoint);
    const appTarget = path.join(fallbackDir, "QDock.app");
    await copyApp(appSource, appTarget, opts);
    return appTarget;
  } finally {
    if (mountPoint) {
      await detachDmg(mountPoint, opts);
    }
  }
}

async function launchApp(appPath, opts) {
  if (!opts.launch) return;
  info("Launching QDock...");
  await execFileAsync("open", [appPath]);
}

function platformGuard() {
  if (process.platform !== "darwin") {
    throw new Error("QDock installer currently supports macOS only.");
  }
}

async function main() {
  let tempDir = null;
  try {
    const opts = parseArgs(process.argv.slice(2));
    if (opts.help) {
      printHelp();
      return;
    }

    platformGuard();
    info(`Installing QDock (${opts.channel} channel)...`);

    const release = await resolveRelease(opts);
    const { dmg, checksums } = pickAssets(release);
    if (!dmg) {
      throw new Error("No DMG asset found in selected release.");
    }

    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "qdock-installer-"));
    const artifactPath = path.join(tempDir, dmg.name || "QDock.dmg");

    info(`Downloading ${dmg.name}...`);
    await downloadFile(dmg.browser_download_url, artifactPath, opts);
    await verifyChecksum(artifactPath, checksums, opts);

    const installedPath = await installFromDmg(artifactPath, opts.installDir, opts);
    info(`Installed to ${installedPath}`);

    await launchApp(installedPath, opts);
    info("Done.");
  } catch (error) {
    console.error(`[QDock] Installation failed: ${error.message}`);
    console.error(`[QDock] You can download manually from: ${FALLBACK_DOWNLOAD_URL}`);
    process.exitCode = 1;
  } finally {
    if (tempDir && fs.existsSync(tempDir)) {
      fs.rmSync(tempDir, { recursive: true, force: true });
    }
  }
}

main();
