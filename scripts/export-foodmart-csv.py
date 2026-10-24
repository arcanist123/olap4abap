#!/usr/bin/env python3
"""Export the FoodMart tables needed for the BW Sales cube from the HSQLDB jar into CSV files.

Source: eMondrian/src/main/webapp/WEB-INF/lib/hsqldb-foodmart.jar (fetched by scripts/setup-reference.sh).
The jar holds an HSQLDB script plus log, no live database: sales_fact_1997 and product_class are INSERTs in
foodmart.script, the dimension tables are INSERTs in foodmart.log. The log has no DDL, so the column lists below
are the standard FoodMart ones, checked against the sample rows.

Output goes to data/foodmart/*.csv (git-ignored, derived from third-party data): UTF-8, comma separated, header
row, NULL as empty, dates as YYYY-MM-DD when the time part is zero, booleans as true/false.

Usage: python scripts/export-foodmart-csv.py [jar] [out_dir]
"""
import csv
import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_JAR = ROOT / "eMondrian/src/main/webapp/WEB-INF/lib/hsqldb-foodmart.jar"
DEFAULT_OUT = ROOT / "data/foodmart"

# table -> (source file inside the jar, columns)
TABLES = {
    "sales_fact_1997": ("foodmart.script", [
        "product_id", "time_id", "customer_id", "promotion_id", "store_id", "store_sales", "store_cost", "unit_sales"]),
    "product_class": ("foodmart.script", [
        "product_class_id", "product_subcategory", "product_category", "product_department", "product_family"]),
    "product": ("foodmart.log", [
        "product_class_id", "product_id", "brand_name", "product_name", "sku", "srp", "gross_weight", "net_weight",
        "recyclable_package", "low_fat", "units_per_case", "cases_per_pallet", "shelf_width", "shelf_height",
        "shelf_depth"]),
    "customer": ("foodmart.log", [
        "customer_id", "account_num", "lname", "fname", "mi", "address1", "address2", "address3", "address4", "city",
        "state_province", "postal_code", "country", "customer_region_id", "phone1", "phone2", "birthdate",
        "marital_status", "yearly_income", "gender", "total_children", "num_children_at_home", "education",
        "date_accnt_opened", "member_card", "occupation", "houseowner", "num_cars_owned", "fullname"]),
    "store": ("foodmart.log", [
        "store_id", "store_type", "region_id", "store_name", "store_number", "store_street_address", "store_city",
        "store_state", "store_postal_code", "store_country", "store_manager", "store_phone", "store_fax",
        "first_opened_date", "last_remodel_date", "store_sqft", "grocery_sqft", "frozen_sqft", "meat_sqft",
        "coffee_bar", "video_store", "salad_bar", "prepared_food", "florist"]),
    "promotion": ("foodmart.log", [
        "promotion_id", "promotion_district_id", "promotion_name", "media_type", "cost", "start_date", "end_date"]),
    "time_by_day": ("foodmart.log", [
        "time_id", "the_date", "the_day", "the_month", "the_year", "day_of_month", "week_of_year", "month_of_year",
        "quarter", "fiscal_period"]),
}

INSERT_RE = re.compile(r'^INSERT INTO "([A-Za-z0-9_]+)" VALUES\((.*)\)\s*$')
ZERO_TIME = " 00:00:00.000000"


def parse_values(text):
    """Split the inside of VALUES(...) into Python values: strings, numbers (as text), None, bool."""
    values, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c == "'":
            j, buf = i + 1, []
            while True:
                k = text.index("'", j)
                buf.append(text[j:k])
                if k + 1 < n and text[k + 1] == "'":  # escaped quote
                    buf.append("'")
                    j = k + 2
                else:
                    i = k + 1
                    break
            values.append("".join(buf))
        else:
            j = text.find(",", i)
            j = n if j < 0 else j
            token = text[i:j].strip()
            i = j
            if token == "NULL":
                values.append(None)
            elif token in ("TRUE", "FALSE"):
                values.append(token.lower())
            else:
                values.append(clean_number(token))
        if i < n and text[i] == ",":
            i += 1
    return values


def clean_number(token):
    """HSQLDB writes doubles as 8.39E0; render them as plain decimals."""
    if "E" in token:
        return format(float(token), "f").rstrip("0").rstrip(".") or "0"
    return token


def clean(value):
    if value is None:
        return ""
    if value.endswith(ZERO_TIME):
        return value[: -len(ZERO_TIME)]
    return value


def main():
    jar = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_JAR
    out_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_OUT
    if not jar.exists():
        sys.exit(f"jar not found: {jar} (run scripts/setup-reference.sh)")
    out_dir.mkdir(parents=True, exist_ok=True)

    rows = {t: [] for t in TABLES}
    wanted_by_file = {}
    for table, (src, _) in TABLES.items():
        wanted_by_file.setdefault(src, set()).add(table)

    with zipfile.ZipFile(jar) as z:
        for src, tables in wanted_by_file.items():
            with z.open(f"hsqldb-foodmart/{src}") as fh:
                for raw in fh:
                    if not raw.startswith(b"INSERT INTO"):
                        continue
                    m = INSERT_RE.match(raw.decode("utf-8"))
                    if m and m.group(1) in tables:
                        rows[m.group(1)].append(parse_values(m.group(2)))

    for table, (_, columns) in TABLES.items():
        for r in rows[table]:
            if len(r) != len(columns):
                sys.exit(f"{table}: row has {len(r)} values, expected {len(columns)}: {r[:5]}")
        path = out_dir / f"{table}.csv"
        with open(path, "w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(columns)
            for r in rows[table]:
                w.writerow([clean(v) for v in r])
        print(f"{table}: {len(rows[table])} rows -> {path}")


if __name__ == "__main__":
    main()
