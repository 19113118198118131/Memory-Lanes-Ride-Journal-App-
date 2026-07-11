// icons.js - Lucide-based inline SVG icon system for Memory Lanes.
// Zero dependencies, no network. Icons use currentColor so they inherit
// the button/text colour. Paths are from Lucide (ISC licensed, lucide.dev).
//
// Usage: buttons/nav keep their IDs and text; a leading emoji in the label
// is replaced by <svg class="ml-icon" ...> via applyIcons() on DOMContentLoaded.

const ML_ICONS = {
  upload:      '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" y1="3" x2="12" y2="15"/>',
  download:    '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/>',
  film:        '<rect x="2" y="3" width="20" height="18" rx="2"/><line x1="7" y1="3" x2="7" y2="21"/><line x1="17" y1="3" x2="17" y2="21"/><line x1="2" y1="9" x2="22" y2="9"/><line x1="2" y1="15" x2="22" y2="15"/>',
  notebook:    '<path d="M2 6h4"/><path d="M2 10h4"/><path d="M2 14h4"/><path d="M2 18h4"/><rect x="4" y="2" width="16" height="20" rx="2"/><path d="M16 2v20"/>',
  share:       '<circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><line x1="8.6" y1="13.5" x2="15.4" y2="17.5"/><line x1="15.4" y1="6.5" x2="8.6" y2="10.5"/>',
  eyeoff:      '<path d="M9.9 4.2A9.1 9.1 0 0 1 12 4c7 0 10 8 10 8a13.2 13.2 0 0 1-1.7 2.7"/><path d="M6.6 6.6A13.5 13.5 0 0 0 2 12s3 8 10 8a9 9 0 0 0 5.4-1.6"/><line x1="2" y1="2" x2="22" y2="22"/>',
  plus:        '<line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/>',
  route:       '<circle cx="6" cy="19" r="3"/><path d="M9 19h8.5a3.5 3.5 0 0 0 0-7h-11a3.5 3.5 0 0 1 0-7H15"/><circle cx="18" cy="5" r="3"/>',
  stats:       '<line x1="18" y1="20" x2="18" y2="10"/><line x1="12" y1="20" x2="12" y2="4"/><line x1="6" y1="20" x2="6" y2="14"/>',
  trending:    '<polyline points="22 7 13.5 15.5 8.5 10.5 2 17"/><polyline points="16 7 22 7 22 13"/>',
  trophy:      '<path d="M6 9H4.5a2.5 2.5 0 0 1 0-5H6"/><path d="M18 9h1.5a2.5 2.5 0 0 0 0-5H18"/><path d="M4 22h16"/><path d="M10 14.66V17c0 .55-.47.98-.97 1.21C7.85 18.75 7 20.24 7 22"/><path d="M14 14.66V17c0 .55.47.98.97 1.21C16.15 18.75 17 20.24 17 22"/><path d="M18 2H6v7a6 6 0 0 0 12 0V2Z"/>',
  map:         '<polygon points="3 6 9 3 15 6 21 3 21 18 15 21 9 18 3 21 3 6"/><line x1="9" y1="3" x2="9" y2="18"/><line x1="15" y1="6" x2="15" y2="21"/>',
  clock:       '<circle cx="12" cy="12" r="9"/><polyline points="12 7 12 12 15 14"/>',
  gallery:     '<rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.1-3.1a2 2 0 0 0-2.8 0L6 21"/>',
  book:        '<path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/>',
  play:        '<polygon points="6 4 20 12 6 20 6 4"/>',
  pin:         '<path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0Z"/><circle cx="12" cy="10" r="3"/>',
  sparkle:     '<path d="M12 3l1.9 5.6L19.5 10l-5.6 1.9L12 17l-1.9-5.1L4.5 10l5.6-1.4L12 3Z"/>',
  edit:        '<path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z"/>',
  save:        '<path d="M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v11a2 2 0 0 1-2 2Z"/><polyline points="17 21 17 13 7 13 7 21"/><polyline points="7 3 7 8 15 8"/>',
  undo:        '<path d="M3 7v6h6"/><path d="M21 17a9 9 0 0 0-9-9 9 9 0 0 0-6 2.3L3 13"/>',
  redo:        '<path d="M21 7v6h-6"/><path d="M3 17a9 9 0 0 1 9-9 9 9 0 0 1 6 2.3L21 13"/>',
  x:           '<line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>',
  trash:       '<polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/><line x1="10" y1="11" x2="10" y2="17"/><line x1="14" y1="11" x2="14" y2="17"/>',
  search:      '<circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/>',
  ruler:       '<path d="M21.3 8.7 8.7 21.3a1 1 0 0 1-1.4 0l-4.6-4.6a1 1 0 0 1 0-1.4L15.3 2.7a1 1 0 0 1 1.4 0l4.6 4.6a1 1 0 0 1 0 1.4Z"/><path d="m7.5 10.5 2 2"/><path d="m10.5 7.5 2 2"/><path d="m13.5 4.5 2 2"/><path d="m4.5 13.5 2 2"/>',
  mountain:    '<path d="m8 3 4 8 5-5 5 15H2L8 3z"/>',
  flag:        '<path d="M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z"/><line x1="4" y1="22" x2="4" y2="15"/>',
  gauge:       '<path d="m12 14 4-4"/><path d="M3.34 19a10 10 0 1 1 17.32 0"/>',
  brake:       '<circle cx="12" cy="12" r="9"/><path d="M12 7v5"/><circle cx="12" cy="16" r="0.5" fill="currentColor"/>',
  lightbulb:   '<path d="M9 18h6"/><path d="M10 22h4"/><path d="M15.09 14c.18-.98.65-1.74 1.41-2.5A4.65 4.65 0 0 0 18 8 6 6 0 0 0 6 8c0 1 .23 2.23 1.5 3.5A4.61 4.61 0 0 1 8.91 14"/>',
  arrowright:  '<line x1="5" y1="12" x2="19" y2="12"/><polyline points="12 5 19 12 12 19"/>',
  reverse:     '<line x1="21" y1="8" x2="3" y2="8"/><polyline points="7 4 3 8 7 12"/><line x1="3" y1="16" x2="21" y2="16"/><polyline points="17 12 21 16 17 20"/>'
};

function mlIconSVG(name, extraClass = '') {
  const p = ML_ICONS[name];
  if (!p) return '';
  return `<svg class="ml-icon ${extraClass}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${p}</svg>`;
}

// Map: element ID -> icon name (button/nav chrome only)
const ICON_BY_ID = {
  // index.html
  'upload-btn': 'upload', 'try-demo-btn': 'play', 'download-summary': 'download',
  'export-video': 'film', 'open-journal': 'notebook', 'share-ride-btn': 'share',
  'unshare-ride-btn': 'eyeoff', 'upload-another': 'upload', 'add-moment-btn': 'plus',
  'header-my-rides-btn': 'route',
  // dashboard.html
  'home-btn': 'plus', 'stats-btn': 'stats', 'export-data-btn': 'download', 'journal-btn': 'book',
  'record-ride-btn': 'play',
  // stats.html
  'back-dashboard-btn': 'route', 'new-ride-btn': 'plus',
  // edit-mode toolbar
  'edit-gpx-btn': 'edit', 'save-edited-gpx-btn': 'save', 'undo-edit-btn': 'undo',
  'redo-edit-btn': 'redo', 'bulk-add-btn': 'plus', 'bulk-delete-btn': 'trash', 'exit-edit-btn': 'x',
  'reverse-edit-btn': 'reverse', 'connect-start-edit-btn': 'flag', 'simplify-edit-btn': 'sparkle',
  'crop-edit-btn': 'ruler', 'split-edit-btn': 'route',
  // planner.html
  'planner-dashboard-btn': 'route', 'planner-record-btn': 'play', 'planner-undo-btn': 'undo', 'planner-redo-btn': 'redo',
  'planner-clear-btn': 'trash', 'planner-search-btn': 'search', 'planner-save-btn': 'save',
  'planner-export-btn': 'download', 'planner-reverse-btn': 'reverse', 'planner-connect-start-btn': 'flag',
  'planner-crop-btn': 'ruler', 'planner-split-btn': 'route',
  // ride-live.html
  'live-cancel-btn': 'x', 'live-start-btn': 'play', 'live-finish-btn': 'flag', 'live-save-btn': 'save',
  'live-moment-btn': 'pin', 'live-moment-save-btn': 'save', 'live-moment-cancel-btn': 'x',
  // route.html (shared route invite page)
  'route-save-btn': 'save', 'route-export-btn': 'download',
  // group.html (group ride lobby)
  // (group-copy-btn deliberately has no icon: its label flips to "Link
  // Copied!" via textContent, which would wipe an inline icon SVG)
  'group-join-btn': 'play', 'group-end-btn': 'x',
  // dashboard.html rider profile
  // (profile-toggle-btn deliberately has no icon: its label flips between
  // Edit/Close via textContent, which would wipe an inline icon SVG)
  'profile-save-btn': 'save',
};

// Replace a leading emoji in an element's text with an inline icon, keep the label.
function iconizeLabel(el, iconName) {
  // Remove any leading emoji + following space from the first text node
  for (const node of el.childNodes) {
    if (node.nodeType === Node.TEXT_NODE && node.textContent.trim()) {
      node.textContent = node.textContent.replace(
        /^[\s\u{1F000}-\u{1FAFF}\u{2190}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}]+/u, ''
      ).replace(/^\s+/, ' ');
      break;
    }
  }
  el.insertAdjacentHTML('afterbegin', mlIconSVG(iconName) + ' ');
  el.classList.add('has-icon');
}

function applyIcons() {
  // Decorative icons placed via data-icon (hero cards, etc.)
  document.querySelectorAll('[data-icon]').forEach(el => {
    if (!el.querySelector('svg')) el.innerHTML = mlIconSVG(el.dataset.icon) + el.innerHTML;
  });
  document.querySelectorAll('[data-head-icon]').forEach(el => {
    if (!el.querySelector('svg')) { el.insertAdjacentHTML('afterbegin', mlIconSVG(el.dataset.headIcon) + ' '); el.classList.add('has-icon'); }
  });
  Object.entries(ICON_BY_ID).forEach(([id, icon]) => {
    const el = document.getElementById(id);
    if (el) iconizeLabel(el, icon);
  });

  // Header nav: Logs | Moments | Journeys -> icon + text
  const navMap = { 'dashboard.html': 'route', 'journal.html': 'pin', 'stats.html': 'trending', 'planner.html': 'flag' };
  document.querySelectorAll('.vibe-nav [data-nav]').forEach(el => {
    const icon = navMap[el.dataset.nav];
    if (icon && !el.querySelector('svg')) {
      el.insertAdjacentHTML('afterbegin', mlIconSVG(icon) + ' ');
      el.classList.add('has-icon');
    }
  });

}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', applyIcons);
} else {
  applyIcons();
}

export { mlIconSVG, applyIcons };
