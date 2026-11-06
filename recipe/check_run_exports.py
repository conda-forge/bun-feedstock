"""Check that bun's run_exports name the same packages as its run dependencies.

`bun build --compile` copies the bun executable into its output, so a compiled
program needs the shared libraries bun itself is linked against. The
run_exports in recipe.yaml hand those to packages that have bun in host. That
list is written by hand, while bun's own run dependencies are derived from
the run_exports of its build and host requirements. This test fails when the
two name different packages, which is what happens when a dependency is
unvendored, or vendored again, without updating run_exports.
"""

import json
import os
import sys
from pathlib import Path

# bun's own code links the MSVC runtime statically (/MT). These come from the
# run_exports of the vs2022 compiler package and a compiled program doesn't
# need them; the DLLs it loads bring their own dependencies.
NOT_EXPORTED = {"ucrt", "vc", "vc14_runtime"}

name = os.environ["PKG_NAME"]
records = [
    json.loads(path.read_text())
    for path in (Path(os.environ["PREFIX"]) / "conda-meta").glob(f"{name}-*.json")
]
(record,) = [record for record in records if record["name"] == name]

depends = {spec.split()[0]: spec for spec in record["depends"]}

# run_exports aren't part of the installed record, only of the package itself
package_dir = record.get("extracted_package_dir")
if not package_dir:
    sys.exit("cannot find the extracted package: no extracted_package_dir in " + name + "'s conda-meta record")
run_exports_json = Path(package_dir) / "info" / "run_exports.json"
weak = json.loads(run_exports_json.read_text()).get("weak", []) if run_exports_json.exists() else []
exports = {spec.split()[0]: spec for spec in weak}

print("run dependencies:", *sorted(depends.values()), sep="\n  ")
print("run_exports:", *sorted(exports.values()), sep="\n  ")

missing = sorted(set(depends) - set(exports) - NOT_EXPORTED)
extra = sorted(set(exports) - set(depends))
for package in sorted(set(depends) & set(exports)):
    if depends[package] != exports[package]:
        print(f"note: bounds differ: run dependency '{depends[package]}', run_export '{exports[package]}'")
if missing or extra:
    sys.exit(
        "run_exports in recipe.yaml are out of date.\n"
        f"  run dependencies that are not exported: {missing}\n"
        f"  exported packages that are not run dependencies: {extra}"
    )
print("run_exports match the run dependencies")
