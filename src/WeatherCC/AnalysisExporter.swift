// meta: created=2026-02-22 updated=2026-02-22 checked=never
// Sandbox OFF (v0.3.2) — getpwuid hack removed, uses homeDirectoryForCurrentUser directly
import Foundation
import AppKit

enum AnalysisExporter {

    static func exportAndOpen() {
        let dir = NSTemporaryDirectory() + "WeatherCC-Analysis/"
        let htmlPath = dir + "analysis.html"
        let dataPath = dir + "data.js"

        // 1. Write empty data + HTML, open browser instantly
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try "var usageData=[];var tokenData=[];".write(toFile: dataPath, atomically: true, encoding: .utf8)
            try htmlTemplate.write(toFile: htmlPath, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(URL(fileURLWithPath: htmlPath))
        } catch {
            NSLog("[WeatherCC] AnalysisExporter error: %@", error.localizedDescription)
            return
        }

        // 2. Generate real data in background → overwrite data.js
        DispatchQueue.global(qos: .userInitiated).async {
            let history = UsageStore.loadAllHistory()
            let allRecords = TokenStore.loadAll()
            let usageJSON = usageDataJSON(from: history)
            let tokenJSON = tokenDataJSON(from: allRecords)
            let js = "var usageData = \(usageJSON);\nvar tokenData = \(tokenJSON);\n"
            try? js.write(toFile: dataPath, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - JSON Serialization

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func usageDataJSON(from history: [UsageStore.DataPoint]) -> String {
        let entries = history.map { dp -> String in
            let ts = iso.string(from: dp.timestamp)
            let fiveH = dp.fiveHourPercent.map { String($0) } ?? "null"
            let sevenD = dp.sevenDayPercent.map { String($0) } ?? "null"
            let fiveHResets = dp.fiveHourResetsAt.map { #""\#(iso.string(from: $0))""# } ?? "null"
            let sevenDResets = dp.sevenDayResetsAt.map { #""\#(iso.string(from: $0))""# } ?? "null"
            return #"{"timestamp":"\#(ts)","five_hour_percent":\#(fiveH),"seven_day_percent":\#(sevenD),"five_hour_resets_at":\#(fiveHResets),"seven_day_resets_at":\#(sevenDResets)}"#
        }
        return "[\(entries.joined(separator: ","))]"
    }

    static func tokenDataJSON(from records: [TokenRecord]) -> String {
        let entries = records.map { record -> String in
            let ts = iso.string(from: record.timestamp)
            let cost = CostEstimator.cost(for: record)
            return #"{"timestamp":"\#(ts)","costUSD":\#(cost)}"#
        }
        return "[\(entries.joined(separator: ","))]"
    }

    // MARK: - HTML Template
    // Based on src/prototype/analysis.html with fetch() replaced by inline data

    private static let htmlTemplate = #"""
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>WeatherCC — Usage Analysis</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4"></script>
<script src="https://cdn.jsdelivr.net/npm/chartjs-adapter-date-fns@3"></script>
<script src="data.js"></script>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body {
  background: #0d1117;
  color: #c9d1d9;
  font-family: -apple-system, BlinkMacSystemFont, 'SF Pro', system-ui, sans-serif;
  padding: 20px;
}
h1 {
  font-size: 20px;
  font-weight: 600;
  margin-bottom: 16px;
  color: #e6edf3;
}
h2 {
  font-size: 15px;
  font-weight: 500;
  margin-bottom: 8px;
  color: #8b949e;
}
.grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 16px;
  margin-bottom: 16px;
}
.card {
  background: #161b22;
  border: 1px solid #30363d;
  border-radius: 8px;
  padding: 16px;
}
.card.full { grid-column: 1 / -1; }
.chart-container { position: relative; width: 100%; height: 300px; }
.chart-container.tall { height: 400px; }
.stats {
  display: flex;
  gap: 24px;
  margin-bottom: 16px;
  flex-wrap: wrap;
}
.stat {
  background: #21262d;
  border-radius: 6px;
  padding: 10px 16px;
}
.stat-value {
  font-size: 22px;
  font-weight: 600;
  color: #e6edf3;
}
.stat-label {
  font-size: 11px;
  color: #8b949e;
  margin-top: 2px;
}
.heatmap-grid {
  display: grid;
  grid-template-columns: 40px repeat(24, 1fr);
  gap: 2px;
  font-size: 10px;
}
.heatmap-cell {
  aspect-ratio: 1;
  border-radius: 2px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 9px;
  color: rgba(255,255,255,0.7);
}
.heatmap-label {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  padding-right: 4px;
  color: #8b949e;
  font-size: 10px;
}
.heatmap-header {
  display: flex;
  align-items: flex-end;
  justify-content: center;
  color: #8b949e;
  font-size: 9px;
  padding-bottom: 2px;
}
.tab-bar {
  display: flex;
  gap: 0;
  margin-bottom: 16px;
  border-bottom: 1px solid #30363d;
}
.tab-btn {
  background: none;
  border: none;
  color: #8b949e;
  padding: 8px 20px;
  font-size: 13px;
  cursor: pointer;
  border-bottom: 2px solid transparent;
  transition: color 0.15s, border-color 0.15s;
}
.tab-btn:hover { color: #c9d1d9; }
.tab-btn.active {
  color: #e6edf3;
  border-bottom-color: #58a6ff;
}
.tab-content { display: none; }
.tab-content.active { display: block; }
.date-range {
  display: flex;
  gap: 12px;
  align-items: center;
  margin-bottom: 16px;
  flex-wrap: wrap;
}
.date-range label {
  color: #8b949e;
  font-size: 12px;
}
.date-range input[type="date"] {
  background: #21262d;
  border: 1px solid #30363d;
  border-radius: 4px;
  color: #c9d1d9;
  padding: 4px 8px;
  font-size: 12px;
}
.date-range button {
  background: #238636;
  border: none;
  border-radius: 4px;
  color: #fff;
  padding: 5px 14px;
  font-size: 12px;
  cursor: pointer;
}
.date-range button:hover { background: #2ea043; }
#loading {
  text-align: center;
  padding: 60px;
  color: #8b949e;
  font-size: 14px;
}
</style>
</head>
<body>
<h1>WeatherCC — Usage Analysis</h1>
<div id="loading">Loading data...</div>
<div id="app" style="display:none;">

<div class="stats" id="stats"></div>

<div class="tab-bar">
  <button class="tab-btn active" data-tab="usage">Usage</button>
  <button class="tab-btn" data-tab="cost">Cost</button>
  <button class="tab-btn" data-tab="efficiency">Efficiency</button>
  <button class="tab-btn" data-tab="cumulative">Cumulative</button>
</div>

<div class="tab-content active" id="tab-usage">
  <div class="card full">
    <h2>Usage Timeline (5h% / 7d%)</h2>
    <div class="chart-container tall"><canvas id="usageTimeline"></canvas></div>
  </div>
</div>

<div class="tab-content" id="tab-cost">
  <div class="grid">
    <div class="card full">
      <h2>Cost Timeline (per request, USD)</h2>
      <div class="chart-container tall"><canvas id="costTimeline"></canvas></div>
    </div>
    <div class="card full">
      <h2>Δ5h% vs Δ Cost</h2>
      <div class="chart-container"><canvas id="costScatter"></canvas></div>
    </div>
  </div>
</div>

<div class="tab-content" id="tab-efficiency">
  <div class="date-range">
    <label>From <input type="date" id="dateFrom"></label>
    <label>To <input type="date" id="dateTo"></label>
    <button id="applyRange">Apply</button>
  </div>
  <div class="grid">
    <div class="card">
      <h2>Efficiency (Δ5h% vs Δ Cost)</h2>
      <div class="chart-container"><canvas id="effScatter"></canvas></div>
    </div>
    <div class="card">
      <h2>KDE — Efficiency Distribution (Δ% / Δ$)</h2>
      <div class="chart-container"><canvas id="kdeChart"></canvas></div>
    </div>
    <div class="card full">
      <h2>Hourly Efficiency Heatmap (Δ% / Δ$)</h2>
      <div id="heatmap"></div>
    </div>
  </div>
</div>

<div class="tab-content" id="tab-cumulative">
  <div class="card full">
    <h2>Cumulative Cost (USD)</h2>
    <div class="chart-container tall"><canvas id="cumulativeCost"></canvas></div>
  </div>
</div>

</div>

<script>
const CHART_DEFAULTS = {
  responsive: true,
  maintainAspectRatio: false,
  plugins: {
    legend: { labels: { color: '#8b949e', font: { size: 11 } } },
  },
  scales: {
    x: {
      type: 'time',
      ticks: { color: '#484f58', font: { size: 10 } },
      grid: { color: '#21262d' },
    },
    y: {
      ticks: { color: '#484f58', font: { size: 10 } },
      grid: { color: '#21262d' },
    },
  },
};

function deepClone(obj) { return JSON.parse(JSON.stringify(obj)); }

// --- Shared state ---
let _usageData, _tokenData, _allDeltas;
const _charts = {};
const _rendered = {};

// --- Time slot config ---
const timeSlots = [
  { label: 'Night (0\u20136h)',     color: 'rgba(100,150,255,0.7)', filter: d => d.hour < 6 },
  { label: 'Morning (6\u201312h)',  color: 'rgba(255,200,80,0.7)',  filter: d => d.hour >= 6 && d.hour < 12 },
  { label: 'Afternoon (12\u201318h)', color: 'rgba(255,130,80,0.7)', filter: d => d.hour >= 12 && d.hour < 18 },
  { label: 'Evening (18\u201324h)', color: 'rgba(180,100,255,0.7)', filter: d => d.hour >= 18 },
];

// --- KDE ---
function computeKDE(values) {
  const n = values.length;
  if (n < 2) return { xs: [], ys: [] };
  const mean = values.reduce((a, b) => a + b, 0) / n;
  const variance = values.reduce((a, b) => a + (b - mean) ** 2, 0) / n;
  const std = Math.sqrt(variance) || 1;
  const h = 1.06 * std * Math.pow(n, -0.2);
  const lo = Math.min(...values) - 3 * h;
  const hi = Math.max(...values) + 3 * h;
  const step = (hi - lo) / 200;
  const xs = [], ys = [];
  const coeff = 1 / (n * h * Math.sqrt(2 * Math.PI));
  for (let x = lo; x <= hi; x += step) {
    let density = 0;
    for (const xi of values) {
      const u = (x - xi) / h;
      density += Math.exp(-0.5 * u * u);
    }
    xs.push(x);
    ys.push(density * coeff);
  }
  return { xs, ys };
}

// --- Compute deltas from usage + token data ---
function computeDeltas(usageData, tokenData) {
  const deltas = [];
  for (let i = 1; i < usageData.length; i++) {
    const prev = usageData[i - 1];
    const curr = usageData[i];
    const d5h = (curr.five_hour_percent ?? 0) - (prev.five_hour_percent ?? 0);
    const t0 = new Date(prev.timestamp).getTime();
    const t1 = new Date(curr.timestamp).getTime();
    const intervalCost = tokenData
      .filter(r => { const t = new Date(r.timestamp).getTime(); return t >= t0 && t < t1; })
      .reduce((s, r) => s + r.costUSD, 0);
    if (intervalCost > 0.001) {
      const dt = new Date(curr.timestamp);
      deltas.push({ x: intervalCost, y: d5h, hour: dt.getHours(), timestamp: curr.timestamp, date: dt });
    }
  }
  return deltas;
}

// --- Heatmap builder ---
function buildHeatmap(deltas) {
  const heatData = {};
  for (const d of deltas) {
    const dt = d.date || new Date(d.timestamp);
    const key = `${dt.getDay()}-${dt.getHours()}`;
    if (!heatData[key]) heatData[key] = { totalDelta: 0, totalCost: 0, count: 0 };
    heatData[key].totalDelta += d.y;
    heatData[key].totalCost += d.x;
    heatData[key].count++;
  }
  const dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  const ratios = [];
  for (const v of Object.values(heatData)) {
    if (v.totalCost > 0.001) ratios.push(v.totalDelta / v.totalCost);
  }
  const minR = Math.min(...ratios, 0);
  const maxR = Math.max(...ratios, 1);
  function ratioColor(ratio) {
    if (ratio === null) return '#161b22';
    const t = Math.max(0, Math.min(1, (ratio - minR) / (maxR - minR + 0.001)));
    const r = Math.round(40 + t * 180), g = Math.round(180 - t * 140), b = 40;
    return `rgba(${r},${g},${b},0.8)`;
  }
  let html = '<div class="heatmap-grid"><div></div>';
  for (let h = 0; h < 24; h++) html += `<div class="heatmap-header">${h}</div>`;
  for (let dow = 0; dow < 7; dow++) {
    html += `<div class="heatmap-label">${dayNames[dow]}</div>`;
    for (let h = 0; h < 24; h++) {
      const d = heatData[`${dow}-${h}`];
      let ratio = null, title = 'No data';
      if (d && d.totalCost > 0.001) {
        ratio = d.totalDelta / d.totalCost;
        title = `\u0394%/\u0394$: ${ratio.toFixed(1)} (n=${d.count})`;
      } else if (d) { title = `n=${d.count}, no cost data`; }
      html += `<div class="heatmap-cell" style="background:${ratioColor(ratio)}" title="${title}">${ratio !== null ? ratio.toFixed(0) : ''}</div>`;
    }
  }
  html += '</div>';
  document.getElementById('heatmap').innerHTML = html;
}

// --- Scatter chart builder (reusable for Cost tab and Efficiency tab) ---
function buildScatterChart(canvasId, deltas) {
  return new Chart(document.getElementById(canvasId), {
    type: 'scatter',
    data: {
      datasets: timeSlots.map(slot => ({
        label: slot.label,
        data: deltas.filter(slot.filter),
        backgroundColor: slot.color,
        pointRadius: 4,
      })),
    },
    options: {
      responsive: true, maintainAspectRatio: false,
      scales: {
        x: {
          type: 'linear',
          ticks: { color: '#484f58', font: { size: 10 } },
          grid: { color: '#21262d' },
          title: { display: true, text: '\u0394 Cost (USD)', color: '#484f58' },
        },
        y: {
          ticks: { color: '#484f58', font: { size: 10 } },
          grid: { color: '#21262d' },
          title: { display: true, text: '\u0394 5h%', color: '#484f58' },
        },
      },
      plugins: {
        legend: { labels: { color: '#8b949e', font: { size: 11 } } },
        tooltip: {
          callbacks: {
            label: (ctx) => {
              const d = ctx.raw;
              return `\u0394$${d.x.toFixed(3)} \u2192 \u0394${d.y.toFixed(1)}% (${d.hour}:00)`;
            },
          },
        },
      },
    },
  });
}

// --- Insert synthetic 0% points at reset boundaries ---
// When resets_at from a previous data point is before the next data point's timestamp,
// a reset occurred between them. Insert 0% at that reset time.
function insertResetPoints(data, percentKey, resetsAtKey) {
  const result = [];
  for (let i = 0; i < data.length; i++) {
    const curr = data[i];
    if (i > 0) {
      const prev = data[i - 1];
      const prevResets = prev[resetsAtKey];
      if (prevResets) {
        const resetTime = new Date(prevResets).getTime();
        const currTime = new Date(curr.timestamp).getTime();
        const prevTime = new Date(prev.timestamp).getTime();
        // Reset occurred between prev and curr
        if (resetTime > prevTime && resetTime < currTime) {
          result.push({ x: prevResets, y: 0 });
        }
      }
    }
    result.push({ x: curr.timestamp, y: curr[percentKey] });
  }
  return result;
}

// --- Tab renderers ---
function renderUsageTab() {
  const fiveHData = insertResetPoints(_usageData, 'five_hour_percent', 'five_hour_resets_at');
  const sevenDData = insertResetPoints(_usageData, 'seven_day_percent', 'seven_day_resets_at');

  _charts.usageTimeline = new Chart(document.getElementById('usageTimeline'), {
    type: 'line',
    data: {
      datasets: [
        {
          label: '5-hour %',
          data: fiveHData,
          borderColor: '#64b4ff', backgroundColor: 'rgba(100,180,255,0.1)',
          fill: true, borderWidth: 1.5, pointRadius: 1, tension: 0,
        },
        {
          label: '7-day %',
          data: sevenDData,
          borderColor: '#ff82b4', backgroundColor: 'rgba(255,130,180,0.1)',
          fill: true, borderWidth: 1.5, pointRadius: 1, tension: 0,
        },
      ],
    },
    options: {
      responsive: true, maintainAspectRatio: false,
      plugins: { legend: { labels: { color: '#8b949e', font: { size: 11 } } } },
      scales: {
        x: { type: 'time', ticks: { color: '#484f58', font: { size: 10 } }, grid: { color: '#21262d' } },
        y: { min: 0, max: 100, ticks: { color: '#484f58', font: { size: 10 } }, grid: { color: '#21262d' }, title: { display: true, text: '%', color: '#484f58' } },
      },
    },
  });
}

function renderCostTab() {
  _charts.costTimeline = new Chart(document.getElementById('costTimeline'), {
    type: 'bar',
    data: {
      datasets: [{
        label: 'Cost (USD)',
        data: _tokenData.map(d => ({ x: d.timestamp, y: d.costUSD })),
        backgroundColor: 'rgba(136,198,103,0.6)', borderColor: '#88c667',
        borderWidth: 0.5, barPercentage: 1.0, categoryPercentage: 1.0,
      }],
    },
    options: {
      responsive: true, maintainAspectRatio: false,
      plugins: { legend: { labels: { color: '#8b949e', font: { size: 11 } } } },
      scales: {
        x: { type: 'time', ticks: { color: '#484f58', font: { size: 10 } }, grid: { color: '#21262d' } },
        y: { ticks: { color: '#484f58', font: { size: 10 } }, grid: { color: '#21262d' }, title: { display: true, text: 'USD', color: '#484f58' } },
      },
    },
  });
  _charts.costScatter = buildScatterChart('costScatter', _allDeltas);
}

function renderEfficiencyTab(deltas) {
  if (_charts.effScatter) _charts.effScatter.destroy();
  if (_charts.kdeChart) _charts.kdeChart.destroy();

  _charts.effScatter = buildScatterChart('effScatter', deltas);

  // KDE
  const ratios = deltas.filter(d => d.x > 0.001).map(d => d.y / d.x);
  const { xs, ys } = computeKDE(ratios);
  if (xs.length > 0) {
    _charts.kdeChart = new Chart(document.getElementById('kdeChart'), {
      type: 'line',
      data: {
        labels: xs,
        datasets: [{
          label: 'Density',
          data: ys,
          borderColor: '#64b4ff',
          backgroundColor: 'rgba(100,180,255,0.15)',
          fill: true, borderWidth: 1.5, pointRadius: 0, tension: 0.3,
        }],
      },
      options: {
        responsive: true, maintainAspectRatio: false,
        plugins: { legend: { labels: { color: '#8b949e', font: { size: 11 } } } },
        scales: {
          x: {
            type: 'linear',
            ticks: { color: '#484f58', font: { size: 10 }, callback: v => v.toFixed(0) },
            grid: { color: '#21262d' },
            title: { display: true, text: '\u0394% / \u0394$ (ratio)', color: '#484f58' },
          },
          y: {
            ticks: { color: '#484f58', font: { size: 10 } },
            grid: { color: '#21262d' },
            title: { display: true, text: 'Density', color: '#484f58' },
          },
        },
      },
    });
  }

  buildHeatmap(deltas);
}

function renderCumulativeTab() {
  let cumCost = 0;
  const cumData = _tokenData.map(r => {
    cumCost += r.costUSD;
    return { x: r.timestamp, y: Math.round(cumCost * 100) / 100 };
  });
  _charts.cumulativeCost = new Chart(document.getElementById('cumulativeCost'), {
    type: 'line',
    data: {
      datasets: [{
        label: 'Cumulative Cost (USD)',
        data: cumData,
        borderColor: '#f0883e', backgroundColor: 'rgba(240,136,62,0.1)',
        fill: true, borderWidth: 1.5, pointRadius: 0,
      }],
    },
    options: {
      responsive: true, maintainAspectRatio: false,
      plugins: { legend: { labels: { color: '#8b949e', font: { size: 11 } } } },
      scales: {
        x: { type: 'time', ticks: { color: '#484f58', font: { size: 10 } }, grid: { color: '#21262d' } },
        y: { ticks: { color: '#484f58', font: { size: 10 } }, grid: { color: '#21262d' }, title: { display: true, text: 'USD', color: '#484f58' } },
      },
    },
  });
}

function renderTab(tabId) {
  switch (tabId) {
    case 'usage': renderUsageTab(); break;
    case 'cost': renderCostTab(); break;
    case 'efficiency':
      const filtered = getFilteredDeltas();
      renderEfficiencyTab(filtered);
      break;
    case 'cumulative': renderCumulativeTab(); break;
  }
}

// --- Date range filter ---
function getFilteredDeltas() {
  const fromVal = document.getElementById('dateFrom').value;
  const toVal = document.getElementById('dateTo').value;
  if (!fromVal || !toVal) return _allDeltas;
  const from = new Date(fromVal + 'T00:00:00');
  const to = new Date(toVal + 'T23:59:59');
  return _allDeltas.filter(d => {
    const dt = d.date || new Date(d.timestamp);
    return dt >= from && dt <= to;
  });
}

// --- Tab switching ---
function initTabs() {
  const tabs = document.querySelectorAll('.tab-btn');
  const contents = document.querySelectorAll('.tab-content');

  tabs.forEach(btn => {
    btn.addEventListener('click', () => {
      tabs.forEach(b => b.classList.remove('active'));
      contents.forEach(c => c.classList.remove('active'));
      btn.classList.add('active');
      const tabId = btn.dataset.tab;
      document.getElementById('tab-' + tabId).classList.add('active');
      if (!_rendered[tabId]) {
        renderTab(tabId);
        _rendered[tabId] = true;
      }
    });
  });

  // Date range: Apply button
  document.getElementById('applyRange').addEventListener('click', () => {
    const filtered = getFilteredDeltas();
    renderEfficiencyTab(filtered);
    _rendered['efficiency'] = true;
  });

  // Set default date range: 3 days ago to today
  const today = new Date();
  const threeDaysAgo = new Date(Date.now() - 3 * 86400000);
  document.getElementById('dateTo').value = today.toISOString().slice(0, 10);
  document.getElementById('dateFrom').value = threeDaysAgo.toISOString().slice(0, 10);
}

// --- Main ---
function main(usageData, tokenData) {
  document.getElementById('loading').textContent = 'Drawing charts...';
  document.getElementById('app').style.display = '';

  _usageData = usageData;
  _tokenData = tokenData;
  _allDeltas = computeDeltas(usageData, tokenData);

  // Stats
  const totalCost = tokenData.reduce((s, r) => s + r.costUSD, 0);
  const usageSpan = usageData.length > 1
    ? ((new Date(usageData[usageData.length-1].timestamp) - new Date(usageData[0].timestamp)) / 3600000).toFixed(1)
    : '0';
  const latestFiveH = usageData[usageData.length - 1]?.five_hour_percent ?? '-';
  const latestSevenD = usageData[usageData.length - 1]?.seven_day_percent ?? '-';

  document.getElementById('stats').innerHTML = `
    <div class="stat"><div class="stat-value">${usageData.length}</div><div class="stat-label">Usage Records</div></div>
    <div class="stat"><div class="stat-value">${tokenData.length.toLocaleString()}</div><div class="stat-label">Token Records</div></div>
    <div class="stat"><div class="stat-value">$${totalCost.toFixed(2)}</div><div class="stat-label">Total Est. Cost</div></div>
    <div class="stat"><div class="stat-value">${usageSpan}h</div><div class="stat-label">Usage Span</div></div>
    <div class="stat"><div class="stat-value">${latestFiveH}%</div><div class="stat-label">Latest 5h</div></div>
    <div class="stat"><div class="stat-value">${latestSevenD}%</div><div class="stat-label">Latest 7d</div></div>
  `;

  initTabs();

  // Render initial tab (Usage)
  renderTab('usage');
  _rendered['usage'] = true;

  document.getElementById('loading').style.display = 'none';
}

// data.js is loaded via <script src="data.js"> in <head>
if (usageData.length === 0 && tokenData.length === 0) {
  setTimeout(() => location.reload(), 500);
} else {
  try {
    document.getElementById('loading').textContent = 'Drawing charts...';
    main(usageData, tokenData);
  } catch(err) {
    document.getElementById('loading').textContent = 'Error: ' + err.message;
    console.error(err);
  }
}
</script>
</body>
</html>
"""#
}
