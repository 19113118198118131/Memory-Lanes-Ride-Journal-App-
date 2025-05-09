// script.js

// 1) Imports & supabase setup
import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';
const SUPABASE_URL     = 'https://vodujxiwkpxaxaqnwkdd.supabase.co';
const SUPABASE_ANON_KEY = 'YOUR_ANON_KEY_HERE';
export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
window.supabase = supabase;

// 2) Globals & map placeholder
let map;
let points = [];
let cumulativeDistance = [];
let speedData = [];
let breakPoints = [];
let marker = null;
let trailPolyline = null;
let playInterval = null;
window.updatePlayback = null;

console.log('script.js loaded');

// 3) Expose loadGPX globally
window.loadGPX = async function(publicUrl) {
  // Ensure map is initialized
  if (!map) initMap();

  // Fetch GPX
  const xmlText = await fetch(publicUrl).then(r => r.text());
  const xml = new DOMParser().parseFromString(xmlText, 'application/xml');
  const trkpts = Array.from(xml.getElementsByTagName('trkpt')).map(tp => ({
    lat: +tp.getAttribute('lat'),
    lng: +tp.getAttribute('lon'),
    ele: +tp.getElementsByTagName('ele')[0]?.textContent || 0,
    time: new Date(tp.getElementsByTagName('time')[0]?.textContent)
  })).filter(p => p.lat && p.lng && p.time instanceof Date);

  if (!trkpts.length) return alert('No valid trackpoints found');

  // Assign and compute
  points = trkpts;
  cumulativeDistance = [0];
  speedData = [0];
  breakPoints = [];
  let lastTime = points[0].time;
  let lastLL = L.latLng(points[0].lat, points[0].lng);
  for (let i = 1; i < points.length; i++) {
    const pt = points[i];
    const d = lastLL.distanceTo(L.latLng(pt.lat, pt.lng));
    const dt = (pt.time - lastTime) / 1000;
    cumulativeDistance[i] = cumulativeDistance[i-1] + d;
    speedData[i] = dt > 0 ? (d/dt)*3.6 : 0;
    if (dt > 180 && d < 20) breakPoints.push(i);
    lastTime = pt.time;
    lastLL = L.latLng(pt.lat, pt.lng);
  }

  // Draw on map
  if (marker) map.removeLayer(marker);
  if (trailPolyline) map.removeLayer(trailPolyline);
  trailPolyline = L.polyline(points.map(p => [p.lat, p.lng]), { color: '#007bff', weight: 3, opacity: 0.7 })
    .addTo(map).bringToBack();
  map.fitBounds(trailPolyline.getBounds(), { padding: [30,30] });

  // Charts & analytics
  setupChart();
  renderSpeedFilter();
  if (window.Analytics) Analytics.initAnalytics(points, speedData, cumulativeDistance);
};

// 4) Initialize map
function initMap() {
  map = L.map('map').setView([20, 0], 2);
  setTimeout(() => map.invalidateSize(), 0);
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '© OpenStreetMap contributors'
  }).addTo(map);
}

// 5) Preload from dashboard
(async () => {
  await supabase.auth.getSession();
  const rideId = new URLSearchParams(window.location.search).get('ride');
  console.log('▶ script sees rideId=', rideId);
  if (rideId) {
    document.getElementById('auth-section').style.display = 'none';
    document.getElementById('upload-section').style.display = 'none';
    document.getElementById('save-ride-form').style.display = 'none';
    document.getElementById('map-section').style.display = 'block';
    document.getElementById('summary-section').style.display = 'block';
    document.getElementById('timeline').style.display = 'block';
    document.getElementById('analytics-container').style.display = 'block';

    const { data: ride, error } = await supabase
      .from('ride_logs')
      .select('gpx_path, title')
      .eq('id', rideId)
      .single();
    if (ride && !error) {
      document.getElementById('ride-title').value = ride.title;
      loadGPX(supabase.storage.from('gpx-files').getPublicUrl(ride.gpx_path).publicUrl);
      document.getElementById('save-ride-form').style.display = 'block';
    }
  }
})();

// 6) DOMContentLoaded: file input & auth logic
document.addEventListener('DOMContentLoaded', () => {
  // Map
  initMap();

  // File upload GPX
  const uploadInput = document.getElementById('gpx-upload');
  uploadInput.addEventListener('change', e => {
    const file = e.target.files[0];
    if (file) loadGPX(URL.createObjectURL(file));
  });

  // Save form visibility
  supabase.auth.getUser().then(({ data: { user } }) => {
    if (!user) document.getElementById('save-ride-form').style.display = 'none';
  });

  // Auth handlers
  document.getElementById('login-btn').addEventListener('click', async () => { /* ... */ });
  document.getElementById('signup-btn').addEventListener('click', async () => { /* ... */ });

  // Other initialization: charts, buttons...
  setupChart();
  renderSpeedFilter();
});
