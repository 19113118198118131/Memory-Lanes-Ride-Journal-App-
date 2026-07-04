// theme.js — theme toggle. The correct theme is already applied pre-paint by the
// inline <head> script; this only handles the toggle button and persistence.
(function () {
  function current() {
    return document.documentElement.getAttribute('data-theme')
      || (window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark');
  }
  function apply(theme) {
    document.documentElement.setAttribute('data-theme', theme);
    try { localStorage.setItem('ml-theme', theme); } catch (e) {}
    document.querySelectorAll('[data-theme-toggle]').forEach(function (btn) {
      btn.setAttribute('aria-label', theme === 'light' ? 'Switch to dark mode' : 'Switch to light mode');
      btn.setAttribute('aria-pressed', theme === 'light' ? 'true' : 'false');
    });
  }
  function init() {
    document.querySelectorAll('[data-theme-toggle]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        apply(current() === 'light' ? 'dark' : 'light');
      });
    });
    apply(current()); // sync button state
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
