// Lifecycle shared by every backend, and the gesture rules they must agree
// on. A backend is an entry in GRAM.adapters providing create / destroy /
// resize / setData. It is named in the payload and looked up here, so a
// second renderer is another entry in the same bundle rather than another
// htmlwidget with its own binding and dependency set. Each adapter file
// registers itself and nothing else; this file never names one.
//
// What crosses the wire is { backend, spec, window, extent }. `spec` is
// whatever the backend's R-side builder produced and is opaque here. `window`
// and `extent` are neutral, because two jobs need them regardless of the
// renderer: skipping the viewport request when the drawn range still equals
// what was pushed, and clamping a pan to the record.

(function () {
  "use strict";

  var GRAM = (window.GRAM = window.GRAM || {});
  GRAM.instances = GRAM.instances || {};
  GRAM.adapters = GRAM.adapters || {};


  // --- gesture rules ---------------------------------------------
  //
  // Zoom and pan both end as a request for a range, debounced so one gesture
  // asks once. Panning clamps to the record extent, not the loaded window: a
  // reader may pan into what is not loaded yet and have the controller fill
  // it in; the canvas is briefly empty there.

  GRAM.viewportDebounceMs = 150;

  GRAM.clampRangeToExtent = function (extent, min, max) {
    var span = max - min;

    if (span >= extent.max - extent.min) return [extent.min, extent.max];
    if (min < extent.min) return [extent.min, extent.min + span];
    if (max > extent.max) return [extent.max - span, extent.max];
    return [min, max];
  };

  // Horizontal wheel travel in pixels: deltaX, or deltaY with shift held.
  // Line and page delta modes are scaled to pixels.
  GRAM.wheelDelta = function (event, plotWidthPx) {
    var delta = 0;
    if (Math.abs(event.deltaX) > Math.abs(event.deltaY)) delta = event.deltaX;
    else if (event.shiftKey) delta = event.deltaY;

    if (event.deltaMode === 1) return delta * 16;
    if (event.deltaMode === 2) return delta * plotWidthPx;
    return delta;
  };


  // --- lifecycle, called by the widget binding --------------------

  GRAM.create = function (el, cfg) {
    var backend = GRAM.adapters[cfg.backend];
    if (!backend) {
      throw new Error("gram: unknown backend '" + cfg.backend + "'");
    }

    GRAM.destroy(el.id); // re-render safety
    GRAM.instances[el.id] = {
      backend: backend,
      state: backend.create(el, cfg)
    };
    return GRAM.instances[el.id];
  };

  GRAM.destroy = function (id) {
    var instance = GRAM.instances[id];
    if (!instance) return;
    instance.backend.destroy(instance.state);
    delete GRAM.instances[id];
  };

  GRAM.resize = function (id) {
    var instance = GRAM.instances[id];
    if (instance) instance.backend.resize(instance.state);
  };


  // --- shiny ------------------------------------------------------

  // priority "event" is required: without it Shiny drops a value identical to
  // the last one, so panning back to a range already visited would go
  // unreported and the window would never be refilled
  GRAM.emit = function (el, event, value) {
    if (!window.Shiny || !el || !el.id) return;
    Shiny.setInputValue(el.id + "_" + event, value, { priority: "event" });
  };

  if (window.Shiny) {
    Shiny.addCustomMessageHandler("gram:set_data", function (msg) {
      var instance = GRAM.instances[msg.id];
      if (instance) {
        instance.backend.setData(instance.state, msg.spec, msg.window);
      }
    });
  }
})();
