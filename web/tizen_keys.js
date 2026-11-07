// Samsung's browser treats Arrow Up and Arrow Down as page scrolling.
// Stop that, and if the remote only sends a numeric key code, reissue the
// event with the names Flutter uses to move focus.
(function () {
  var base = document.querySelector('base');
  var href = base ? base.getAttribute('href') : '';
  var ua = navigator.userAgent || '';
  var tizen = window.__SRCTV_TIZEN === true
    || typeof window.tizen !== 'undefined'
    || /Tizen|SMART-TV/i.test(ua)
    || href === './';
  if (!tizen) return;

  var style = document.createElement('style');
  style.textContent = [
    'html,body{margin:0;padding:0;width:100%;height:100%;overflow:hidden!important;position:fixed;inset:0;}',
    'flt-glass-pane,flt-scene-host,flt-semantics-host{overflow:hidden!important;}'
  ].join('');
  document.head.appendChild(style);

  var arrows = {
    37: ['ArrowLeft', 'ArrowLeft'],
    38: ['ArrowUp', 'ArrowUp'],
    39: ['ArrowRight', 'ArrowRight'],
    40: ['ArrowDown', 'ArrowDown']
  };

  var sending = false;

  function editable(el) {
    if (!el || !el.tagName) return false;
    var tag = el.tagName.toLowerCase();
    if (tag === 'textarea' || el.isContentEditable) return true;
    if (tag !== 'input') return false;
    var type = (el.type || 'text').toLowerCase();
    return type === 'text' || type === 'search' || type === 'password'
      || type === 'email' || type === 'url' || type === 'tel' || type === 'number';
  }

  function onKey(e) {
    if (sending) return;
    var code = e.keyCode || e.which || 0;

    // Samsung remote Back. The player claims this while it is open so the
    // first press only hides the controls. Every other screen leaves through
    // history, which stays on this file because the TV build uses hash URLs.
    if (code === 10009 || code === 461) {
      e.preventDefault();
      e.stopImmediatePropagation();
      if (e.type === 'keydown' && !e.repeat) {
        if (typeof window.__srctvOnBack === 'function') window.__srctvOnBack();
        else history.back();
      }
      return;
    }

    var pair = arrows[code];
    if (!pair) return;

    var horizontal = code === 37 || code === 39;
    if (!(horizontal && editable(e.target))) e.preventDefault();

    if (e.key === pair[0] && e.code === pair[1]) return;

    e.stopImmediatePropagation();
    sending = true;
    try {
      window.dispatchEvent(new KeyboardEvent(e.type, {
        key: pair[0],
        code: pair[1],
        bubbles: true,
        cancelable: true,
        repeat: !!e.repeat
      }));
    } finally {
      sending = false;
    }
  }

  window.addEventListener('keydown', onKey, true);
  window.addEventListener('keyup', onKey, true);
  window.addEventListener('scroll', function () {
    if (window.scrollX || window.scrollY) window.scrollTo(0, 0);
  }, true);
})();
