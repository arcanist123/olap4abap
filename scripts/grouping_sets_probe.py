#!/usr/bin/env python3
"""Probes GROUPING SETS on HANA through ADBC (docs/query-planning.md, open question on GROUPING SETS): on the wide
demo's aDSO (docs/wide-demo.md, reporting view /BIC/AZXMLWIDEA7, 1,000,000 records) each case reads the same groups
three ways, all with ZZXXMLA1_CL_SQL=>query (the engine's path: native SQL, every value fetched as a string):

    grouping_sets  one statement, GROUP BY GROUPING SETS ( ... ), GROUPING_ID( ... ) telling the patterns apart
    union_all      one statement, a SELECT per pattern joined by UNION ALL
    separate       a statement per pattern (what ZZXXMLA1_CL_MDX_FACTS does today)

and checks that the three give the same groups (per pattern: rows, total, and a sum weighted by the keys, so a value
under the wrong key shows). Times are milliseconds of the query calls only, in the order of the
repetitions. The variants run in a random order per repetition and every statement carries a new no-op condition
(AMOUNT <> -random), so no run is answered from HANA's plan cache or a result cache: each is compiled, as the engine's
statements with their literals are; the column data stays in memory, as it does in BW on HANA. Each case is one `sapcli abap run` (as the user of .env.sap), one after the other.

    python scripts/grouping_sets_probe.py                 # every case, 3 repetitions
    python scripts/grouping_sets_probe.py --case one big --reps 5
"""
import argparse
import importlib.util
import pathlib
import random

ROOT = pathlib.Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location("sap_files", ROOT / "scripts" / "sap-files.py")
sap_files = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sap_files)

TABLE = '"/BIC/AZXMLWIDEA7"'
AMOUNT = '"/BIC/ZXMLAKF"'
# replaced per run by a new random number: a condition true for every record (the amounts are 1 to 1,000) that makes
# each statement new text, so that HANA's plan cache and any result cache never answer it
NONCE = "#NONCE#"


def column(n):
    return f'"/BIC/ZXMLAD{n:02d}"'


# name -> (characteristics of the result, grouping sets as tuples of them, WHERE condition or None)
CASES = {
    # the proposal's example: one level on an axis and its All member
    "one": ((1,), [(1,), ()], None),
    # a grid of two levels with both totals and the grand total, on a slice of about 1,000 records
    "grid_slice": ((1, 2), [(1, 2), (1,), (2,), ()], f"{column(3)} = '0001'"),
    # the same on all records: Excel's 1,001 x 1,001 grid, about 632,000 groups
    "grid": ((1, 2), [(1, 2), (1,), (2,), ()], None),
    # a level of 100,000 members and its All member
    "big": ((0,), [(0,), ()], None),
    # rows one level, columns a crossjoin of two with subtotals: six patterns on about 50,000 records
    "many": ((1, 2, 3), [(1, 2, 3), (1, 2), (1,), (2, 3), (2,), ()], f"{column(4)} BETWEEN '0001' AND '0050'"),
}


def grouping_id(keys, grouping_set):
    # GROUPING_ID( a, b, ... ): a bit per argument, the first the most significant, 1 where it is aggregated
    value = 0
    for key in keys:
        value = value * 2 + (0 if key in grouping_set else 1)
    return value


def statements(keys, sets, where):
    condition = f" WHERE {AMOUNT} <> -{NONCE}" + (f" AND {where}" if where else "")
    key_list = ", ".join(column(k) for k in keys)
    grouping_sets = (
        f"SELECT GROUPING_ID( {key_list} ), {key_list}, SUM( {AMOUNT} ) FROM {TABLE}{condition} GROUP BY GROUPING SETS ( "
        + ", ".join("( " + ", ".join(column(k) for k in s) + " )" for s in sets) + " )")

    def one(grouping_set):
        selected = ", ".join(column(k) if k in grouping_set else f"CAST( NULL AS NVARCHAR( 6 ) )" for k in keys)
        group_by = (" GROUP BY " + ", ".join(column(k) for k in grouping_set)) if grouping_set else ""
        return (f"SELECT {grouping_id(keys, grouping_set)}, {selected}, SUM( {AMOUNT} ) FROM {TABLE}{condition}"
                f"{group_by}")

    separate = [one(s) for s in sets]
    union_all = " UNION ALL ".join(separate)
    return [("grouping_sets", [grouping_sets]), ("union_all", [union_all]), ("separate", separate)]


def abap_string(text, chunk=100):
    # a string expression of literals of at most `chunk` characters: a source line holds at most 255
    parts = [text[i:i + chunk] for i in range(0, len(text), chunk)]
    return "\n      && ".join(sap_files.literal(p) for p in parts)


def program(name, keys, sets, where, reps):
    # the runs in random order: per repetition every variant once, shuffled, each with its own nonce
    runs = []
    for rep in range(1, reps + 1):
        order = list(range(1, 4))
        random.shuffle(order)
        runs += [f"APPEND VALUE #( rep = {rep} variant = {v} nonce = `{random.randrange(10**8, 10**9)}` ) TO runs."
                 for v in order]
    appends = []
    for variant, sqls in statements(keys, sets, where):
        appends.append(f"APPEND VALUE #( name = {sap_files.literal(variant)} ) TO variants ASSIGNING <variant>.")
        for sql in sqls:
            appends.append(f"APPEND {abap_string(sql)} TO <variant>-sqls.")
    return "\n".join([
        "TYPES: BEGIN OF ty_stat, g TYPE string, rows TYPE i, total TYPE decfloat34, weighted TYPE decfloat34,",
        "       END OF ty_stat.",
        "TYPES ty_stats TYPE SORTED TABLE OF ty_stat WITH UNIQUE KEY g.",
        "TYPES: BEGIN OF ty_variant, name TYPE string, sqls TYPE string_table, times TYPE int4_table,",
        "         rows TYPE i, stats TYPE ty_stats, END OF ty_variant.",
        "DATA variants TYPE STANDARD TABLE OF ty_variant WITH EMPTY KEY.",
        "TYPES: BEGIN OF ty_run, rep TYPE i, variant TYPE i, nonce TYPE string, END OF ty_run.",
        "DATA runs TYPE STANDARD TABLE OF ty_run WITH EMPTY KEY.",
        "FIELD-SYMBOLS <variant> TYPE ty_variant.",
        "FIELD-SYMBOLS <stat> TYPE ty_stat.",
        f"DATA(keys) = {len(keys)}.",
        f"DATA(columns) = {len(keys) + 2}.",
        "DATA t0 TYPE i.",
        "DATA t1 TYPE i.",
        *appends,
        *runs,
        "LOOP AT runs INTO DATA(run).",
        "  DATA(rep) = run-rep.",
        "  ASSIGN variants[ run-variant ] TO <variant>.",
        "    DATA(elapsed) = 0.",
        "    DATA(count) = 0.",
        "    DATA(stats) = VALUE ty_stats( ).",
        "    LOOP AT <variant>-sqls INTO DATA(sql).",
        f"      REPLACE ALL OCCURRENCES OF `{NONCE}` IN sql WITH run-nonce.",
        "      GET RUN TIME FIELD t0.",
        "      DATA(result) = zzxxmla1_cl_sql=>query( sql = sql columns = columns ).",
        "      GET RUN TIME FIELD t1.",
        "      elapsed = elapsed + t1 - t0.",
        "      count = count + lines( result ).",
        "      IF rep = 1.",
        "        LOOP AT result INTO DATA(row).",
        "          DATA(weight) = CONV decfloat34( 1 ).",
        "          DO keys TIMES.",
        "            DATA(key) = row[ 1 + sy-index ].",
        "            weight = weight * ( COND decfloat34( WHEN key IS INITIAL THEN 0 ELSE key ) + 7 * sy-index + 1 ).",
        "          ENDDO.",
        "          DATA(text) = row[ columns ].",
        "          DATA(value) = COND decfloat34( WHEN text IS INITIAL THEN 0 ELSE text ).",
        "          READ TABLE stats ASSIGNING <stat> WITH TABLE KEY g = row[ 1 ].",
        "          IF sy-subrc <> 0.",
        "            INSERT VALUE #( g = row[ 1 ] ) INTO TABLE stats ASSIGNING <stat>.",
        "          ENDIF.",
        "          <stat>-rows = <stat>-rows + 1.",
        "          <stat>-total = <stat>-total + value.",
        "          <stat>-weighted = <stat>-weighted + value * weight.",
        "        ENDLOOP.",
        "      ENDIF.",
        "      CLEAR result.",
        "    ENDLOOP.",
        "    APPEND CONV i( elapsed / 1000 ) TO <variant>-times.",
        "    IF rep = 1.",
        "      <variant>-rows = count.",
        "      <variant>-stats = stats.",
        "    ENDIF.",
        "ENDLOOP.",
        f"out->write( |case {name}| ).",
        "DATA(first) = variants[ 1 ].",
        "LOOP AT variants ASSIGNING <variant>.",
        "  DATA(times) = ``.",
        "  DATA(best) = 0.",
        "  LOOP AT <variant>-times INTO DATA(ms).",
        "    times = times && | { ms }|.",
        "    IF best = 0 OR ms < best.",
        "      best = ms.",
        "    ENDIF.",
        "  ENDLOOP.",
        "  out->write( |  { <variant>-name WIDTH = 14 } statements { lines( <variant>-sqls ) WIDTH = 2 }|",
        "           && |  rows { <variant>-rows WIDTH = 8 }  best { best WIDTH = 6 } ms  (ms:{ times })|",
        "           && |  same groups: { COND string( WHEN <variant>-stats = first-stats THEN `yes` ELSE `NO` ) }| ).",
        "ENDLOOP.",
        "LOOP AT first-stats ASSIGNING <stat>.",
        "  out->write( |  grouping id { <stat>-g WIDTH = 2 }: rows { <stat>-rows WIDTH = 7 }  total { <stat>-total }| ).",
        "ENDLOOP.",
    ])


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--case", nargs="*", choices=list(CASES), default=list(CASES))
    parser.add_argument("--reps", type=int, default=3)
    parser.add_argument("--print-sql", action="store_true", help="print the statements and run nothing")
    args = parser.parse_args()
    for name in args.case:
        keys, sets, where = CASES[name]
        if args.print_sql:
            for variant, sqls in statements(keys, sets, where):
                print(f"-- {name} {variant}")
                print(";\n".join(sqls) + ";")
            continue
        # one sapcli call after the other (work processes in PRIV mode, docs/environment.md)
        print(sap_files.run_abap(program(name, keys, sets, where, args.reps)).rstrip(), flush=True)


if __name__ == "__main__":
    main()
