// analytics.js

// 1) Compute turn angles & longitudinal acceleration
default function computeAnalytics(points, speedData) {
  const angleDegs = Array(points.length).fill(0);
  const accelData = [0];

  for (let i = 1; i < points.length - 1; i++) {
    const p0 = points[i - 1], p1 = points[i], p2 = points[i + 1];
    const v1 = { x: p1.lng - p0.lng, y: p1.lat - p0.lat };
    const v2 = { x: p2.lng - p1.lng, y: p2.lat - p1.lat };
    const dot = v1.x * v2.x + v1.y * v2.y;
    const m1 = Math.hypot(v1.x, v1.y), m2 = Math.hypot(v2.x, v2.y);
    if (m1 && m2) {
      const cosA = Math.min(1, Math.max(-1, dot / (m1 * m2)));
      angleDegs[i] = Math.acos(cosA) * 180 / Math.PI;
    }
  }

  for (let i = 1; i < speedData.length; i++) {
    const dt = (points[i].time - points[i - 1].time) / 1000;
    const dv = speedData[i] - speedData[i - 1];
    accelData[i] = dt ? (dv / dt) * (1000 / 3600) : 0;
  }

  return { angleDegs, accelData };
}

// 2) Render elevation vs speed chart (setupChart)
function setupChart() {
  const ctx = document.getElementById('elevationChart').getContext('2d');
  if (window.elevationChart) window.elevationChart.destroy();
  window.elevationChart = new Chart(ctx, {
    type: 'line',
    data: {
      datasets: [] // will be populated in loadGPX
    },
    options: {
      responsive: true,
      animation: false,
      interaction: { mode: 'nearest', intersect: false, axis: 'x' },
      scales: {
        x: { title: { display: true, text: 'Distance (km)' } },
        y: { title: { display: true, text: 'Elevation / Speed' } }
      }
    }
  });
}

// 3) Render speed filter UI (renderSpeedFilter)
function renderSpeedFilter(speedBins) {
  const container = document.getElementById('speed-bins');
  container.innerHTML = '';
  speedBins.forEach((bin, i) => {
    const btn = document.createElement('button');
    btn.textContent = bin.label;
    btn.dataset.index = i;
    btn.addEventListener('click', () => {
      // toggle logic
    });
    container.appendChild(btn);
  });
}

// 4) Render corner vs speed
function renderCornerChart(angleDegs, speedData) {
  // unchanged from previous version
}

// 5) Render accel chart
function renderAccelChart(accelData, cumulativeDistance, speedData, selectedBins, speedBins) {
  // unchanged
}

// 6) Entry point
function initAnalytics(points, speedData, cumulativeDistance) {
  const { angleDegs, accelData } = computeAnalytics(points, speedData);
  renderCornerChart(angleDegs, speedData);
  renderAccelChart(accelData, cumulativeDistance, speedData, [], []);
}

// 7) Expose globals
window.computeAnalytics = computeAnalytics;
window.setupChart = setupChart;
window.renderSpeedFilter = renderSpeedFilter;
window.initAnalytics = initAnalytics;
