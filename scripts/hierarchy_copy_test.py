#!/usr/bin/env python3
"""Tests the copies of BW's hierarchies (docs/next-steps.md, Now: time-independent BW hierarchies, part one) on the
clinic demo: ZZXXMLA1_CL_BW_HIERARCHY_COPY (run with sapcli class execute) creates the tables of ZCLDIAG, ZCLPAT and
ZCLSERV if they have none, copies each of their plain hierarchies (refilled if BW's is newer) and prints per hierarchy
its tables, version, whether it was refilled, the SIDs of its All member and of its not-assigned node, whether that is
shown, its node rows, inner nodes, closure rows, depth, the values of the All member and of the not-assigned node.

The class checks every copy against BW itself (a node's distinct values against BW's rows and correction factors) and
refuses what olap4abap refuses; here a second run must refill nothing, and per hierarchy the copy is compared with BW's
own MDX (ZZXXMLA1_CL_BW_HIERARCHY_PROBE, as scripts/bw_hierarchy_test.py asks it): BW shows a member per node row but
the virtual root before the not-assigned node REST_H, and the not-assigned node, where BW shows it, with as many
values as the copy reads live.

    "$LOCALAPPDATA/pipx/pipx/venvs/sapcli/Scripts/python.exe" scripts/hierarchy_copy_test.py
"""
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bw_hierarchy_test  # noqa: E402

COPY = "ZZXXMLA1_CL_BW_HIERARCHY_COPY"
FIELDS = ["characteristic", "hierarchy", "status", "node_table", "closure_table", "version", "refilled", "root_sid",
          "rest_top_sid", "rest_shown", "nodes", "inner_nodes", "closure", "depth", "all_values", "rest_values",
          "microseconds"]


def copies():
    """Runs the copy class; returns its rows by (characteristic, hierarchy)."""
    e = bw_hierarchy_test.env()
    command = ["sapcli", "--ashost", e["SAP_ASHOST"], "--client", e["SAP_CLIENT"], "--user", e["SAP_USER"]]
    if e.get("SAP_PORT"):
        command += ["--port", e["SAP_PORT"]]
    if e.get("SAP_USE_SSL", "false") != "true":
        command += ["--no-ssl"]
    command += ["class", "execute", COPY]
    output = subprocess.run(command, capture_output=True, text=True, encoding="utf-8",
                            env={**os.environ, "SAP_PASSWORD": e["SAP_PASSWORD"]})
    if output.returncode != 0 or "\t" not in output.stdout:
        sys.exit(f"{COPY} failed: {output.stdout[-2000:]}{output.stderr[-2000:]}")
    rows = {}
    for line in output.stdout.splitlines():
        fields = line.split("\t")
        if len(fields) < 3:
            continue
        row = dict(zip(FIELDS, fields))
        rows[(row["characteristic"], row["hierarchy"])] = row
    return rows


def main():
    failures = []
    first = copies()
    second = copies()
    _, bw = bw_hierarchy_test.bw_members()
    for key, row in sorted(second.items()):
        name = " ".join(key)
        if row["status"] != "OK":
            failures.append(f"{name}: {row['status']} {row.get('node_table', '')}")
            continue
        if row["refilled"]:
            failures.append(f"{name}: refilled again although BW's hierarchy did not change")
        if first[key].get("version") not in (row["version"],) and not first[key].get("refilled"):
            failures.append(f"{name}: version {first[key].get('version')} became {row['version']}")
        members = bw.get(key)
        if members is None:
            print(f"{name}: OK, {row['nodes']} node rows, {row['closure']} closure rows (no member from BW's MDX)")
            continue
        rest = next((i for i, m in enumerate(members) if m["kind"] == "1HIER_REST"), None)
        tree = members if rest is None else members[:rest]
        # BW has no All member: the copy's virtual root is its extra node row
        if len(tree) != int(row["nodes"]) - 1:
            failures.append(f"{name}: {int(row['nodes']) - 1} nodes but the root, BW's MDX shows {len(tree)}")
        if (rest is not None) != (row["rest_shown"] == "X"):
            failures.append(f"{name}: not-assigned node shown {row['rest_shown'] == 'X'}, by BW {rest is not None}")
        elif rest is not None and members[rest]["children"] != int(row["rest_values"]):
            failures.append(f"{name}: {row['rest_values']} not-assigned values, BW's MDX shows "
                            f"{members[rest]['children']}")
        print(f"{name}: {row['nodes']} node rows, {row['inner_nodes']} inner, {row['closure']} closure rows, "
              f"depth {row['depth']}, All {row['all_values']} values, not assigned "
              f"{row['rest_values'] if row['rest_shown'] == 'X' else 'suppressed'}, {row['microseconds']} us")
    for failure in failures:
        print(f"FAIL {failure}")
    print(f"{len(second) - len({f.split(':')[0] for f in failures})} of {len(second)} hierarchies pass")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
