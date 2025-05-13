// analytics.js

// 1) Compute turn angles & accel
function computeAnalytics(points, speedData) {
  const angleDegs = Array(points.length).fill(0);
  const accelData = [0];

  // angles
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

  // accel (m/s²)
  for (let i = 1; i < speedData.length; i++) {
    const dt = (points[i].time - points[i - 1].time) / 1000;
    const dv = speedData[i] - speedData[i - 1];
    accelData[i] = dt ? (dv / dt) * (1000 / 3600) : 0;
  }

  return { angleDegs, accelData };
}

// 2) Render corner-vs-speed scatter
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
        { label: 'Corners', data: cornerPts, pointBackgroundColor: '#8338EC' },
        { label: 'Straights', data: straightPts, pointBackgroundColor: '#FF6384' }
      ]
    },
  options: {
    responsive: true,
    animation: false,
    interaction: { mode: 'nearest', intersect: false },
onClick: function(evt) {
  const elements = this.getElementsAtEventForMode(evt, 'nearest', { intersect: false }, true);
  if (!elements.length) return;
  const dataPoint = this.data.datasets[elements[0].datasetIndex].data[elements[0].index];
  if (dataPoint && typeof dataPoint.idx === 'number') {
    window.jumpToPlaybackIndex(dataPoint.idx);
  }
},

      plugins: {
        tooltip: {
          callbacks: {
            label: ctx => `Angle: ${ctx.raw.x.toFixed(1)}°, Speed: ${ctx.raw.y.toFixed(1)} km/h`
          }
        }
      }
    }
  });
}

// 3) Smoothing helper
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



// 4) Entry point
function initAnalytics(points, speedData, cumulativeDistance) {
  const { angleDegs, accelData } = computeAnalytics(points, speedData);
  renderCornerChart(angleDegs, speedData);
  window.accelData = accelData; // make it global
  renderAccelChart(accelData, cumulativeDistance, speedData, [], []);

}

// expose globally
window.Analytics = { initAnalytics, renderAccelChart };
