// analytics.js

// 1) Compute turn angles & longitudinal acceleration
function computeAnalytics(points, speedData) {
  const angleDegs = Array(points.length).fill(0);
  const accelData = [0];

  // Turn angles
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

  // Longitudinal acceleration (m/s²)
  for (let i = 1; i < speedData.length; i++) {
    const dt = (points[i].time - points[i - 1].time) / 1000;
    const dv = speedData[i] - speedData[i - 1];
    accelData[i] = dt ? (dv / dt) * (1000 / 3600) : 0;
  }

  return { angleDegs, accelData };
}

// 2) Render corner vs speed scatter plot
function renderCornerChart(angleDegs, speedData) {
  const cornerThreshold = 20;
  const cornerPts = [], straightPts = [];
  angleDegs.forEach((ang, i) => {
    if (i === 0) return;
    const pt = { x: ang, y: speedData[i], idx: i };
    (ang > cornerThreshold ? cornerPts : straightPts).push(pt);
  });

  const ctx = document.getElementById('cornerChart').getContext('2d');
  new Chart(ctx, {
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
      onClick(evt) {
        const elems = this.getElementsAtEventForMode(evt, 'nearest', { intersect: true }, true);
        if (!elems.length) return;
        const { datasetIndex, index } = elems[0];
        const dataObj = this.data.datasets[datasetIndex].data[index];
        if (window.updatePlayback) window.updatePlayback(dataObj.idx);
      }
    }
  });
}

// 3) Simple moving average smoothing
function smoothArray(data, windowSize = 15) {
  const smoothed = [];
  for (let i = 0; i < data.length; i++) {
    const start = Math.max(0, i - Math.floor(windowSize / 2));
    const end = Math.min(data.length, i + Math.ceil(windowSize / 2));
    const avg = data.slice(start, end).reduce((a, b) => a + b, 0) / (end - start);
    smoothed.push(avg);
  }
  return smoothed;
}

// 4) Render acceleration profile with highlights
function renderAccelChart(accelData, cumulativeDistance, speedData, selectedBins = [], speedBins = []) {
  const smoothAccel = smoothArray(accelData, 15);
  const dataWithIdx = smoothAccel.map((a, i) => ({ x: cumulativeDistance[i] / 1000, y: a, idx: i }));

  const ctx = document.getElementById('accelChart').getContext('2d');
  if (window.accelChart) window.accelChart.destroy();
  window.accelChart = new Chart(ctx, {
    type: 'line',
    data: { datasets: [ { label: 'Accel (m/s²)', data: dataWithIdx } ] },
    options: {
      interaction: { mode: 'nearest', axis: 'x', intersect: true },
      scales: { x: { title: { display: true, text: 'Distance (km)' } } },
      onClick(evt) {
        const elems = this.getElementsAtEventForMode(evt, 'nearest', { intersect: true }, true);
        if (!elems.length) return;
        const { index } = elems[0];
        if (window.updatePlayback) window.updatePlayback(this.data.datasets[0].data[index].idx);
      }
    }
  });
}

// 5) Entry point for analyticsunction initAnalytics(points, speedData, cumulativeDistance) {
  const { angleDegs, accelData } = computeAnalytics(points, speedData);
  renderCornerChart(angleDegs, speedData);
  window.accelData = accelData;
  renderAccelChart(accelData, cumulativeDistance, speedData, [], []);
}

// 6) Expose globals for script.js access
window.setupChart        = setupChart;
window.renderSpeedFilter = renderSpeedFilter;
window.initAnalytics     = initAnalytics;

// Note: loadGPX comes from script.js and should be loaded first in index.html
