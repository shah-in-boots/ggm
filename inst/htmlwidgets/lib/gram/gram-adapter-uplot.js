// Drives uPlot from the spec gm_build_uplot_spec() built in R: one uPlot instance
// per panel, independent y-scales, one shared x-range and cursor.
//
// uPlot is imperative, so R could only send what serialises -- the per-panel
// data, labels and strokes, the axis label, the sizes. Everything that is a
// function lives here: the hooks that keep the panels in step, the cursor
// sync, the wheel pan, and the rebuild. The lifecycle and the gesture rules
// shared with other backends are in gram-core.js.
//
// Every panel carries its own x, because an overview tier reports each
// channel's extrema at the samples they actually fell on, so the per-channel
// vectors have different lengths. Panels are therefore drawn against
// cfg.window rather than against their own extents -- without that they would
// each autoscale to a slightly different range and the stack would lose its
// alignment. Panning clamps to cfg.extent, the whole record.

(function () {
  "use strict";

  var GRAM = (window.GRAM = window.GRAM || {});
  GRAM.adapters = GRAM.adapters || {};
  var syncSequence = 0;

  function getPanelWidth(state) {
    return state.el.clientWidth || 800;
  }

  function getPanelHeight(state) {
    return state.cfg.spec.panel_height || 120;
  }

  // The controller picks an overview tier from the panel width, so it has to
  // be told what that width is. Emitting only on a genuine change keeps a
  // resize storm from becoming a re-read storm, and terminates the loop the
  // reply would otherwise start: a push rebuilds the panels, which measures
  // the same width again and says nothing.
  function resizePanels(state) {
    var width = getPanelWidth(state);
    var height = getPanelHeight(state);
    state.plots.forEach(function (plot) {
      plot.setSize({ width: width, height: height });
    });

    if (state.width !== width) {
      state.width = width;
      GRAM.emit(state.el, "width", width);
    }
  }

  function scalesDiffer(scale, min, max) {
    return scale.min !== min || scale.max !== max;
  }

  function setSharedXRange(state, min, max, source) {
    if (!Number.isFinite(min) || !Number.isFinite(max) || max <= min) return;

    state.syncingScale = true;
    state.plots.forEach(function (plot) {
      if (plot !== source && scalesDiffer(plot.scales.x, min, max)) {
        plot.setScale("x", { min: min, max: max });
      }
    });
    state.syncingScale = false;
  }

  // Zoom (a drag release) and pan (the wheel) both end in setScale, so one
  // debounced request covers both: the controller is told the range wanted and
  // answers with whatever tier fits it. state.applying is what stops a reply
  // from being read as a new request -- setData ends in setSharedXRange, which
  // fires setScale, which would ask again forever.
  function requestViewport(state) {
    if (state.applying || !state.ready || state.plots.length === 0) return;

    var scale = state.plots[0].scales.x;
    if (!Number.isFinite(scale.min) || !Number.isFinite(scale.max)) return;

    // uPlot's own cursor.sync propagates a setScale of its own after a push
    // has finished applying, which would ask for the range just delivered and
    // buy a second read of it. buildPanels sets the scale to cfg.window
    // verbatim, so an exact match means nothing has moved since.
    var loaded = state.cfg.window;
    if (scale.min === loaded.min && scale.max === loaded.max) return;

    GRAM.emit(state.el, "viewport", { xmin: scale.min, xmax: scale.max });
  }

  function scheduleViewportRequest(state) {
    if (state.applying) return;
    window.clearTimeout(state.viewportTimer);
    state.viewportTimer = window.setTimeout(function () {
      requestViewport(state);
    }, GRAM.viewportDebounceMs);
  }

  function syncScaleFrom(state, source, scaleKey) {
    if (!state.ready || state.syncingScale || scaleKey !== "x") return;
    setSharedXRange(state, source.scales.x.min, source.scales.x.max, source);
    scheduleViewportRequest(state);
  }

  function panSharedXRange(state, source, pixelDelta) {
    var extent = state.cfg.extent;
    var scale = source.scales.x;
    var visibleSpan = scale.max - scale.min;

    if (visibleSpan >= extent.max - extent.min || !Number.isFinite(visibleSpan)) {
      return false;
    }

    var domainDelta = pixelDelta / source.bbox.width * visibleSpan;
    var range = GRAM.clampRangeToExtent(
      extent,
      scale.min + domainDelta,
      scale.max + domainDelta
    );
    setSharedXRange(state, range[0], range[1], null);
    scheduleViewportRequest(state);
    return true;
  }

  function addHorizontalPan(state, holder, plot) {
    var overlay = holder.querySelector(".u-over");
    if (!overlay) return;

    var onWheel = function (event) {
      var delta = GRAM.wheelDelta(event, plot.bbox.width);
      if (delta === 0 || !panSharedXRange(state, plot, delta)) return;
      event.preventDefault();
    };

    overlay.addEventListener("wheel", onWheel, { passive: false });
    state.wheelHandlers.push({ element: overlay, handler: onWheel });
  }

  function buildOpts(state, panel, showXAxis) {
    var spec = state.cfg.spec;
    return {
      width: getPanelWidth(state),
      height: getPanelHeight(state),
      series: [
        {},
        { label: panel.label, stroke: panel.stroke, points: { show: false } }
      ],
      scales: {
        x: { time: !!spec.x_is_time }
      },
      axes: [
        {
          show: showXAxis,
          label: showXAxis ? spec.x_axis_label : null
        },
        {
          size: spec.y_axis_size || 72
        }
      ],
      cursor: {
        drag: { x: true, y: false },
        sync: {
          key: state.syncKey,
          setSeries: false,
          scales: ["x", null]
        }
      },
      hooks: {
        setScale: [function (plot, scaleKey) {
          syncScaleFrom(state, plot, scaleKey);
        }]
      }
    };
  }

  function createPanel(state, panel, showXAxis) {
    var holder = document.createElement("div");
    holder.className = "gram-uplot-panel";
    holder.dataset.channel = panel.label;
    state.panels.appendChild(holder);

    var plot = new uPlot(buildOpts(state, panel, showXAxis), [panel.x, panel.y], holder);
    state.holders.push(holder);
    state.plots.push(plot);
    addHorizontalPan(state, holder, plot);
  }

  // --- panel set -------------------------------------------------
  //
  // Which channels are on screen is a controller decision, and the controller
  // is R: it pushes a spec holding only the panels to draw. This file draws
  // every panel it is handed, and the x-axis belongs to the last one.
  // Rebuilding a handful of uPlots over a viewport-sized window is cheap, and
  // it keeps one code path for both first render and every later change.

  function teardownPanels(state) {
    state.ready = false;
    state.wheelHandlers.forEach(function (entry) {
      entry.element.removeEventListener("wheel", entry.handler);
    });
    state.plots.forEach(function (plot) {
      plot.destroy();
    });
    state.plots = [];
    state.holders = [];
    state.wheelHandlers = [];
    state.panels.innerHTML = "";
  }

  function buildPanels(state) {
    teardownPanels(state);
    var panels = state.cfg.spec.panels;
    panels.forEach(function (panel, position) {
      createPanel(state, panel, position === panels.length - 1);
    });
    state.ready = true;
    // adding panels can introduce a vertical scrollbar; re-measure once the
    // DOM is complete so every plotting area stays aligned
    resizePanels(state);
    // panels autoscale x to their own data, which differs per channel on an
    // overview tier; the loaded window is the only range they share
    setSharedXRange(state, state.cfg.window.min, state.cfg.window.max, null);
  }

  var adapter = {

    create: function (el, cfg) {
      var state = {
        el: el,
        cfg: cfg,
        plots: [],
        holders: [],
        wheelHandlers: [],
        panels: document.createElement("div"),
        syncKey: "gram-uplot-" + (++syncSequence),
        syncingScale: false,
        applying: false,
        viewportTimer: null,
        width: 0,
        ready: false
      };

      el.innerHTML = "";
      el.classList.add("gram-stack");
      state.panels.className = "gram-uplot-panels";
      el.appendChild(state.panels);

      buildPanels(state);
      return state;
    },

    destroy: function (state) {
      window.clearTimeout(state.viewportTimer);
      teardownPanels(state);
      state.el.classList.remove("gram-stack");
      state.el.innerHTML = "";
    },

    resize: function (state) {
      resizePanels(state);
    },

    // A full rebuild rather than plot.setData(). uPlot's setData either
    // autoscales x to the panel's own extent, which is wrong when every panel
    // holds a different one, or skips the commit entirely and leaves the new
    // data undrawn until something else redraws. buildPanels is already this
    // file's one path for every change.
    //
    // ponytail: full rebuild per push; per-plot setData if 27 panels measure janky
    setData: function (state, spec, bounds) {
      state.applying = true;
      state.cfg.spec = spec;
      state.cfg.window = bounds;
      buildPanels(state);
      state.applying = false;
    }
  };

  GRAM.adapters.uplot = adapter;
})();
