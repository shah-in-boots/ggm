// Drives Plotly.react from the spec gm_plotly_spec() built in R. plotly is
// declarative, so the spec already is the figure -- traces, axes, grid, the
// gestures allowed -- and this file adds only what R cannot know or do: the
// element's width, the wheel pan, and the report of where the reader has
// moved. The lifecycle and the gesture rules shared with other backends are
// in gram-core.js.
//
// No `applying` flag, unlike the uPlot adapter. Plotly.react never fires
// plotly_relayout (plot_api.js: only plotly_react and plotly_afterplot), so a
// push is silent by construction. The only relayout this file issues is the
// wheel pan, which should be reported. The exact-match check in the handler
// is the belt for a timer that was already pending when a push landed.

(function () {
  "use strict";

  var GRAM = (window.GRAM = window.GRAM || {});
  GRAM.adapters = GRAM.adapters || {};

  // The controller picks an overview tier from the panel width, so it has to
  // be told what that width is; emitting only on a genuine change keeps a
  // resize storm from becoming a re-read storm.
  function measure(state) {
    var width = state.el.clientWidth || 800;
    if (width === state.width) return false;
    state.width = width;
    GRAM.emit(state.el, "width", width);
    return true;
  }

  // The same layout object is handed back on every render. Plotly writes the
  // reader's drag range into it, so a resize re-react keeps their zoom; a
  // push replaces the whole spec, so it wins. Width is measured, not sent:
  // R does not know the element's box.
  function render(state) {
    var spec = state.cfg.spec;
    var layout = Object.assign({}, spec.layout, { width: state.width });
    return Plotly.react(state.el, spec.data, layout, spec.config);
  }

  function drawnRange(state) {
    var axis = state.el._fullLayout && state.el._fullLayout.xaxis;
    if (!axis || !axis.range) return null;
    var min = Number(axis.range[0]);
    var max = Number(axis.range[1]);
    if (!Number.isFinite(min) || !Number.isFinite(max) || max <= min) return null;
    return { min: min, max: max, plotWidth: axis._length || state.width };
  }

  // After a drag-zoom or our own pan settles. The event payload is ignored
  // because its shape depends on the cause (range[0]/[1] keys for a drag,
  // xaxis.range for a relayout call); _fullLayout is always the drawn range.
  function onRelayout(state) {
    window.clearTimeout(state.viewportTimer);
    state.viewportTimer = window.setTimeout(function () {
      var range = drawnRange(state);
      if (!range) return;
      var loaded = state.cfg.window;
      if (range.min === loaded.min && range.max === loaded.max) return;
      GRAM.emit(state.el, "viewport", { xmin: range.min, xmax: range.max });
    }, GRAM.viewportDebounceMs);
  }

  // Plotly's own wheel handler returns before preventDefault when cartesian
  // scrollZoom is off (dragbox.js), so the event reaches the element. Gated
  // on the drag rect so the margins do not pan.
  function onWheel(state, event) {
    var target = event.target;
    if (!target || !target.closest || !target.closest(".nsewdrag")) return;

    var range = drawnRange(state);
    if (!range) return;
    var delta = GRAM.wheelDelta(event, range.plotWidth);
    if (delta === 0) return;

    var span = range.max - range.min;
    var extent = state.cfg.extent;
    if (!(span < extent.max - extent.min)) return;

    var shift = delta / range.plotWidth * span;
    var next = GRAM.clampRangeToExtent(extent, range.min + shift, range.max + shift);
    event.preventDefault();
    Plotly.relayout(state.el, { "xaxis.range": next });
  }

  var adapter = {

    create: function (el, cfg) {
      var state = {
        el: el,
        cfg: cfg,
        width: 0,
        viewportTimer: null,
        wheel: null
      };

      el.innerHTML = "";
      el.classList.add("gram-stack");
      measure(state);
      render(state); // el.on exists synchronously afterwards

      el.on("plotly_relayout", function () { onRelayout(state); });
      state.wheel = function (event) { onWheel(state, event); };
      el.addEventListener("wheel", state.wheel, { passive: false });
      return state;
    },

    destroy: function (state) {
      window.clearTimeout(state.viewportTimer);
      state.el.removeEventListener("wheel", state.wheel);
      Plotly.purge(state.el); // drops the plotly_relayout listener too
      state.el.classList.remove("gram-stack");
      state.el.innerHTML = "";
    },

    // Re-react with the new width rather than Plotly.Plots.resize, which
    // deletes layout.height and adopts the container's css height
    // (plots.js). Height is the spec's; only width follows the box.
    resize: function (state) {
      if (measure(state)) render(state);
    },

    setData: function (state, spec, bounds) {
      state.cfg.spec = spec;
      state.cfg.window = bounds;
      render(state);
    }
  };

  GRAM.adapters.plotly = adapter;
})();
