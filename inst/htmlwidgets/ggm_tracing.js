// ggm_tracing.js -- htmlwidgets binding (thin)
//
// all real work delegated to GGMAnim (ggm-anim.js), which owns the
// anime.js timeline. this file only forwards lifecycle events.

HTMLWidgets.widget({

  name: "ggm_tracing",
  type: "output",

  factory: function (el, width, height) {

    return {

      renderValue: function (x) {
        GGMAnim.create(el, x);
      },

      resize: function (w, h) {
        // svg scales with its viewBox; nothing to recompute
      }
    };
  }
});
