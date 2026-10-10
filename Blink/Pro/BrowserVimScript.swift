//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K   P R O
//
// JavaScript injected into the built-in browser: Vim-style keys and
// homerow-style link hints. Native actions (address bar, close) are posted
// to the "blinkpro" message handler.
//
//////////////////////////////////////////////////////////////////////////////////

import Foundation

enum BrowserVimScript {
  static let messageHandler = "blinkpro"

  static let source = #"""
(function () {
  if (window.__blinkProVim) { return; }
  window.__blinkProVim = true;

  var STEP = 90;
  var hints = null, typed = '', pendingG = false, gTimer = null;
  var CHARS = 'asdfghjklqwertyuiopzxcvbnm';

  function post(action, payload) {
    try { window.webkit.messageHandlers.blinkpro.postMessage({ action: action, payload: payload || null }); } catch (e) {}
  }
  function isEditable(el) {
    if (!el) { return false; }
    if (el.isContentEditable) { return true; }
    var t = el.tagName;
    return t === 'INPUT' || t === 'TEXTAREA' || t === 'SELECT';
  }
  function scroller() {
    return document.scrollingElement || document.documentElement;
  }
  function visible(el) {
    var r = el.getBoundingClientRect();
    if (r.width < 2 || r.height < 2) { return false; }
    if (r.bottom < 0 || r.top > window.innerHeight || r.right < 0 || r.left > window.innerWidth) { return false; }
    var s = getComputedStyle(el);
    if (s.visibility === 'hidden' || s.display === 'none' || s.opacity === '0') { return false; }
    var cx = Math.min(Math.max(r.left + r.width / 2, 1), window.innerWidth - 1);
    var cy = Math.min(Math.max(r.top + r.height / 2, 1), window.innerHeight - 1);
    var top = document.elementFromPoint(cx, cy);
    return !!top && (top === el || el.contains(top) || top.contains(el));
  }
  function labels(n) {
    var len = 1;
    while (Math.pow(CHARS.length, len) < n) { len++; }
    var out = [];
    for (var i = 0; i < n; i++) {
      var s = '', v = i;
      for (var k = 0; k < len; k++) { s = CHARS[v % CHARS.length] + s; v = Math.floor(v / CHARS.length); }
      out.push(s);
    }
    return out;
  }
  function clearHints() {
    if (hints) { hints.box.remove(); hints = null; }
    typed = '';
  }
  function showHints() {
    clearHints();
    var sel = 'a[href], button, input, textarea, select, summary, [role="button"], [role="link"], [role="tab"], [role="menuitem"], [onclick], [tabindex]:not([tabindex="-1"])';
    var els = Array.prototype.slice.call(document.querySelectorAll(sel)).filter(visible);
    if (!els.length) { return; }
    var box = document.createElement('div');
    box.id = '__blinkpro_hints';
    box.style.cssText = 'position:fixed;left:0;top:0;width:0;height:0;z-index:2147483647;pointer-events:none;font:bold 12px/1 -apple-system,Helvetica,sans-serif;';
    var labs = labels(els.length), spans = [];
    els.forEach(function (el, i) {
      var r = el.getBoundingClientRect();
      var sp = document.createElement('span');
      sp.textContent = labs[i].toUpperCase();
      sp.style.cssText = 'position:fixed;left:' + Math.max(0, r.left - 2) + 'px;top:' + Math.max(0, r.top - 2) + 'px;' +
        'background:#ffe14d;color:#222;border:1px solid #c8a800;border-radius:3px;padding:2px 4px;box-shadow:0 1px 3px rgba(0,0,0,.4);letter-spacing:1px;';
      box.appendChild(sp);
      spans.push(sp);
    });
    document.documentElement.appendChild(box);
    hints = { box: box, els: els, labels: labs, spans: spans };
  }
  function filterHints() {
    var remaining = 0, match = -1;
    hints.labels.forEach(function (l, i) {
      var ok = l.indexOf(typed) === 0;
      hints.spans[i].style.display = ok ? '' : 'none';
      if (ok) {
        remaining++;
        hints.spans[i].innerHTML = '<span style="color:#b00">' + typed.toUpperCase() + '</span>' + l.slice(typed.length).toUpperCase();
        if (l === typed) { match = i; }
      }
    });
    if (match >= 0) {
      var el = hints.els[match];
      clearHints();
      if (isEditable(el)) { el.focus(); }
      else { el.focus && el.focus(); el.click(); }
    } else if (remaining === 0) {
      clearHints();
    }
  }
  function scrollBy(dy) { window.scrollBy({ top: dy, left: 0, behavior: 'auto' }); }

  window.addEventListener('keydown', function (e) {
    if (e.metaKey || e.ctrlKey || e.altKey) { return; }
    var active = document.activeElement;
    if (isEditable(active)) {
      if (e.key === 'Escape') { active.blur(); e.preventDefault(); }
      return;
    }
    if (hints) {
      e.preventDefault(); e.stopPropagation();
      if (e.key === 'Escape') { clearHints(); return; }
      if (e.key === 'Backspace') { typed = typed.slice(0, -1); filterHints(); return; }
      if (e.key.length === 1 && CHARS.indexOf(e.key.toLowerCase()) >= 0) { typed += e.key.toLowerCase(); filterHints(); }
      return;
    }
    var handled = true;
    switch (e.key) {
      case 'j': scrollBy(STEP); break;
      case 'k': scrollBy(-STEP); break;
      case 'd': scrollBy(window.innerHeight / 2); break;
      case 'u': scrollBy(-window.innerHeight / 2); break;
      case ' ': scrollBy(e.shiftKey ? -window.innerHeight * 0.9 : window.innerHeight * 0.9); break;
      case 'G': window.scrollTo({ top: scroller().scrollHeight, behavior: 'auto' }); break;
      case 'g':
        if (pendingG) { window.scrollTo({ top: 0, behavior: 'auto' }); pendingG = false; clearTimeout(gTimer); }
        else { pendingG = true; gTimer = setTimeout(function () { pendingG = false; }, 700); }
        break;
      case 'f': showHints(); break;
      case 'H': history.back(); break;
      case 'L': history.forward(); break;
      case 'r': location.reload(); break;
      case 'o': case '/': post('address'); break;
      case 'y': post('copyURL', location.href); break;
      case 'x': post('close'); break;
      case 'Escape': clearHints(); break;
      default: handled = false;
    }
    if (handled) { e.preventDefault(); e.stopPropagation(); }
  }, true);

  window.addEventListener('scroll', function () { if (hints) { clearHints(); } }, { passive: true });

  // Pages like Google autofocus their search box, which would swallow j/k and
  // Option shortcuts. Release that focus unless the user interacted with the page.
  var interacted = false;
  window.addEventListener('pointerdown', function () { interacted = true; }, true);
  window.addEventListener('keydown', function (e) {
    if (!e.metaKey && !e.altKey && !e.ctrlKey && isEditable(document.activeElement) && e.key.length === 1) { interacted = true; }
  }, true);
  function releaseAutofocus() {
    if (!interacted && isEditable(document.activeElement)) { document.activeElement.blur(); }
  }
  [0, 300, 1000, 2500].forEach(function (ms) { setTimeout(releaseAutofocus, ms); });
})();
"""#

  /// Always injected: hide/reset shortcuts intercepted in the page itself, in the
  /// capture phase, so they work even while a page text box has focus (where the
  /// web process would otherwise consume Option+C as a typed character).
  static let hotkeys = #"""
(function () {
  if (window.__blinkProHotkeys) { return; }
  window.__blinkProHotkeys = true;
  function post(action) {
    try { window.webkit.messageHandlers.blinkpro.postMessage({ action: action, payload: null }); } catch (e) {}
  }
  window.addEventListener('keydown', function (e) {
    var k = (e.key || '').toLowerCase();
    var alt = e.altKey && !e.metaKey && !e.ctrlKey;
    var meta = e.metaKey && !e.altKey && !e.ctrlKey;
    if ((alt && !e.shiftKey && (k === 'c' || k === 'ç')) || (meta && k === 'w')) {
      e.preventDefault(); e.stopImmediatePropagation(); post('close');
    } else if (alt && e.shiftKey && (k === 'c' || k === 'ç')) {
      e.preventDefault(); e.stopImmediatePropagation(); post('reset');
    } else if (meta && k === '.') {
      e.preventDefault(); e.stopImmediatePropagation(); post('stop');
    } else if (alt && (k === 'o' || k === 'ø')) {
      e.preventDefault(); e.stopImmediatePropagation(); post('address');
    }
  }, true);
})();
"""#

  /// Local start page shown the first time the browser is toggled open.
  static let startPageHTML = """
<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  html,body{margin:0;height:100%;background:#0f1115;color:#c9d1d9;font:16px/1.6 -apple-system,Helvetica,sans-serif}
  main{max-width:640px;margin:0 auto;padding:12vh 24px}
  h1{font-size:22px;font-weight:600;color:#fff;margin:0 0 6px}
  p{color:#8b949e;margin:0 0 28px}
  table{border-collapse:collapse;width:100%}
  td{padding:6px 0;border-bottom:1px solid #21262d}
  td:first-child{width:160px;font-family:ui-monospace,Menlo,monospace;color:#79c0ff}
</style></head><body><main>
<h1>Blink Pro Browser</h1>
<p>Type in the address bar to search. Esc returns to the page.</p>
<table>
<tr><td>⌥O · o · /</td><td>Address bar</td></tr>
<tr><td>f</td><td>Link hints: type the label to click</td></tr>
<tr><td>j k · d u · gg G</td><td>Scroll</td></tr>
<tr><td>H L · r</td><td>Back, forward, reload</td></tr>
<tr><td>y · x</td><td>Copy URL · hide browser</td></tr>
<tr><td>⌥C · ⌘W</td><td>Hide browser (page is kept)</td></tr>
<tr><td>⌥⇧C</td><td>Reset browser (kills a stuck page)</td></tr>
</table>
</main></body></html>
"""

  /// CSS that inverts the page for "force dark" while keeping media natural.
  static let forceDarkCSS = #"""
(function () {
  if (document.getElementById('__blinkpro_dark')) { return; }
  var st = document.createElement('style');
  st.id = '__blinkpro_dark';
  st.textContent = 'html{filter:invert(1) hue-rotate(180deg)!important;background:#111!important;}' +
    'img,video,canvas,picture,svg,iframe,[style*="background-image"]{filter:invert(1) hue-rotate(180deg)!important;}';
  (document.head || document.documentElement).appendChild(st);
})();
"""#
}
