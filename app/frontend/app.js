const API_BASE = window.CLOUDFORGE_API_BASE || "";

const backendEl = document.getElementById("backend-status");
const databaseEl = document.getElementById("database-status");

async function refreshStatus() {
  backendEl.textContent = "checking…";
  databaseEl.textContent = "checking…";
  backendEl.className = "";
  databaseEl.className = "";

  try {
    const res = await fetch(`${API_BASE}/api/status`);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();

    backendEl.textContent = data.backend === "ok" ? "OK" : "ERROR";
    backendEl.className = data.backend === "ok" ? "ok" : "error";

    databaseEl.textContent = data.database;
    databaseEl.className = data.database === "connected" ? "ok" : "error";
  } catch (err) {
    backendEl.textContent = "UNREACHABLE";
    backendEl.className = "error";
    databaseEl.textContent = "unknown";
    databaseEl.className = "error";
  }
}

document.getElementById("refresh").addEventListener("click", refreshStatus);
refreshStatus();
