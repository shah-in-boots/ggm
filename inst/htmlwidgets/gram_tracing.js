// gram_tracing.js -- htmlwidgets binding (thin)
//
// all real work delegated to GRAMAnim (gram-anim.js), which owns the
// anime.js timeline. this file only forwards lifecycle events.

HTMLWidgets.widget({

  name: "gram_tracing",
  type: "output",

  factory: function (el, width, height) {

    return {

      renderValue: function (x) {
        GRAMAnim.create(el, x);
      },

      resize: function (w, h) {
        // svg scales with its viewBox; nothing to recompute
      }
    };
  }
});
