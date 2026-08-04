// gram-dispatch.js -- backend-neutral core
//
// owns:
//   GRAM.instances : elId -> {adapter, state}
//   GRAM.adapters  : name -> adapter object (verb impls)
//   shiny "gram:*" message routing, both directions
//
// knows nothing about uPlot. animation layer + shiny talk
// only to this file.

(function () {
  "use strict";

  var GRAM = window.GRAM = window.GRAM || {};
  GRAM.instances = GRAM.instances || {};
  GRAM.adapters  = GRAM.adapters  || {};

  // adapter contract (each adapter implements):
  //   create(el, cfg)          -> state (backend-private)
  //   destroy(state)
  //   resize(state, w, h)
  //   setData(state, columns)
  //   setViewport(state, v)    v = {xmin,xmax,ymin,ymax}
  //   setSeries(state, s)      s = {series,visible,color,label}
  //   setVisible(state, ch)    ch = 1-based channel indices to show;
  //                            channel visibility is view state, so the
  //                            backend owns it and no R read is involved
  //   valToPos(state, val, axis) -> px   (for animation layer)
  //   posToVal(state, px, axis)  -> val

  // --- lifecycle (called by widget binding) ---------------------

  GRAM.create = function (el, cfg) {
    var ad = GRAM.adapters[cfg.backend];
    if (!ad) throw new Error("gram: no adapter '" + cfg.backend + "'");
    GRAM.destroy(el.id); // re-render safety
    GRAM.instances[el.id] = {
      adapter: ad,
      state: ad.create(el, cfg)
    };
    return GRAM.instances[el.id];
  };

  GRAM.destroy = function (id) {
    var inst = GRAM.instances[id];
    if (!inst) return;
    inst.adapter.destroy(inst.state);
    delete GRAM.instances[id];
  };

  GRAM.resize = function (id, w, h) {
    var inst = GRAM.instances[id];
    if (inst) inst.adapter.resize(inst.state, w, h);
  };

  // --- verb dispatch --------------------------------------------

  // call a verb on an instance; used by shiny handlers below and
  // directly by the animation layer (GRAM.call(id, "valToPos", ...))
  GRAM.call = function (id, verb) {
    var inst = GRAM.instances[id];
    if (!inst) return null; // widget not rendered yet; drop msg
    var args = Array.prototype.slice.call(arguments, 2);
    return inst.adapter[verb].apply(
      inst.adapter, [inst.state].concat(args)
    );
  };

  // --- shiny routing, outbound ----------------------------------

  // The one path from a backend back to R. Adapters call this instead of
  // touching Shiny, so a second backend inherits the wire unchanged.
  //
  // priority "event" is required, not decoration: without it Shiny drops a
  // value identical to the last one, so selecting the same range twice
  // would go unreported.
  GRAM.emit = function (el, event, value) {
    if (!window.Shiny || !el || !el.id) return;
    Shiny.setInputValue(el.id + "_" + event, value, { priority: "event" });
  };

  // --- shiny routing, inbound -----------------------------------

  // msg always carries msg.id (set by gram_send in backend.R)
  if (window.Shiny) {
    Shiny.addCustomMessageHandler("gram:set_data", function (msg) {
      GRAM.call(msg.id, "setData", msg.columns);
    });
    Shiny.addCustomMessageHandler("gram:set_viewport", function (msg) {
      GRAM.call(msg.id, "setViewport", msg);
    });
    Shiny.addCustomMessageHandler("gram:set_series", function (msg) {
      GRAM.call(msg.id, "setSeries", msg);
    });
    Shiny.addCustomMessageHandler("gram:set_visible", function (msg) {
      GRAM.call(msg.id, "setVisible", msg.channels);
    });
  }
})();
