const GITHUB_REPO = "altansaid/QDock";

function setReleaseFallback() {
  const link = document.getElementById("download-link");
  const version = document.getElementById("release-version");
  link.href = `https://github.com/${GITHUB_REPO}/releases/latest`;
  version.textContent = "latest";
}

function updateDownloadFromRelease(release) {
  const link = document.getElementById("download-link");
  const version = document.getElementById("release-version");
  const assets = Array.isArray(release.assets) ? release.assets : [];
  const dmgAsset = assets.find((asset) =>
    String(asset.name || "").toLowerCase().endsWith(".dmg")
  );

  if (dmgAsset && dmgAsset.browser_download_url) {
    link.href = dmgAsset.browser_download_url;
    link.textContent = `Download ${release.tag_name} DMG`;
  } else {
    link.href = release.html_url || `https://github.com/${GITHUB_REPO}/releases/latest`;
  }

  version.textContent = release.tag_name || "latest";
}

async function loadLatestRelease() {
  try {
    const response = await fetch(`https://api.github.com/repos/${GITHUB_REPO}/releases?per_page=20`, {
      headers: {
        Accept: "application/vnd.github+json"
      }
    });

    if (!response.ok) {
      throw new Error(`GitHub API error: ${response.status}`);
    }

    const releases = await response.json();
    const stable = releases.find((release) => !release.draft && !release.prerelease);
    if (!stable) {
      setReleaseFallback();
      return;
    }

    updateDownloadFromRelease(stable);
  } catch (_error) {
    setReleaseFallback();
  }
}

async function copyTextFromTarget(targetId, button) {
  const element = document.getElementById(targetId);
  if (!element) return;

  const text = element.textContent.trim();
  if (!text) return;

  await navigator.clipboard.writeText(text);
  const original = button.textContent;
  button.textContent = "Copied";
  setTimeout(() => {
    button.textContent = original;
  }, 1400);
}

function setupCopyButtons() {
  const buttons = document.querySelectorAll(".copy-btn");
  for (const button of buttons) {
    button.addEventListener("click", async () => {
      const targetId = button.getAttribute("data-copy-target");
      if (!targetId) return;
      try {
        await copyTextFromTarget(targetId, button);
      } catch (_error) {
        button.textContent = "Failed";
        setTimeout(() => {
          button.textContent = "Copy";
        }, 1400);
      }
    });
  }
}

setupCopyButtons();
loadLatestRelease();
