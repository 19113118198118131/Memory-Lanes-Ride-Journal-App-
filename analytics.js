// analytics.js

// 1) Compute turn angles & acceleration
type ChartModule = typeof Chart;
export function computeAnalytics(points, speedData) {
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

// 2) Render corner vs speed scatter
export function renderCornerChart(angleDegs, speedData) {
  const cornerThreshold = 20;
  const cornerPts = [], straightPts = [];
  angleDegs.forEach((ang, i) => {
    if (i === 0) return;
    const pt = { x: ang, y: speedData[i], idx: i };
    (ang > cornerThreshold ? cornerPts : straightPts).push(pt);
  });

  const ctx = document.getElementById('cornerChart').getContext('2d');
  window.cornerChart = new Chart(ctx, {
    type: 'scatter',
    data: {
      datasets: [
        { label: 'Corners', data: cornerPts },
        { label: 'Straights', data: straightPts }
      ]
    },
    options: {
      interaction: { mode: 'nearest', axis: 'xy', intersect: true },
      scales: {
        x: { title: { display: true, text: 'Turn Angle (°)' } },
        y: { title: { display: true, text: 'Speed (km/h)' } }
      },
      onClick(evt, elements) {
        if (!elements.length) return;
        const idx = elements[0].index;
        if (window.updatePlayback) window.updatePlayback(idx);
      }
    }
  });
}

// 3) Smoothing helper
export function smoothArray(data, windowSize = 15) {
  const smoothed = [];
  for (let i = 0; i < data.length; i++) {
    const start = Math.max(0, i - Math.floor(windowSize / 2));
    const end = Math.min(data.length, i + Math.ceil(windowSize / 2));
    const chunk = data.slice(start, end);
    smoothed.push(chunk.reduce((a, b) => a + b, 0) / chunk.length);
  }
  return smoothed;
}

// 4) Render acceleration chart
export function renderAccelChart(accelData, cumulativeDistance, speedData, selectedBins = [], speedBins = []) {
  const labels = cumulativeDistance.map(d => (d / 1000).toFixed(2));
  const smoothAccel = smoothArray(accelData);
  const dataWithIdx = smoothAccel.map((a, i) => ({ x: cumulativeDistance[i]/1000, y: a, idx: i }));

  const ctx = document.getElementById('accelChart').getContext('2d');
  if (window.accelChart) window.accelChart.destroy();
  window.accelChart = new Chart(ctx, {
    type: 'line',
    data: { labels, datasets: [{ label: 'Accel', data: dataWithIdx }] },
    options: {
      interaction: { mode: 'nearest', axis: 'xy', intersect: true },
      scales: {
        x: { title: { display: true, text: 'Distance (km)' } },
        y: { title: { display: true, text: 'Acceleration (m/s²)' } }
      },
      onClick(evt, elements) {
        if (!elements.length) return;
        const idx = elements[0].index;
        if (window.updatePlayback) window.updatePlayback(idx);
      }
    }
  });
}

// 5) Chart setup and filter UI
export function setupChart() {
  // Reinitialize elevation/speed chart or other shared charts
}

export function renderSpeedFilter() {
  // Reproduce speed filter buttons behavior
}

// 6) Expose globally
window.computeAnalytics   = computeAnalytics;
window.renderCornerChart  = renderCornerChart;
window.renderAccelChart   = renderAccelChart;
window.smoothArray        = smoothArray;
window.setupChart         = setupChart;
window.renderSpeedFilter  = renderSpeedFilter;
