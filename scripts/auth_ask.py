#!/usr/bin/env python3
"""Asks BW's own MDX given statements with the analysis authorizations of the test users (GET auth/probe?mdx=..., the
probe's run_statements: BW's "Execute as Other User" at a key date), for questions the probe's kinds of query do not ask
(docs/clinic-demo.md, Probing BW's authorizations on them). Prints per user, key date and statement BW's status (OK,
EMPTY, NO AUTH, UNKNOWN, ERROR), its message and the members of its rows; --json writes the answers to a file.

A statement may use short forms on $ZCLVISITA's ZCLDOC hierarchies:
    {H}            [ZCLDOC<pad 30>ZCLDOC_ORG<pad 30>001], the hierarchy (--hierarchy, --version change it)
    {N:GP}         a text node: [GP<pad 32>0HIER_NODE<pad 30>] under {H}
    {L:001}        a leaf: [001] under {H}
    {F:001}        the flat value [ZCLDOC].[001]
    {M}            [Measures].[ZCLVISNO]
A line of the statements file that starts with # is a comment.

    python scripts/auth_ask.py --scenario H2LEAF --scenario FULL --key-date 9999-12-31 --file questions.mdx
    python scripts/auth_ask.py --scenario H2LEAF "SELECT {{M}} ON 0, {{N:GP}.Children} ON 1 FROM [$ZCLVISITA]"
"""
import argparse
import json
import re
import sys

from auth_probe import ROOT, Session, read_env  # noqa: F401  (ROOT for callers)


def expand(statement, hierarchy, version, characteristic="ZCLDOC"):
    unique = f"[{characteristic:<30}{hierarchy:<30}{version}]"
    statement = statement.replace("{H}", unique).replace("{M}", "[Measures].[ZCLVISNO]")
    statement = re.sub(r"\{N:([^}]+)\}", lambda m: f"{unique}.[{m.group(1):<32}{'0HIER_NODE':<30}]", statement)
    statement = re.sub(r"\{L:([^}]+)\}", lambda m: f"{unique}.[{m.group(1)}]", statement)
    statement = re.sub(r"\{F:([^}]+)\}", lambda m: f"[{characteristic}].[{m.group(1)}]", statement)
    return statement


def shorten(member):
    """A member of BW's answer without the hierarchy and the blanks: GP 0HIER_NODE, 001."""
    part = member.split("].[", 1)[1][:-1] if "].[" in member else member
    return re.sub(r"\s+", " ", part).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("statements", nargs="*", help="statements; or --file")
    parser.add_argument("--file", help="statements, one per line")
    parser.add_argument("--scenario", action="append", required=True, help="a scenario (its test user); repeatable")
    parser.add_argument("--key-date", action="append", help="YYYY-MM-DD; repeatable (default 9999-12-31)")
    parser.add_argument("--hierarchy", default="ZCLDOC_ORG")
    parser.add_argument("--version", default="001")
    parser.add_argument("--json", help="write the answers to this file")
    args = parser.parse_args()
    raw = list(args.statements)
    if args.file:
        raw += [line.rstrip("\n") for line in open(args.file, encoding="utf-8")]
    raw = [s for s in raw if s.strip() and not s.lstrip().startswith("#")]
    if not raw:
        sys.exit("no statements")
    statements = [expand(s, args.hierarchy, args.version) for s in raw]

    env = read_env()
    scheme = "https" if env.get("SAP_USE_SSL", "").lower() in ("true", "1", "yes") else "http"
    api = Session(f"{scheme}://{env['SAP_ASHOST']}:{env['SAP_PORT']}/zzxxmla1", env.get("SAP_CLIENT", "001"),
                  env["SAP_USER"], env["SAP_PASSWORD"])
    answers = []
    try:
        status, body = api.get_json("/schema/api/auth/scenarios")
        users = {s["name"]: s["user"] for s in body["scenarios"]}
        for scenario in args.scenario:
            if scenario not in users:
                sys.exit(f"unknown scenario {scenario}")
            status, body = api.get_json("/schema/api/auth/probe", {
                "user": users[scenario], "keyDates": ",".join(args.key_date or ["9999-12-31"]),
                "mdx": "\n".join(statements)})
            if status != 200:
                sys.exit(f"{scenario}: {status} {body.get('error', body)}")
            rows = [r for r in body["results"] if r["test"] == "MDX"]
            others = [r for r in body["results"] if r["test"] != "MDX"]
            for row in others:
                print(f"{scenario} {row['keyDate']} {row['test']}: {row['status']} {row['message']}")
            for row in rows:
                question = raw[statements.index(row["mdx"])] if row["mdx"] in statements else row["mdx"]
                shown = [" x ".join(shorten(m) for m in cell["members"]) for cell in row.get("cells", [])]
                print(f"{scenario:8} {row['keyDate']} {row['status']:8} {question}")
                if row["message"]:
                    print(f"{'':28}{row['message'][:150]}")
                if shown:
                    print(f"{'':28}{', '.join(shown)[:300]}")
                answers.append({"scenario": scenario, "keyDate": row["keyDate"], "question": question,
                                "mdx": row["mdx"], "status": row["status"], "message": row["message"],
                                "rows": shown,
                                "values": [cell["value"] for cell in row.get("cells", [])]})
    finally:
        api.logoff()
    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(answers, f, indent=1, ensure_ascii=False)


if __name__ == "__main__":
    main()
