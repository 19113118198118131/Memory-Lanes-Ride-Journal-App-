// Inside the native iOS app Capacitor injects `window.Capacitor` (with
// `registerPlugin`) before any web code runs, so we use that directly and the
// app never depends on a runtime CDN fetch to reach its own native recorder —
// which matters most exactly when connectivity is poor (a tunnel, the middle of
// nowhere). The dynamic CDN import is only a fallback for a browser context,
// where every exported function below already short-circuits on
// `isNativeRideRecorderAvailable()` and the plugin is never actually invoked.
async function resolveRegisterPlugin() {
  if (window.Capacitor?.registerPlugin) return window.Capacitor.registerPlugin;
  const mod = await import('https://cdn.jsdelivr.net/npm/@capacitor/core@8/+esm');
  return mod.registerPlugin;
}

let nativeRideRecorderPromise = null;
function getNativeRideRecorder() {
  if (!nativeRideRecorderPromise) {
    nativeRideRecorderPromise = resolveRegisterPlugin()
      .then(register => register('MemoryLanesRideRecorder'));
  }
  return nativeRideRecorderPromise;
}

export function isNativeRideRecorderAvailable() {
  return Boolean(window.Capacitor?.isNativePlatform?.());
}

export async function checkRideRecorderPermission() {
  if (!isNativeRideRecorderAvailable()) return { location: 'web' };
  return (await getNativeRideRecorder()).checkPermissions();
}

export async function requestRideRecorderPermission() {
  if (!isNativeRideRecorderAvailable()) return { location: 'web' };
  return (await getNativeRideRecorder()).requestPermissions();
}

export async function startNativeRideRecording() {
  if (!isNativeRideRecorderAvailable()) {
    throw new Error('Native ride recording is only available inside the iOS app.');
  }
  return (await getNativeRideRecorder()).start();
}

export async function stopNativeRideRecording() {
  if (!isNativeRideRecorderAvailable()) return { recording: false, pointCount: 0 };
  return (await getNativeRideRecorder()).stop();
}

export async function getNativeRideRecordingStatus() {
  if (!isNativeRideRecorderAvailable()) return { recording: false, pointCount: 0, permission: 'web' };
  return (await getNativeRideRecorder()).getStatus();
}

export async function getNativeRideTrack() {
  if (!isNativeRideRecorderAvailable()) return { startedAt: null, pointCount: 0, points: [] };
  return (await getNativeRideRecorder()).getTrack();
}

export async function clearNativeRideTrack() {
  if (!isNativeRideRecorderAvailable()) return { recording: false, pointCount: 0 };
  return (await getNativeRideRecorder()).clear();
}

export async function onNativeRidePoint(callback) {
  if (!isNativeRideRecorderAvailable()) return { remove: () => {} };
  return (await getNativeRideRecorder()).addListener('rideRecorderPoint', callback);
}

export async function onNativeRideStatus(callback) {
  if (!isNativeRideRecorderAvailable()) return { remove: () => {} };
  return (await getNativeRideRecorder()).addListener('rideRecorderStatus', callback);
}

export async function onNativeRideError(callback) {
  if (!isNativeRideRecorderAvailable()) return { remove: () => {} };
  return (await getNativeRideRecorder()).addListener('rideRecorderError', callback);
}

export function nativeTrackToGPX(track, title = 'Memory Lanes Ride') {
  const points = Array.isArray(track?.points) ? track.points : [];
  const safeTitle = escapeXml(title);
  const trkpts = points.map(point => {
    const lat = Number(point.lat);
    const lng = Number(point.lng);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return '';
    const ele = Number.isFinite(Number(point.altitude)) ? `<ele>${Number(point.altitude).toFixed(1)}</ele>` : '';
    const time = point.timestamp ? `<time>${escapeXml(point.timestamp)}</time>` : '';
    return `    <trkpt lat="${lat.toFixed(7)}" lon="${lng.toFixed(7)}">${ele}${time}</trkpt>`;
  }).filter(Boolean).join('\n');

  return `<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Memory Lanes iOS" xmlns="http://www.topografix.com/GPX/1/1">
  <trk>
    <name>${safeTitle}</name>
    <trkseg>
${trkpts}
    </trkseg>
  </trk>
</gpx>`;
}

function escapeXml(value) {
  return String(value ?? '').replace(/[<>&"']/g, char => ({
    '<': '&lt;',
    '>': '&gt;',
    '&': '&amp;',
    '"': '&quot;',
    "'": '&apos;'
  }[char]));
}
