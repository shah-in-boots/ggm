// gram-adapter-uplot.js -- uPlot implementation of adapter contract
//
// Each signal channel owns one uPlot instance. Panels keep independent
// y-scales while sharing x-range and cursor state.

(function () {
  "use strict";

  var GRAM = window.GRAM;
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
  function plotForChannel(state, channelIndex) {
    var at = state.visible.indexOf(channelIndex);
    return at === -1 ? null : state.plots[at];
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

  GRAM.adapters.uplot = {

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

    // Fan aligned columns out to one [x, y] data pair per visible panel. The
    // count checked is the channel total, not the panel count -- panels are
    // only the channels currently switched on.
    setData: function (state, columns) {
      if (columns.length !== state.cfg.columns.length) {
        throw new Error("gram: setData cannot change the channel count");
      }
      // every channel can be switched off at once, leaving nothing to scale
      // the new data against
      if (!state.plots.length) {
        state.cfg.columns = columns;
        return;
      }

      var currentX = state.plots[0].scales.x;
      var range = clampRangeToData(columns[0], currentX.min, currentX.max);

      state.cfg.columns = columns;
      state.syncingScale = true;
      state.plots.forEach(function (plot, position) {
        var channelIndex = state.visible[position];
        plot.setData([columns[0], columns[channelIndex + 1]], false);
        plot.setScale("x", { min: range[0], max: range[1] });
      });
      state.syncingScale = false;
    },

    // visible: 1-based channel indices, matching setSeries and R habits.
    // state.visible is 0-based, so convert on the way in.
    setVisible: function (state, visible) {
      setVisibleChannels(
        state,
        visible.map(function (i) { return i - 1; })
      );
    },

    setViewport: function (state, viewport) {
      setSharedXRange(state, viewport.xmin, viewport.xmax, null);
      if (viewport.ymin != null && viewport.ymax != null) {
        state.plots.forEach(function (plot) {
          plot.setScale("y", { min: viewport.ymin, max: viewport.ymax });
        });
      }
    },

    // NB series.visible is uPlot's per-line toggle *within* a panel, which is
    // not the same thing as setVisible above -- that one adds and removes the
    // panel itself. Use setVisible to put a channel on or off screen.
    setSeries: function (state, series) {
      // series.series is a 1-based channel index, so it has to be mapped
      // through the visible set rather than used as a panel position
      var plot = plotForChannel(state, series.series - 1);
      if (!plot) return;

      var opts = {};
      if (series.visible != null) opts.show = series.visible;
      if (series.label != null) opts.label = series.label;
      plot.setSeries(1, opts);

      if (series.color != null) {
        plot.series[1].stroke = function () {
          return series.color;
        };
        plot.redraw();
      }
    },

    valToPos: function (state, val, axis) {
      return state.plots[0].valToPos(val, axis || "x");
    },

    posToVal: function (state, px, axis) {
      return state.plots[0].posToVal(px, axis || "x");
    }
  };
})();
