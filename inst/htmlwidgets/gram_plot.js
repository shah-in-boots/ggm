// gram_plot.js -- htmlwidgets binding (thin)
//
// htmlwidgets calls renderValue(x) with the payload built by
// gram_plot() in R. all real work delegated to GRAM (dispatch).
// resize is wired by htmlwidgets automatically.

HTMLWidgets.widget({

  name: "gram_plot",   // must match R widget name + yaml filename
  type: "output",

  factory: function (el, width, height) {

    return {

      // fires on first render AND every reactive re-render;
      // GRAM.create handles teardown of any previous instance
      renderValue: function (x) {
        GRAM.create(el, x);
      },

      resize: function (w, h) {
        GRAM.resize(el.id, w, h);
      }
    };
  }
});
