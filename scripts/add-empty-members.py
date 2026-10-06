#!/usr/bin/env python3
"""Adds an "empty" member with id 0 to every FoodMart dimension that lacks one, in a patched copy of the HSQLDB jar.

Why: BW gives every characteristic an initial member (blank key, SID 0, "not assigned"). Mondrian does not enforce that,
but FoodMart already uses id 0 that way for two dimensions (promotion 0 'No Promotion', store 0 'HQ'). To compare BW and
Mondrian one-to-one every dimension needs the same member: id 0, all attributes empty (strings '' and numbers 0), only the
name says what it is. This script adds those rows for product (and product_class), customer and time_by_day.

Input:  eMondrian/src/main/webapp/WEB-INF/lib/hsqldb-foodmart.jar (original, fetched by scripts/setup-reference.sh).
Output: data/foodmart-bw/hsqldb-foodmart.jar (git-ignored, derived from third-party data). The original is not changed.
        The rows are INSERT lines: product_class goes into foodmart.script, the others at the end of foodmart.log,
        which HSQLDB replays after foodmart.script.

Then: python scripts/export-foodmart-csv.py data/foodmart-bw/hsqldb-foodmart.jar   (CSV with the new rows)
      scripts/deploy-reference-schema.sh                                           (installs the patched jar)

Usage: python scripts/add-empty-members.py [source_jar] [target_jar]
"""
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SOURCE = ROOT / "eMondrian/src/main/webapp/WEB-INF/lib/hsqldb-foodmart.jar"
DEFAULT_TARGET = ROOT / "data/foodmart-bw/hsqldb-foodmart.jar"
LOG = "hsqldb-foodmart/foodmart.log"
SCRIPT = "hsqldb-foodmart/foodmart.script"
NL = chr(10)
CR = chr(13)

# product_class lives in foodmart.script (the export script reads it from there), everything else in foodmart.log.
# Column order is the one of scripts/export-foodmart-csv.py (the log has no DDL).
CLASS_ROW = "INSERT INTO \"product_class\" VALUES(0,'','','','')"  # so that product 0 has a class, all attributes empty
NEW_ROWS = [
    # product_class_id, product_id, brand_name, product_name, sku, srp, gross_weight, net_weight, recyclable_package,
    # low_fat, units_per_case, cases_per_pallet, shelf_width, shelf_height, shelf_depth
    "INSERT INTO \"product\" VALUES(0,0,'','No Product',0,0.0000,0.0E0,0.0E0,FALSE,FALSE,0,0,0.0E0,0.0E0,0.0E0)",
    # customer_id, account_num, lname, fname, mi, address1-4, city, state_province, postal_code, country,
    # customer_region_id, phone1, phone2, birthdate, marital_status, yearly_income, gender, total_children,
    # num_children_at_home, education, date_accnt_opened, member_card, occupation, houseowner, num_cars_owned, fullname
    "INSERT INTO \"customer\" VALUES(0,0,'','','','',NULL,NULL,NULL,'','','','',0,'','',NULL,'','','',0,0,'',NULL,'','','',0,"
    "'No Customer')",
    # time_id, the_date, the_day, the_month, the_year, day_of_month, week_of_year, month_of_year, quarter, fiscal_period
    "INSERT INTO \"time_by_day\" VALUES(0,NULL,'','',0,0,0,0,'',NULL)",
]


def main():
    source = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SOURCE
    target = Path(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_TARGET
    target.parent.mkdir(parents=True, exist_ok=True)

    with zipfile.ZipFile(source) as zin:
        log = zin.read(LOG).decode("utf-8")
        script = zin.read(SCRIPT).decode("utf-8")
        for row in NEW_ROWS + [CLASS_ROW]:
            table = row.split('"')[1]
            if f'INSERT INTO "{table}" VALUES(0,' in log + script:
                sys.exit(f"{table} already has an id 0 row; start from the original jar")

        # product_class: after its last INSERT in the script
        script_lines = script.split(NL)
        last_class = max(i for i, line in enumerate(script_lines) if line.startswith('INSERT INTO "product_class" '))
        line_end = CR if script_lines[last_class].endswith(CR) else ""
        script_lines.insert(last_class + 1, CLASS_ROW + line_end)
        new_script = NL.join(script_lines)

        # the other tables: at the end of the log, before its final COMMIT
        lines = log.rstrip(CR + NL).split(NL)
        end = max(i for i, line in enumerate(lines) if line.strip() == "COMMIT")
        line_end = CR if lines[0].endswith(CR) else ""
        patched = lines[:end] + [row + line_end for row in NEW_ROWS] + lines[end:]
        new_log = NL.join(patched) + NL

        with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as zout:
            for item in zin.infolist():
                if item.filename == LOG:
                    data = new_log.encode("utf-8")
                elif item.filename == SCRIPT:
                    data = new_script.encode("utf-8")
                else:
                    data = zin.read(item.filename)
                zout.writestr(item, data)
    shown = target.relative_to(ROOT) if target.is_relative_to(ROOT) else target
    print(f"wrote {shown}: {len(NEW_ROWS) + 1} rows added")


if __name__ == "__main__":
    main()
