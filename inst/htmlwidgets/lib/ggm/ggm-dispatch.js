// ggm-dispatch.js -- backend-neutral core
//
// owns:
//   GGM.instances : elId -> {adapter, state}
//   GGM.adapters  : name -> adapter object (verb impls)
//   shiny "ggm:*" message routing
//
// knows nothing about uPlot. animation layer + shiny talk
// only to this file.

(function () {
  "use strict";

  var GGM = window.GGM = window.GGM || {};
  GGM.instances = GGM.instances || {};
  GGM.adapters  = GGM.adapters  || {};

  // adapter contract (each adapter implements):
  //   create(el, cfg)          -> state (backend-private)
  //   destroy(state)
  //   resize(state, w, h)
  //   setData(state, columns)
  //   setViewport(state, v)    v = {xmin,xmax,ymin,ymax}
  //   setSeries(state, s)      s = {series,visible,color,label}
  //   valToPos(state, val, axis) -> px   (for animation layer)
  //   posToVal(state, px, axis)  -> val

  // --- lifecycle (called by widget binding) ---------------------

  GGM.create = function (el, cfg) {
    var ad = GGM.adapters[cfg.backend];
    if (!ad) throw new Error("ggm: no adapter '" + cfg.backend + "'");
    GGM.destroy(el.id); // re-render safety
    GGM.instances[el.id] = {
      adapter: ad,
      state: ad.create(el, cfg)
    };
    return GGM.instances[el.id];
  };

  GGM.destroy = function (id) {
    var inst = GGM.instances[id];
    if (!inst) return;
    inst.adapter.destroy(inst.state);
    delete GGM.instances[id];
  };

  GGM.resize = function (id, w, h) {
    var inst = GGM.instances[id];
    if (inst) inst.adapter.resize(inst.state, w, h);
  };

  // --- verb dispatch --------------------------------------------

  // call a verb on an instance; used by shiny handlers below and
  // directly by the animation layer (GGM.call(id, "valToPos", ...))
  GGM.call = function (id, verb) {
    var inst = GGM.instances[id];
    if (!inst) return null; // widget not rendered yet; drop msg
    var args = Array.prototype.slice.call(arguments, 2);
    return inst.adapter[verb].apply(
      inst.adapter, [inst.state].concat(args)
    );
  };

  // --- shiny routing --------------------------------------------

  // msg always carries msg.id (set by ggm_send in backend.R)
  if (window.Shiny) {
    Shiny.addCustomMessageHandler("ggm:set_data", function (msg) {
      GGM.call(msg.id, "setData", msg.columns);
    });
    Shiny.addCustomMessageHandler("ggm:set_viewport", function (msg) {
      GGM.call(msg.id, "setViewport", msg);
    });
    Shiny.addCustomMessageHandler("ggm:set_series", function (msg) {
      GGM.call(msg.id, "setSeries", msg);
    });
  }
})();
