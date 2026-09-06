// Each signal channel owns one uPlot instance. Panels keep independent
// y-scales while sharing x-range and cursor state.
//
// Every panel carries its own x, because an overview tier reports each
// channel's extrema at the samples they actually fell on, so the per-channel
// vectors have different lengths. Panels are therefore drawn against
// cfg.window rather than against their own extents -- without that they would
// each autoscale to a slightly different range and the stack would lose its
// alignment. Panning clamps to cfg.extent, the whole record, so a reader can
// pan past what is loaded; the canvas is briefly empty there until the
// controller answers with the next window.

(function () {
  "use strict";

  var GRAM = (window.GRAM = window.GRAM || {});
  GRAM.instances = GRAM.instances || {};
  GRAM.adapters = GRAM.adapters || {};
  var syncSequence = 0;
  var viewportDebounceMs = 150;

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

  function channelLabel(cfg, channelIndex) {
    var panel = cfg.panels[channelIndex] || {};
    return panel.label || ("ch" + (channelIndex + 1));
  }

  function channelSeries(cfg, channelIndex) {
    var panel = cfg.panels[channelIndex] || {};
    return {
      label: channelLabel(cfg, channelIndex),
      stroke: panel.color || "#111",
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
    }, viewportDebounceMs);
  }

  function syncScaleFrom(state, source, scaleKey) {
    if (!state.ready || state.syncingScale || scaleKey !== "x") return;
    setSharedXRange(state, source.scales.x.min, source.scales.x.max, source);
    scheduleViewportRequest(state);
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

  function clampRangeToExtent(extent, min, max) {
    var span = max - min;

    if (span >= extent.max - extent.min) return [extent.min, extent.max];
    if (min < extent.min) return [extent.min, extent.min + span];
    if (max > extent.max) return [extent.max - span, extent.max];
    return [min, max];
  }

  function panSharedXRange(state, source, pixelDelta) {
    var extent = state.cfg.extent;
    var scale = source.scales.x;
    var visibleSpan = scale.max - scale.min;

    if (visibleSpan >= extent.max - extent.min || !Number.isFinite(visibleSpan)) {
      return false;
    }

    var domainDelta = pixelDelta / source.bbox.width * visibleSpan;
    var range = clampRangeToExtent(
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
    var panel = state.cfg.panels[channelIndex] || {};
    var holder = document.createElement("div");
    holder.className = "gram-uplot-panel";
    holder.dataset.channel = channelLabel(state.cfg, channelIndex);
    state.panels.appendChild(holder);

    var data = [panel.x, panel.y];
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
    // panels autoscale x to their own data, which differs per channel on an
    // overview tier; the loaded window is the only range they share
    setSharedXRange(state, state.cfg.window.min, state.cfg.window.max, null);
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

  var adapter = {

    create: function (el, cfg) {
      var state = {
        el: el,
        cfg: cfg,
        plots: [],
        holders: [],
        wheelHandlers: [],
        panels: document.createElement("div"),
        // every channel is on screen until a controller says otherwise
        visible: cfg.panels.map(function (_, i) { return i; }),
        syncKey: "gram-uplot-" + (++syncSequence),
        syncingScale: false,
        applying: false,
        viewportTimer: null,
        width: 0,
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
      window.clearTimeout(state.viewportTimer);
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
    },

    // A full rebuild rather than plot.setData(). uPlot's setData either
    // autoscales x to the panel's own extent, which is wrong when every panel
    // holds a different one, or skips the commit entirely and leaves the new
    // data undrawn until something else redraws. buildPanels is already this
    // file's one path for every change.
    //
    // ponytail: full rebuild per push; per-plot setData if 27 panels measure janky
    setData: function (state, panels, bounds) {
      state.applying = true;
      state.cfg.panels = panels;
      state.cfg.window = bounds;
      // a push normally carries every channel, so the visible subset survives;
      // drop only indices a shorter payload no longer has
      state.visible = state.visible.filter(function (i) {
        return i < panels.length;
      });
      if (state.visible.length === 0) {
        state.visible = panels.map(function (_, i) { return i; });
      }
      buildPanels(state);
      state.applying = false;
    }
  };

  GRAM.adapters.uplot = adapter;


  // --- lifecycle, called by the widget binding --------------------
  //
  // The backend is named in the payload and resolved here, so a second
  // renderer is another entry in GRAM.adapters rather than another htmlwidget
  // with its own binding and dependency set. An adapter has to provide
  // create/destroy/resize/setVisible/setData.

  GRAM.create = function (el, cfg) {
    var backend = GRAM.adapters[cfg.backend || "uplot"];
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
    Shiny.addCustomMessageHandler("gram:set_visible", function (msg) {
      var instance = GRAM.instances[msg.id];
      if (instance) instance.backend.setVisible(instance.state, msg.channels);
    });

    Shiny.addCustomMessageHandler("gram:set_data", function (msg) {
      var instance = GRAM.instances[msg.id];
      if (instance) {
        instance.backend.setData(instance.state, msg.panels, msg.window);
      }
    });
  }
})();
