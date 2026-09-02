// Each signal channel owns one uPlot instance. Panels keep independent
// y-scales while sharing x-range and cursor state.

(function () {
  "use strict";

  var GRAM = (window.GRAM = window.GRAM || {});
  GRAM.instances = GRAM.instances || {};
  var syncSequence = 0;

  function getScaleKind(cfg) {
    return cfg.scale && cfg.scale.kind || "index";
  }

  function getXAxisLabel(cfg) {
    var kind = getScaleKind(cfg);
    if (kind === "elapsed") return "Time (s)";
    if (kind === "index") return "Sample";
    return null;
  }

  function getPanelWidth(state) {
    return state.el.clientWidth || 800;
  }

  function getPanelHeight(state) {
    return state.cfg.layout && state.cfg.layout.panel_height || 120;
  }

  function resizePanels(state) {
    var width = getPanelWidth(state);
    var height = getPanelHeight(state);
    state.plots.forEach(function (plot) {
      plot.setSize({ width: width, height: height });
    });
  }

  function channelLabel(cfg, channelIndex) {
    var series = cfg.series[channelIndex] || {};
    return series.label || ("ch" + (channelIndex + 1));
  }

  function channelSeries(cfg, channelIndex) {
    var series = cfg.series[channelIndex] || {};
    return {
      label: channelLabel(cfg, channelIndex),
      stroke: series.color || "#111",
      points: { show: false }
    };
  }

  // state.visible holds original channel indices, ascending. Panels are the
  // visible subset, so a panel's position is not its channel number.
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

  function syncScaleFrom(state, source, scaleKey) {
    if (!state.ready || state.syncingScale || scaleKey !== "x") return;
    setSharedXRange(state, source.scales.x.min, source.scales.x.max, source);
  }

  function horizontalWheelDelta(event) {
    if (Math.abs(event.deltaX) > Math.abs(event.deltaY)) return event.deltaX;
    if (event.shiftKey) return event.deltaY;
    return 0;
  }

  function wheelDeltaInPixels(event, plot) {
    var delta = horizontalWheelDelta(event);
    if (event.deltaMode === 1) return delta * 16;
    if (event.deltaMode === 2) return delta * plot.bbox.width;
    return delta;
  }

  function panSharedXRange(state, source, pixelDelta) {
    var x = state.cfg.columns[0];
    var scale = source.scales.x;
    var dataSpan = x[x.length - 1] - x[0];
    var visibleSpan = scale.max - scale.min;

    if (visibleSpan >= dataSpan || !Number.isFinite(visibleSpan)) return false;

    var domainDelta = pixelDelta / source.bbox.width * visibleSpan;
    var range = clampRangeToData(
      x,
      scale.min + domainDelta,
      scale.max + domainDelta
    );
    setSharedXRange(state, range[0], range[1], null);
    return true;
  }

  function addHorizontalPan(state, holder, plot) {
    var overlay = holder.querySelector(".u-over");
    if (!overlay) return;

    var onWheel = function (event) {
      var delta = wheelDeltaInPixels(event, plot);
      if (delta === 0 || !panSharedXRange(state, plot, delta)) return;
      event.preventDefault();
    };

    overlay.addEventListener("wheel", onWheel, { passive: false });
    state.wheelHandlers.push({ element: overlay, handler: onWheel });
  }

  // uPlot fires setSelect when a drag finishes, with state.select in CSS
  // pixels over the plotting area. The conversion to domain units happens
  // here because only the backend knows its own coordinate system; dispatch
  // forwards whatever it is handed.
  function emitSelection(state, plot) {
    var width = plot.select.width;
    if (!(width > 0)) return; // a plain click is not a selection

    GRAM.emit(state.el, "selection", {
      xmin: plot.posToVal(plot.select.left, "x"),
      xmax: plot.posToVal(plot.select.left + width, "x")
    });
  }

  function buildOpts(state, channelIndex, showXAxis) {
    var cfg = state.cfg;
    return {
      width: getPanelWidth(state),
      height: getPanelHeight(state),
      series: [{}, channelSeries(cfg, channelIndex)],
      scales: {
        x: { time: getScaleKind(cfg) === "timestamp" }
      },
      axes: [
        {
          show: showXAxis,
          label: showXAxis ? getXAxisLabel(cfg) : null
        },
        {
          size: 72
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
        }],
        setSelect: [function (plot) {
          emitSelection(state, plot);
        }]
      }
    };
  }

  function createPanel(state, channelIndex, showXAxis) {
    var holder = document.createElement("div");
    var series = state.cfg.series[channelIndex] || {};
    holder.className = "gram-uplot-panel";
    holder.dataset.channel = series.label || ("ch" + (channelIndex + 1));
    state.panels.appendChild(holder);

    var data = [state.cfg.columns[0], state.cfg.columns[channelIndex + 1]];
    var plot = new uPlot(buildOpts(state, channelIndex, showXAxis), data, holder);
    state.holders.push(holder);
    state.plots.push(plot);
    addHorizontalPan(state, holder, plot);
  }

  // --- panel set -------------------------------------------------
  //
  // Which channels are on screen is view state, so a controller decides it
  // and sends setVisible; this file only renders the answer. Dropping a
  // channel rebuilds the panels rather than hiding a series inside one: an
  // emptied panel would still hold its lane, and the x-axis belongs to the
  // last visible panel, so it has to move when the bottom channel goes away.
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
    state.visible.forEach(function (channelIndex, position) {
      createPanel(state, channelIndex, position === state.visible.length - 1);
    });
    state.ready = true;
    // adding panels can introduce a vertical scrollbar; re-measure once the
    // DOM is complete so every plotting area stays aligned
    resizePanels(state);
  }

  // Rebuild for a new visible set, leaving the reader where they were rather
  // than snapping back to the full record.
  function setVisibleChannels(state, visible) {
    var held = state.plots.length
      ? [state.plots[0].scales.x.min, state.plots[0].scales.x.max]
      : null;

    state.visible = visible;
    buildPanels(state);

    if (held && state.plots.length) {
      setSharedXRange(state, held[0], held[1], null);
    }
  }

  function clampRangeToData(x, min, max) {
    var dataMin = x[0];
    var dataMax = x[x.length - 1];
    var dataSpan = dataMax - dataMin;
    var span = max - min;

    if (span >= dataSpan) return [dataMin, dataMax];
    if (min < dataMin) return [dataMin, dataMin + span];
    if (max > dataMax) return [dataMax - span, dataMax];
    return [min, max];
  }

  var adapter = {

    create: function (el, cfg) {
      var channelCount = cfg.columns.length - 1;
      var state = {
        el: el,
        cfg: cfg,
        plots: [],
        holders: [],
        wheelHandlers: [],
        panels: document.createElement("div"),
        // every channel is on screen until a controller says otherwise
        visible: Array.apply(null, { length: channelCount }).map(
          function (_, i) { return i; }
        ),
        syncKey: "gram-uplot-" + (++syncSequence),
        syncingScale: false,
        ready: false
      };

      el.innerHTML = "";
      el.classList.add("gram-uplot-stack");
      state.panels.className = "gram-uplot-panels";
      el.appendChild(state.panels);

      buildPanels(state);
      return state;
    },

    destroy: function (state) {
      teardownPanels(state);
      state.el.classList.remove("gram-uplot-stack");
      state.el.innerHTML = "";
    },

    resize: function (state) {
      resizePanels(state);
    },

    // visible: 1-based channel indices, matching R habits. state.visible is
    // 0-based, so convert on the way in.
    setVisible: function (state, visible) {
      setVisibleChannels(
        state,
        visible.map(function (i) { return i - 1; })
      );
    }
  };


  // --- lifecycle, called by the widget binding --------------------

  GRAM.create = function (el, cfg) {
    GRAM.destroy(el.id); // re-render safety
    GRAM.instances[el.id] = adapter.create(el, cfg);
    return GRAM.instances[el.id];
  };

  GRAM.destroy = function (id) {
    var state = GRAM.instances[id];
    if (!state) return;
    adapter.destroy(state);
    delete GRAM.instances[id];
  };

  GRAM.resize = function (id) {
    var state = GRAM.instances[id];
    if (state) adapter.resize(state);
  };


  // --- shiny ------------------------------------------------------

  // priority "event" is required: without it Shiny drops a value identical to
  // the last one, so selecting the same range twice would go unreported
  GRAM.emit = function (el, event, value) {
    if (!window.Shiny || !el || !el.id) return;
    Shiny.setInputValue(el.id + "_" + event, value, { priority: "event" });
  };

  if (window.Shiny) {
    Shiny.addCustomMessageHandler("gram:set_visible", function (msg) {
      var state = GRAM.instances[msg.id];
      if (state) adapter.setVisible(state, msg.channels);
    });
  }
})();
