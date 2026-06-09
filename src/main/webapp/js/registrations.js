/* ===========================================================================
   registrations.js — fetches /api/registrations, renders table,
                       filter by workshop, CSV export
   =========================================================================== */

(function () {
  const tbody       = document.getElementById("reg-tbody");
  const statTotal   = document.getElementById("stat-total");
  const filterSelect= document.getElementById("filter-workshop");
  const btnRefresh  = document.getElementById("btn-refresh");
  const btnCsv      = document.getElementById("btn-csv");

  let allRows = [];      // last full result set from server
  let viewRows = [];     // after client-side filtering

  // ───── Fetch and render ───────────────────────────────────────────────
  async function load() {
    setLoading();
    try {
      const res  = await fetch("api/registrations");
      const data = await res.json();
      if (!res.ok || data.status !== "ok") {
        setError(data.message || "Failed to load registrations.");
        return;
      }
      allRows = data.registrations || [];
      applyFilter();
    } catch (err) {
      setError("Network error — please try again.");
    }
  }

  function applyFilter() {
    const f = filterSelect.value.trim();
    viewRows = f
      ? allRows.filter(r => (r.workshop || "") === f)
      : allRows.slice();
    render();
  }

  function render() {
    statTotal.textContent = viewRows.length;

    if (viewRows.length === 0) {
      tbody.innerHTML = `
        <tr class="reg-state-row">
          <td colspan="5">No registrations${filterSelect.value ? " for this workshop" : ""} yet.</td>
        </tr>`;
      return;
    }

    tbody.innerHTML = viewRows.map((r, idx) => `
      <tr>
        <td class="col-num">${idx + 1}</td>
        <td>${esc(r.studentName)}</td>
        <td><code>${esc(r.studentNo)}</code></td>
        <td>${workshopBadge(r.workshop)}</td>
        <td class="col-time">${formatDate(r.registeredAt)}</td>
      </tr>
    `).join("");
  }

  function setLoading() {
    tbody.innerHTML = `<tr class="reg-state-row"><td colspan="5">Loading…</td></tr>`;
    statTotal.textContent = "—";
  }
  function setError(msg) {
    tbody.innerHTML = `<tr class="reg-state-row reg-error"><td colspan="5">⚠ ${esc(msg)}</td></tr>`;
    statTotal.textContent = "—";
  }

  // ───── Helpers ───────────────────────────────────────────────────────
  function esc(s) {
    return (s == null ? "" : String(s))
      .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;").replace(/'/g, "&#39;");
  }

  function workshopBadge(name) {
    if (!name) return `<span class="reg-badge reg-badge-grey">—</span>`;
    const isK8s = /kubernetes/i.test(name);
    const cls   = isK8s ? "reg-badge-blue" : "reg-badge-teal";
    return `<span class="reg-badge ${cls}">${esc(name)}</span>`;
  }

  function formatDate(iso) {
    if (!iso) return "—";
    try {
      const d = new Date(iso);
      return d.toLocaleString("en-GB", {
        day: "2-digit", month: "short", year: "numeric",
        hour: "2-digit", minute: "2-digit", hour12: false,
      });
    } catch { return iso; }
  }

  // ───── CSV download ──────────────────────────────────────────────────
  function downloadCsv() {
    if (viewRows.length === 0) {
      alert("Nothing to export.");
      return;
    }
    const headers = ["#", "Student Name", "Student No", "Workshop", "Registered At"];
    const lines = [headers.map(csvCell).join(",")];
    viewRows.forEach((r, i) => {
      lines.push([
        i + 1,
        r.studentName,
        r.studentNo,
        r.workshop || "",
        formatDate(r.registeredAt),
      ].map(csvCell).join(","));
    });
    const csv  = "\uFEFF" + lines.join("\r\n");   // BOM for Excel UTF-8
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
    const url  = URL.createObjectURL(blob);
    const a    = document.createElement("a");
    const stamp= new Date().toISOString().replace(/[:T]/g, "-").slice(0, 16);
    a.href = url;
    a.download = `registrations-${stamp}.csv`;
    document.body.appendChild(a); a.click(); document.body.removeChild(a);
    URL.revokeObjectURL(url);
  }
  function csvCell(v) {
    const s = v == null ? "" : String(v);
    return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  }

  // ───── Wire up ───────────────────────────────────────────────────────
  filterSelect.addEventListener("change", applyFilter);
  btnRefresh.addEventListener("click", load);
  btnCsv.addEventListener("click", downloadCsv);

  load();
})();
