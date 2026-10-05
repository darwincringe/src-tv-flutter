// CarPlay browsers (APTV and similar) open their own fullscreen keyboard.
// On Enter they assign the typed string to the focused element's .value
// and often never fire an `input` event. Flutter web draws text itself and
// only updates a TextField from `input` events on its .flt-text-editing
// element, so the field stays blank. Ordinary sites work because their
// boxes are real inputs that show .value directly.
//
// Loaded before Flutter. Patching the value setter is enough for keyboards
// that write straight onto Flutter's field. The extra listeners cover a
// keyboard that types into some other input, then hits Enter.
(function () {
  var inputProto = window.HTMLInputElement && HTMLInputElement.prototype;
  var areaProto = window.HTMLTextAreaElement && HTMLTextAreaElement.prototype;
  if (!inputProto || !areaProto) return;

  var nativeInputSet = Object.getOwnPropertyDescriptor(inputProto, 'value').set;
  var nativeAreaSet = Object.getOwnPropertyDescriptor(areaProto, 'value').set;
  var typing = false;
  var dispatching = false;

  function isField(el) {
    if (!el || !el.tagName) return false;
    return el.tagName === 'INPUT' || el.tagName === 'TEXTAREA';
  }

  function isFlutterField(el) {
    return isField(el) && el.classList && el.classList.contains('flt-text-editing');
  }

  function dispatchInput(el) {
    if (!isField(el) || dispatching) return;
    dispatching = true;
    try {
      el.dispatchEvent(new Event('input', { bubbles: true }));
    } catch (e) {
      // Ignore. A detached field just has nothing to update.
    } finally {
      dispatching = false;
    }
  }

  function armTyping() {
    typing = true;
    setTimeout(function () {
      typing = false;
    }, 0);
  }

  function patch(proto, nativeSet) {
    var desc = Object.getOwnPropertyDescriptor(proto, 'value');
    if (!desc || !nativeSet || nativeSet.__srctv) return;
    function set(v) {
      var before = this.value;
      nativeSet.call(this, v);
      if (typing || dispatching) return;
      if (this.value === before) return;
      dispatchInput(this);
    }
    set.__srctv = true;
    Object.defineProperty(proto, 'value', {
      configurable: true,
      enumerable: desc.enumerable,
      get: desc.get,
      set: set,
    });
  }

  patch(inputProto, nativeInputSet);
  patch(areaProto, nativeAreaSet);

  document.addEventListener('beforeinput', armTyping, true);

  function flutterField() {
    var list = document.querySelectorAll(
      'input.flt-text-editing, textarea.flt-text-editing'
    );
    var i;
    for (i = 0; i < list.length; i++) {
      if (list[i] === document.activeElement) return list[i];
    }
    return list.length ? list[list.length - 1] : null;
  }

  // A keyboard that focused some other box: copy its text into Flutter's.
  function mirrorIntoFlutter(source) {
    if (!isField(source) || isFlutterField(source)) return;
    if (source.closest && source.closest('flutter-view')) return;
    var target = flutterField();
    if (!target || target === source) return;
    if (target.value === source.value) {
      dispatchInput(target);
      return;
    }
    target.value = source.value;
  }

  document.addEventListener(
    'input',
    function (e) {
      mirrorIntoFlutter(e.target);
    },
    true
  );

  document.addEventListener(
    'change',
    function (e) {
      if (isFlutterField(e.target)) dispatchInput(e.target);
      else mirrorIntoFlutter(e.target);
    },
    true
  );

  function onEnter(e) {
    if (e.key !== 'Enter' && e.keyCode !== 13) return;
    var el = e.target;
    if (!isField(el)) return;
    if (isFlutterField(el)) dispatchInput(el);
    else mirrorIntoFlutter(el);
  }

  // Capture runs before Flutter's own keydown listener, which treats Enter
  // as submit using whatever text it last heard about.
  document.addEventListener('keydown', onEnter, true);
  document.addEventListener('keyup', onEnter, true);
})();
