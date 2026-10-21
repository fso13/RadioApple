(() => {
  "use strict";

  const repo = window.RADIO_MAC_REPO || "fso13/RadioApple";
  const releasesUrl = `https://github.com/${repo}/releases`;
  const latestApi = `https://api.github.com/repos/${repo}/releases/latest`;

  const all = (selector) => Array.from(document.querySelectorAll(selector));
  const setText = (selector, text) => all(selector).forEach((node) => { node.textContent = text; });
  const setHref = (selector, href) => all(selector).forEach((node) => { node.href = href; });

  all("[data-repo-link]").forEach((node) => { node.href = `https://github.com/${repo}`; });
  all("[data-releases-link]").forEach((node) => { node.href = releasesUrl; });

  const year = document.querySelector("[data-year]");
  if (year) year.textContent = String(new Date().getFullYear());

  const formatSize = (bytes) => {
    const mb = bytes / (1024 * 1024);
    return `${mb.toFixed(mb < 10 ? 1 : 0).replace(".", ",")} МБ`;
  };

  async function loadLatestRelease() {
    try {
      const response = await fetch(latestApi, {
        headers: { Accept: "application/vnd.github+json" }
      });
      if (!response.ok) throw new Error(`GitHub API ${response.status}`);

      const release = await response.json();
      const tag = release.tag_name || "";
      const version = tag.replace(/^v/, "");
      const assets = Array.isArray(release.assets) ? release.assets : [];
      const asset = (suffix) => assets.find((item) => item.name.endsWith(suffix));

      const dmg = asset(".dmg");
      const pkg = asset(".pkg");
      const sums = asset("SHA256SUMS.txt");
      const sbom = asset(".spdx.json");

      if (tag) {
        setText("[data-version]", tag);
        setText("[data-version-plain]", version);
      }
      if (dmg) {
        setHref("[data-download]", dmg.browser_download_url);
        setText("[data-size]", formatSize(dmg.size));
      }
      if (pkg) setHref("[data-download-pkg]", pkg.browser_download_url);
      if (sums) setHref("[data-checksums]", sums.browser_download_url);
      if (sbom) setHref("[data-sbom]", sbom.browser_download_url);

      if (release.published_at) {
        const date = new Date(release.published_at);
        if (!Number.isNaN(date.getTime())) {
          setText(
            "[data-release-date]",
            date.toLocaleDateString("ru-RU", { day: "numeric", month: "long", year: "numeric" })
          );
        }
      }

      document.documentElement.dataset.release = tag;
    } catch (error) {
      // The static fallbacks already point at /releases/latest.
      document.documentElement.dataset.release = "unavailable";
    }
  }

  loadLatestRelease();
})();
