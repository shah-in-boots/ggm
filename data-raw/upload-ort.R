# Upload large ORT record files to GitHub Releases via piggyback.
# Run once when files change — too large to include in the package.

# The release/tag must exist before uploading. Run once:
#   piggyback::pb_release_create(repo = "shah-in-boots/ggm", tag = "v0.0.0.9000-data")
# Tag must match the one tests download from (tests/testthat/helper-ggm.R).

piggyback::pb_upload(
  c("data-raw/ort.dat", "data-raw/ort.hea"),
  repo = "shah-in-boots/ggm",
  tag = "v0.0.0.9000-data"
)
