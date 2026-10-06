#!/usr/bin/env python3
"""Generate ABAP data classes that carry the FoodMart data inside the program.

Input:  data/foodmart/*.csv (made by scripts/export-foodmart-csv.py).
Output: data/foodmart-abap/<class>.clas.abap, one class per table, ready for
        `sapcli class write -a <CLASS> <file>` (see scripts/deploy-foodmart-data.sh).

Each class has one method, GET_CHUNKS, returning a STRING_TABLE. Every line of that table holds whole records:
fields are separated by '|' and records by '~'. A line is at most MAX_LITERAL characters, because an ABAP source
line is limited to 255 characters. Only the columns the BW model uses are exported (the column order is stated in
each class header and is the contract with the loader). Facts drop trailing zeros of their decimals.

The data has no '|', '~', apostrophes or non-ASCII characters; the script stops if that ever changes. It also stops
if a record ends with an empty field: ABAP SPLIT ... INTO TABLE drops a trailing empty field, so the loader would
see one field too few.
"""
import csv
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "data/foodmart"
OUT = ROOT / "data/foodmart-abap"
FIELD, RECORD = "|", "~"
MAX_LITERAL = 220  # APPEND '<literal>' TO rt_chunk. must stay below 255 characters per source line


def read(name):
    with open(SRC / f"{name}.csv", newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def trim_decimal(value):
    return value.rstrip("0").rstrip(".") if "." in value else value


def tables():
    """class suffix -> (description, column names, rows as lists of strings)."""
    classes = {r["product_class_id"]: r for r in read("product_class")}
    product = []
    for r in read("product"):
        c = classes[r["product_class_id"]]
        product.append([r["product_id"], r["product_name"], r["brand_name"], c["product_subcategory"],
                        c["product_category"], c["product_department"], c["product_family"]])
    return {
        "SALES": ("sales_fact_1997 rows",
                  ["product_id", "time_id", "customer_id", "promotion_id", "store_id", "store_sales", "store_cost",
                   "unit_sales"],
                  [[r["product_id"], r["time_id"], r["customer_id"], r["promotion_id"], r["store_id"],
                    trim_decimal(r["store_sales"]), trim_decimal(r["store_cost"]), trim_decimal(r["unit_sales"])]
                   for r in read("sales_fact_1997")]),
        "PRODUCT": ("product joined with product_class",
                    ["product_id", "product_name", "brand_name", "product_subcategory", "product_category",
                     "product_department", "product_family"],
                    product),
        "CUSTOMER": ("customer rows",
                     ["customer_id", "fullname", "country", "state_province", "city", "gender", "marital_status",
                      "education", "yearly_income"],
                     [[r["customer_id"], r["fullname"], r["country"], r["state_province"], r["city"], r["gender"],
                       r["marital_status"], r["education"], r["yearly_income"]] for r in read("customer")]),
        "STORE": ("store rows",
                  ["store_id", "store_name", "store_country", "store_state", "store_city", "store_type",
                   "store_manager", "store_sqft", "grocery_sqft", "frozen_sqft", "meat_sqft", "coffee_bar",
                   "store_street_address"],
                  [[r["store_id"], r["store_name"], r["store_country"], r["store_state"], r["store_city"],
                    r["store_type"], r["store_manager"], r["store_sqft"], r["grocery_sqft"], r["frozen_sqft"],
                    r["meat_sqft"], r["coffee_bar"], r["store_street_address"]] for r in read("store")]),
        "PROMO": ("promotion rows",
                  ["promotion_id", "promotion_name", "media_type"],
                  [[r["promotion_id"], r["promotion_name"], r["media_type"]] for r in read("promotion")]),
        # fiscal_period is empty in every row, so it must not be the last field (ABAP SPLIT drops trailing empties)
        "TIME": ("time_by_day rows",
                 ["time_id", "the_date", "the_day", "the_month", "the_year", "day_of_month", "week_of_year",
                  "month_of_year", "fiscal_period", "quarter"],
                 [[r["time_id"], r["the_date"], r["the_day"], r["the_month"], r["the_year"], r["day_of_month"],
                   r["week_of_year"], r["month_of_year"], r["fiscal_period"], r["quarter"]]
                  for r in read("time_by_day")]),
    }


def check(value):
    if FIELD in value or RECORD in value or "'" in value or not value.isascii():
        sys.exit(f"value not safe for an ABAP literal: {value!r}")


def pack(records):
    """Pack whole records into lines of at most MAX_LITERAL characters."""
    lines, current = [], ""
    for rec in records:
        if len(rec) > MAX_LITERAL:
            sys.exit(f"record longer than {MAX_LITERAL}: {rec[:60]}...")
        if current and len(current) + 1 + len(rec) > MAX_LITERAL:
            lines.append(current)
            current = rec
        else:
            current = rec if not current else current + RECORD + rec
    if current:
        lines.append(current)
    return lines


def render(suffix, description, columns, rows):
    for row in rows:
        for value in row:
            check(value)
        # the empty member (id 0) has empty attributes, also at the end; the loader reads attributes with OPTIONAL, so a
        # dropped trailing field is read as empty. Every other record must not end empty.
        if row[-1] == "" and row[0] != "0":
            sys.exit(f"{suffix}: record ends with an empty field, ABAP SPLIT would drop it: {row}")
    lines = pack(FIELD.join(row) for row in rows)
    name = f"zzxxmla1_cl_fm_data_{suffix.lower()}"
    out = [
        f'"! Generated by scripts/generate-foodmart-abap.py - do not edit. FoodMart {description}: {len(rows)} rows.',
        f'"! Columns, in order: {", ".join(columns)}.',
        f'"! Each line of the result holds whole records: fields separated by {FIELD}, records by {RECORD}.',
        f"CLASS {name} DEFINITION",
        "  PUBLIC",
        "  FINAL",
        "  CREATE PUBLIC.",
        "",
        "  PUBLIC SECTION.",
        "    CLASS-METHODS get_chunks RETURNING VALUE(rt_chunk) TYPE string_table.",
        "ENDCLASS.",
        "",
        f"CLASS {name} IMPLEMENTATION.",
        "  METHOD get_chunks.",
    ]
    out += [f"    APPEND '{line}' TO rt_chunk." for line in lines]
    out += ["  ENDMETHOD.", "ENDCLASS.", ""]
    return name, "\n".join(out), len(rows), len(lines)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for suffix, (description, columns, rows) in tables().items():
        name, source, nrows, nlines = render(suffix, description, columns, rows)
        path = OUT / f"{name}.clas.abap"
        path.write_text(source, encoding="utf-8", newline="\n")
        print(f"{name.upper()}: {nrows} rows in {nlines} lines, {path.stat().st_size // 1024} KB -> {path}")


if __name__ == "__main__":
    main()
