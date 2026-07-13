record_dir <- system.file("extdata", package = "ggm")
study <- open_study("bard-egm", record_dir)
build_overview(study)

explore_study(
  study,
  channels = c("I", "ABL D", "HIS D", "RV 1-2"),
  annotator = "qrs"
)

# Large-study trial:
# record_dir <- cache_study_data("ort")
# study <- open_study("ort", record_dir)
# build_overview(study)
# explore_study(study, channels = c("I", "HRA D", "HIS D", "RVA D"))
