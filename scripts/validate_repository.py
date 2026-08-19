from pathlib import Path
import csv


ROOT = Path(__file__).resolve().parents[1]
REQUIRED = [
    "README.md",
    "BIO211_CW3.Rproj",
    "R/01_taxonomy_alpha.R",
    "data/metadata.txt",
    "data/pollutant.txt",
    "data/species_table.txt",
]


def tab_shape(path: Path) -> tuple[int, int]:
    with path.open(encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.reader(handle, delimiter="\t"))
    if not rows:
        raise AssertionError(f"{path.name} is empty")
    width = len(rows[0])
    if any(len(row) != width for row in rows):
        raise AssertionError(f"{path.name} has ragged rows")
    return len(rows) - 1, width


missing = [name for name in REQUIRED if not (ROOT / name).is_file()]
assert not missing, f"Missing required files: {missing}"

figures = sorted((ROOT / "figures").glob("Figure*.png"))
assert len(figures) == 10, f"Expected 10 result figures, found {len(figures)}"

metadata_rows, metadata_cols = tab_shape(ROOT / "data/metadata.txt")
pollutant_rows, pollutant_cols = tab_shape(ROOT / "data/pollutant.txt")
species_rows, species_cols = tab_shape(ROOT / "data/species_table.txt")
assert metadata_rows == pollutant_rows == species_rows, "Sample counts do not match"
assert metadata_cols >= 5, "Metadata schema is unexpectedly narrow"
assert pollutant_cols == 18, "Exposure table should contain Sample + 17 measurements"
assert species_cols > 100, "Species table is unexpectedly narrow"

for forbidden in (".Rhistory", ".RData", ".Renviron"):
    assert not (ROOT / forbidden).exists(), f"Remove local state file: {forbidden}"

print(
    f"OK: {metadata_rows} samples, {species_cols - 1} taxa, "
    f"{pollutant_cols - 1} exposure measurements and {len(figures)} figures"
)
