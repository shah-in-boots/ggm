// ggm-anim.js -- compiles a tracing spec into an anime.js timeline
//
// the spec from R names selectors, durations, and order. every anime.js
// option -- easing, draw values, timeline offsets -- is chosen here, so
// the R grammar stays stable if this runtime is replaced.
//
// selectors are resolved inside the widget element, so two tracings on
// one page animate their own nodes.

(function () {
  "use strict";

  var GGMAnim = (window.GGMAnim = window.GGMAnim || {});
  GGMAnim.instances = GGMAnim.instances || {};

  // the os-level preference collapses every duration to zero
  var reduceMotion =
    window.matchMedia &&
    window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  function dur(ms) {
    return reduceMotion ? 0 : ms;
  }

  // resolve a selector within one widget instance
  function find(el, selector) {
    return Array.prototype.slice.call(el.querySelectorAll(selector));
  }

  function verbs() {
    var A = window.anime;
    if (!A || !A.createTimeline) {
      throw new Error("ggm: anime.js v4 not loaded");
    }
    return {
      animate: A.animate,
      createTimeline: A.createTimeline,
      stagger: A.stagger,
      svg: A.svg
    };
  }

  // --- chrome ----------------------------------------------------

  function buildControls(el, getTimeline) {
    var bar = document.createElement("div");
    bar.className = "ggm-tracing-controls";

    [
      ["play", "Play", function (tl) { tl.play(); }],
      ["pause", "Pause", function (tl) { tl.pause(); }],
      ["restart", "Restart", function (tl) { tl.restart(); }],
      ["end", "Final frame", function (tl) { tl.complete(); }]
    ].forEach(function (spec) {
      var button = document.createElement("button");
      button.type = "button";
      button.className = "ggm-tracing-button";
      button.setAttribute("data-action", spec[0]);
      button.textContent = spec[1];
      button.addEventListener("click", function () {
        var tl = getTimeline();
        if (tl) spec[2](tl);
      });
      bar.appendChild(button);
    });

    el.appendChild(bar);
  }

  // --- timeline --------------------------------------------------

  // hold every drawable at zero so nothing flashes before playback
  function prime(el, v) {
    var drawn = find(el, ".ggm-trace, .ggm-arrow, .ggm-emph");
    if (drawn.length) {
      v.animate(v.svg.createDrawable(drawn), {
        draw: "0 0",
        duration: 0
      });
    }
  }

  function buildTimeline(el, spec, autoplay) {
    var v = verbs();
    prime(el, v);

    var tl = v.createTimeline({
      autoplay: autoplay,
      defaults: { ease: "inOutQuad" }
    });

    spec.ops.forEach(function (op) {
      var targets = find(el, op.targets);
      if (!targets.length) return;

      if (op.type === "reveal") {
        tl.add(v.svg.createDrawable(targets), {
          draw: ["0 0", "0 1"],
          duration: dur(op.duration),
          delay: v.stagger(dur(op.stagger))
        });
      } else if (op.type === "arrow" || op.type === "emphasize") {
        tl.add(
          v.svg.createDrawable(targets),
          { draw: ["0 0", "0 1"], duration: dur(op.duration) },
          "-=150"
        );
      }

      if (op.label) {
        var labels = find(el, op.label);
        if (labels.length) {
          tl.add(
            labels,
            { opacity: [0, 1], duration: dur(250), ease: "outExpo" },
            "-=" + dur(150)
          );
        }
      }
    });

    return tl;
  }

  // --- lifecycle -------------------------------------------------

  GGMAnim.create = function (el, cfg) {
    GGMAnim.destroy(el.id);

    el.innerHTML = "";
    el.classList.add("ggm-tracing-holder");

    var stage = document.createElement("div");
    stage.className = "ggm-tracing-stage";
    stage.innerHTML = cfg.spec.svg;
    el.appendChild(stage);

    var instance = { timeline: null };
    if (cfg.controls) {
      buildControls(el, function () {
        return instance.timeline;
      });
    }

    instance.timeline = buildTimeline(el, cfg.spec, cfg.autoplay);
    GGMAnim.instances[el.id] = instance;
    return instance;
  };

  GGMAnim.destroy = function (id) {
    var instance = GGMAnim.instances[id];
    if (!instance) return;
    if (instance.timeline) {
      if (typeof instance.timeline.revert === "function") {
        instance.timeline.revert();
      } else {
        instance.timeline.pause();
      }
    }
    delete GGMAnim.instances[id];
  };
})();
