// ggm_plot.js -- htmlwidgets binding (thin)
//
// htmlwidgets calls renderValue(x) with the payload built by
// ggm_plot() in R. all real work delegated to GGM (dispatch).
// resize is wired by htmlwidgets automatically.

HTMLWidgets.widget({

  name: "ggm_plot",   // must match R widget name + yaml filename
  type: "output",

  factory: function (el, width, height) {

    return {

      // fires on first render AND every reactive re-render;
      // GGM.create handles teardown of any previous instance
      renderValue: function (x) {
        GGM.create(el, x);
      },

      resize: function (w, h) {
        GGM.resize(el.id, w, h);
      }
    };
  }
});
