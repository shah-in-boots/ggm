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

  function channelSeries(cfg, channelIndex) {
    var series = cfg.series[channelIndex] || {};
    return {
      label: series.label || ("ch" + (channelIndex + 1)),
      stroke: series.color || "#111",
      points: { show: false }
    };
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
      var state = {
        el: el,
        cfg: cfg,
        plots: [],
        holders: [],
        wheelHandlers: [],
        panels: document.createElement("div"),
        syncKey: "gram-uplot-" + (++syncSequence),
        syncingScale: false,
        ready: false
      };

      el.innerHTML = "";
      el.classList.add("gram-uplot-stack");
      state.panels.className = "gram-uplot-panels";
      el.appendChild(state.panels);

      var channelCount = cfg.columns.length - 1;
      for (var i = 0; i < channelCount; i++) {
        createPanel(state, i, i === channelCount - 1);
      }
      state.ready = true;
      // Adding enough panels can introduce a vertical scrollbar. Re-measure
      // once after the DOM is complete so every plotting area stays aligned.
      resizePanels(state);

      return state;
    },

    destroy: function (state) {
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
      state.el.classList.remove("gram-uplot-stack");
      state.el.innerHTML = "";
    },

    resize: function (state) {
      resizePanels(state);
    },

    // Fan aligned columns out to one [x, y] data pair per channel panel.
    setData: function (state, columns) {
      if (columns.length - 1 !== state.plots.length) {
        throw new Error("gram: setData cannot change the channel count");
      }

      var currentX = state.plots[0].scales.x;
      var range = clampRangeToData(columns[0], currentX.min, currentX.max);

      state.syncingScale = true;
      state.plots.forEach(function (plot, i) {
        plot.setData([columns[0], columns[i + 1]], false);
        plot.setScale("x", { min: range[0], max: range[1] });
      });
      state.syncingScale = false;
      state.cfg.columns = columns;
    },

    setViewport: function (state, viewport) {
      setSharedXRange(state, viewport.xmin, viewport.xmax, null);
      if (viewport.ymin != null && viewport.ymax != null) {
        state.plots.forEach(function (plot) {
          plot.setScale("y", { min: viewport.ymin, max: viewport.ymax });
        });
      }
    },

    setSeries: function (state, series) {
      var plot = state.plots[series.series - 1];
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
