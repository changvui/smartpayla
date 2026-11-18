"""Report what a partner zip adds to this repository, without merging blindly.

Kerry works from zip files, not git. Each zip is a snapshot of the repository at
whatever commit he downloaded, plus his own edits. Taking a whole file from his
zip can therefore silently revert newer work in this repository: his copy of a
file he never touched is simply an older version of it.

This script answers the only question that matters - *which of his files contain
code that exists nowhere in this repository* - by listing the top-level symbols
that appear only in his copy.

Usage:
    python tools/kerry_zip_report.py <partner.zip> [repo-root]

Exit code is 0 even when differences are found; read the report.
"""
import re
import sys
import tempfile
import zipfile
from pathlib import Path

SYMBOLS = [
    re.compile(r"^(?:abstract\s+)?class\s+(\w+)", re.M),
    re.compile(r"^enum\s+(\w+)", re.M),
    re.compile(r"^mixin\s+(\w+)", re.M),
    re.compile(r"^extension\s+(\w+)", re.M),
    re.compile(r"^typedef\s+(\w+)", re.M),
    re.compile(
        r"^(?:Future<[^>\n]*>|Future|void|String|bool|double|int|num|Widget|"
        r"IconData|Color|List<[^>\n]*>|Map<[^>\n]*>|Set<[^>\n]*>|"
        r"\(\{[^}\n]*\}\)|\([^)\n]*\))\s+(\w+)\s*\(",
        re.M,
    ),
    re.compile(r"^const\s+(?:List|Map|Set)<[^>\n]*>\s+(\w+)", re.M),
    re.compile(r"^final\s+(\w+)\s*=", re.M),
]


def symbols(text):
    found = set()
    for pattern in SYMBOLS:
        for match in pattern.finditer(text):
            found.add(match.group(1))
    return found


def lib_root(base):
    for candidate in (base / "lib", *base.glob("*/lib")):
        if candidate.is_dir():
            return candidate
    return None


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1

    zip_path = Path(sys.argv[1]).expanduser()
    repo = Path(sys.argv[2]) if len(sys.argv) > 2 else Path.cwd()
    if not zip_path.is_file():
        print(f"no such zip: {zip_path}")
        return 1

    with tempfile.TemporaryDirectory() as tmp:
        with zipfile.ZipFile(zip_path) as archive:
            archive.extractall(tmp)
        their_lib = lib_root(Path(tmp))
        if their_lib is None:
            print("the zip has no lib/ directory")
            return 1
        ours_lib = repo / "lib"
        if not ours_lib.is_dir():
            print(f"no lib/ under {repo}")
            return 1

        theirs = {p.relative_to(their_lib) for p in their_lib.rglob("*.dart")}
        ours = {p.relative_to(ours_lib) for p in ours_lib.rglob("*.dart")}

        print(f"zip : {zip_path.name}")
        print(f"repo: {repo}")
        print(f"files: theirs {len(theirs)}, ours {len(ours)}\n")

        new_files = sorted(theirs - ours)
        missing = sorted(ours - theirs)

        if new_files:
            print("FILES ONLY IN HIS ZIP (safe to add)")
            for name in new_files:
                print(f"  + {name}")
            print()

        if missing:
            print("FILES ONLY IN THIS REPO (his zip is older; keep ours)")
            for name in missing:
                print(f"  - {name}")
            print()

        interesting = []
        identical = 0
        stale = []
        for name in sorted(theirs & ours):
            his_text = (their_lib / name).read_text(encoding="utf-8", errors="replace")
            our_text = (ours_lib / name).read_text(encoding="utf-8", errors="replace")
            if his_text == our_text:
                identical += 1
                continue
            his_only = symbols(his_text) - symbols(our_text)
            our_only = symbols(our_text) - symbols(his_text)
            if his_only:
                interesting.append((name, sorted(his_only), sorted(our_only)))
            else:
                stale.append(name)

        print(f"identical: {identical} file(s)")
        if stale:
            print(
                f"differs but adds nothing new: {len(stale)} file(s) "
                "(his copy is older - do NOT overwrite)"
            )
            for name in stale:
                print(f"  = {name}")
            print()

        if interesting:
            print("FILES WITH CODE THAT DOES NOT EXIST HERE (review, then merge)")
            for name, his_only, our_only in interesting:
                print(f"  * {name}")
                print(f"      only in his zip: {', '.join(his_only[:12])}")
                if our_only:
                    print(f"      only here      : {', '.join(our_only[:12])}")
            print()
        else:
            print("No file in his zip introduces a symbol that is missing here.")

        print(
            "Rule of thumb: add the '+' files, review the '*' files by hand, "
            "and ignore the '=' files."
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
