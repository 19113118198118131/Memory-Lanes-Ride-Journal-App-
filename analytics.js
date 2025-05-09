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
      interaction: { mode: 'nearest', axis: 'xy', intersect: true },
      scales: {
        x: { title: { display: true, text: 'Turn Angle (°)' } },
        y: { title: { display: true, text: 'Speed (km/h)' } }
      },
      onClick: function(evt) {
        const elements = this.getElementsAtEventForMode(evt, 'nearest', { intersect: true }, true);
        if (!elements.length) return;
        const { datasetIndex, index } = elements[0];
        const dataObj = this.data.datasets[datasetIndex].data[index];
        if (window.updatePlayback) window.updatePlayback(dataObj.idx);
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

// 4) Render acceleration chart with highlight overlay

function renderAccelChart(accelData, cumulativeDistance, speedData, selectedBins = [], speedBins = []) {
  console.log("Speed data (sample):", speedData.slice(0, 50));
  console.log("Speed min:", Math.min(...speedData));
  console.log("Speed max:", Math.max(...speedData));
    
  const labels = cumulativeDistance.map(d => (d / 1000).toFixed(2));
  const smoothAccel = smoothArray(accelData, 15);
  const dataWithIdx = smoothAccel.map((a, i) => ({
    x: cumulativeDistance[i] / 1000,
    y: a,
    idx: i
  }));


  const maxDistance = Math.max(...cumulativeDistance) / 1000;
  const xTickStep = maxDistance > 300 ? 50 : maxDistance > 100 ? 25 : 10;

  const ctx = document.getElementById('accelChart').getContext('2d');
  const g = ctx.createLinearGradient(0, 0, 0, 300);
  g.addColorStop(0, 'rgba(0, 123, 255, 0.6)');
  g.addColorStop(1, 'rgba(0, 123, 255, 0.1)');

  // Create highlight points based on selected speed bins
  const highlightPoints = [];
if (selectedBins.length > 0) {
  for (let i = 1; i < speedData.length; i++) {
    const s = speedData[i];
    for (let binIndex of selectedBins) {
      const { min, max } = speedBins[binIndex];
      const inRange = (s >= min && s < max) || (binIndex === speedBins.length - 1 && s >= min);
      if (inRange) {
        const x = +(cumulativeDistance[i] / 1000).toFixed(2);
        const y = smoothAccel[i];
        if (!isNaN(y)) highlightPoints.push({ x, y, idx: i });
        break;
      }
    }
  }
}


  // 🔍 Log to verify
  console.log("Selected bins:", selectedBins);
  console.log("Highlight points found:", highlightPoints.length);
  if (highlightPoints.length > 0) console.log("Sample highlight:", highlightPoints[0]);

  // Optional: fallback demo highlight
  // if (highlightPoints.length === 0) {
  //   highlightPoints.push({ x: 20, y: 0.2 }, { x: 40, y: 0.1 }, { x: 60, y: 0.15 });
  // }

if (window.accelChart && typeof window.accelChart.destroy === 'function') {
  window.accelChart.destroy();
}

window.accelChart = new Chart(ctx, {
  type: 'line',
    data: {
      labels,
      datasets: [
        {
          label: 'Acceleration (m/s²)',
          data: dataWithIdx,
          borderWidth: 1,
          pointRadius: 0,
          pointHoverRadius: 4,
          tension: 0.1,
          borderColor: '#007bff',
          backgroundColor: g,
          fill: true
        },
        {
          label: 'Highlighted Speeds',
          data: highlightPoints,
          type: 'scatter',
          pointRadius: 4,
          backgroundColor: 'rgba(255, 99, 132, 0.8)',
          borderColor: '#ff4d6d',
          showLine: false
        }
  


      ]
    },
    options: {
      interaction: { mode: 'nearest', axis: 'xy', intersect: true },
      scales: {
        x: {
          type: 'linear',
          title: { display: true, text: 'Distance (km)' },
          grid: { color: '#223' },
          ticks: {
            autoSkip: false,
            stepSize: xTickStep,
            callback: v => Number(v).toFixed(0)
          }
        },
        y: {
          title: { display: true, text: 'Accel (m/s²)' }
        }
      },
      onClick: function(evt) {
        const elements = this.getElementsAtEventForMode(evt, 'nearest', { intersect: true }, true);
        if (!elements.length) return;
        const { datasetIndex, index } = elements[0];
        const dataObj = this.data.datasets[datasetIndex].data[index];
        if (window.updatePlayback) window.updatePlayback(dataObj.idx);
      },
      plugins: {
        tooltip: {
          callbacks: {
            label: ctx => `Dist: ${ctx.label} km, Accel: ${ctx.raw.y.toFixed(2)} m/s²`
          }
        }
      }
    }
  });
}

// 5) Entry point
function initAnalytics(points, speedData, cumulativeDistance) {
  const { angleDegs, accelData } = computeAnalytics(points, speedData);
  renderCornerChart(angleDegs, speedData);
  window.accelData = accelData; // make it global
  renderAccelChart(accelData, cumulativeDistance, speedData, [], []);

}

// expose globally
window.Analytics = { initAnalytics, renderAccelChart };
