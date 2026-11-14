#!/usr/bin/env python3
"""Pass/fail for a GdUnit4 run, read from its JUnit report rather than Godot's exit code.

Godot exits 134 at shutdown after a green gdUnit run (a known, pre-existing quirk), so the
exit code alone can't be trusted. This passes only when the run wrote exactly one
results.xml with at least one test and no failures or errors, and Godot's exit code is 0
or the known 134.

usage: gdunit_verdict.py REPORT_DIR GODOT_EXIT_CODE
"""
import pathlib
import sys
import xml.etree.ElementTree as ET


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    report_dir = pathlib.Path(sys.argv[1])
    exit_code = int(sys.argv[2])

    reports = sorted(report_dir.glob("**/results.xml"))
    if len(reports) != 1:
        print(f"::error::expected one gdUnit results.xml under {report_dir}, found {len(reports)}")
        return 1
    root = ET.parse(reports[0]).getroot()
    cases = root.findall(".//testcase")
    failed = [c for c in cases if c.find("failure") is not None or c.find("error") is not None]
    skipped = [c for c in cases if c.find("skipped") is not None]
    print(f"gdUnit: {len(cases)} tests, {len(failed)} failed, {len(skipped)} skipped "
          f"(Godot exit code {exit_code}, report {reports[0]})")
    for case in failed:
        print(f"::error::FAILED {case.get('classname')}.{case.get('name')}")

    if not cases:
        print("::error::gdUnit ran no tests")
        return 1
    if failed:
        return 1
    if exit_code not in (0, 134):
        print(f"::error::all tests passed but Godot exited {exit_code} (only 0 or 134 are expected)")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
