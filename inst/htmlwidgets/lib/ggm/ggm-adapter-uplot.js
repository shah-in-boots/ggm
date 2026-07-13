// ggm-adapter-uplot.js -- uPlot implementation of adapter contract
//
// only JS file allowed to touch uPlot APIs.
// state object here = { u: uPlot inst, cfg: original config }

(function () {
  "use strict";

  var GGM = window.GGM;

  // build uPlot opts from backend-neutral cfg
  // kept minimal; grows as contract grows
  function buildOpts(el, cfg) {
    var series = [{}]; // slot 0 = x
    (cfg.series || []).forEach(function (s, i) {
      series.push({
        label: s.label || ("ch" + (i + 1)),
        stroke: s.color || "black",
        // no point markers at scale
        points: { show: false }
      });
    });

    return {
      width: el.clientWidth || 800,
      height: el.clientHeight || 400,
      series: series,
      scales: {
        // "index" scale: plain numeric axis, not time
        x: { time: cfg.scale && cfg.scale.kind === "time" }
      },
      // pan/zoom-friendly defaults; refine later
      cursor: { drag: { x: true, y: false } }
    };
  }

  GGM.adapters.uplot = {

    create: function (el, cfg) {
      var u = new uPlot(buildOpts(el, cfg), cfg.columns, el);
      return { u: u, cfg: cfg };
    },

    destroy: function (state) {
      state.u.destroy();
    },

    resize: function (state, w, h) {
      state.u.setSize({ width: w, height: h });
    },

    // columns arrive uPlot-shaped from R -> zero reshaping
    setData: function (state, columns) {
      // false = keep current scales (viewport) during sweep
      state.u.setData(columns, false);
    },

    setViewport: function (state, v) {
      state.u.batch(function () {
        state.u.setScale("x", { min: v.xmin, max: v.xmax });
        if (v.ymin != null && v.ymax != null) {
          state.u.setScale("y", { min: v.ymin, max: v.ymax });
        }
      });
    },

    setSeries: function (state, s) {
      // s.series is 1-based channel idx from R; uPlot series 0 = x,
      // so channel i lives at uPlot idx i -- offsets cancel out
      var opts = {};
      if (s.visible != null) opts.show = s.visible;
      if (s.label   != null) opts.label = s.label;
      state.u.setSeries(s.series, opts);
      // stroke can't change via setSeries; direct poke + redraw
      if (s.color != null) {
        state.u.series[s.series].stroke = function () {
          return s.color;
        };
        state.u.redraw();
      }
    },

    // coordinate bridge for the animation layer
    valToPos: function (state, val, axis) {
      return state.u.valToPos(val, axis || "x");
    },

    posToVal: function (state, px, axis) {
      return state.u.posToVal(px, axis || "x");
    }
  };
})();
