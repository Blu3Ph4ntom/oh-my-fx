(() => {
  const tabs = Array.from(document.querySelectorAll(".tab"));
  const panels = Array.from(document.querySelectorAll(".install"));
  const copyBtn = document.querySelector("[data-copy]");

  function activePanel() {
    return panels.find((p) => p.classList.contains("is-visible")) || panels[0];
  }

  function setTab(name) {
    tabs.forEach((tab) => {
      const on = tab.dataset.tab === name;
      tab.classList.toggle("is-active", on);
      tab.setAttribute("aria-selected", on ? "true" : "false");
    });
    panels.forEach((panel) => {
      const on = panel.dataset.panel === name;
      panel.classList.toggle("is-visible", on);
      panel.hidden = !on;
    });
  }

  // Default to Windows when the visitor is on Windows.
  const preferWin = /Windows/i.test(navigator.userAgent || "");
  setTab(preferWin ? "win" : "unix");

  tabs.forEach((tab) => {
    tab.addEventListener("click", () => setTab(tab.dataset.tab));
  });

  if (copyBtn) {
    copyBtn.addEventListener("click", async () => {
      const panel = activePanel();
      const text = panel ? panel.textContent.trim() : "";
      try {
        await navigator.clipboard.writeText(text);
        copyBtn.textContent = "Copied";
        setTimeout(() => {
          copyBtn.textContent = "Copy";
        }, 1200);
      } catch {
        copyBtn.textContent = "Select + copy";
      }
    });
  }
})();
