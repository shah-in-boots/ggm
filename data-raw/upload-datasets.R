# Upload large ORT record files to GitHub Releases via piggyback.
# Run once when files change — too large to include in the package.

# The release/tag must exist before uploading. Run once:
#   piggyback::pb_release_create(repo = "shah-in-boots/gram", tag = "v0.0.0.9000-data")
# Tag must match the one cache_study_data() pulls from, in R/datasets.R.
# The test suite does not download it -- it runs on the bundled bard-egm
# record instead, so no test needs the network.

piggyback::pb_upload(
  c("data-raw/ort.dat", "data-raw/ort.hea"),
  repo = "shah-in-boots/gram",
  tag = "v0.0.0.9000-data"
)
