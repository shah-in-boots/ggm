// htmlwidgets calls renderValue(x) with the payload built by gram_plot() in R.
// All real work is delegated to GRAM (gram-adapter-uplot.js).

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
