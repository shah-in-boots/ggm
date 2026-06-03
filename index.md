Visualization and interaction layer for cardiac electrophysiology signal
data. 'ggm' (Grammar of Electrograms) builds on the 'EGM' data backend
to view, annotate, and present electrograms. The signal store stays
canonical in 'EGM' (WFDB byte-seek reads); 'ggm' adds windowed access, a
multi-resolution overview, and a declarative grammar for animated and
print-ready figures. Sample index (integer) is the canonical key for
storage and joins, while time (seconds) is the display unit.
