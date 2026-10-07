#!/usr/bin/env python3
"""Drives the MDX console (/zzxxmla1/schema/console.html, web/schema/console.js) in a headless browser against SAP:
the cube browser, a grid of two axes, a flat table of three, a statement without axes and an error. Reads only.

    pip install playwright && playwright install chromium-headless-shell
    python scripts/console_ui_test.py
    python scripts/console_ui_test.py --shots out/       # with a screenshot per step
"""
import argparse
import pathlib
import sys

from playwright.sync_api import sync_playwright

RUN = 120000  # ms


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--url", default="http://localhost:50000/zzxxmla1/schema/console.html")
    parser.add_argument("--client", default="001")
    parser.add_argument("--shots", help="folder for screenshots")
    args = parser.parse_args()
    failures, errors = [], []

    def check(name, condition, detail=""):
        print(f"{'ok  ' if condition else 'FAIL'} {name}{'' if condition else ': ' + str(detail)[:300]}")
        if not condition:
            failures.append(name)

    def shot(page, name):
        if args.shots:
            pathlib.Path(args.shots).mkdir(parents=True, exist_ok=True)
            page.screenshot(path=f"{args.shots}/{name}.png", full_page=True)

    def run(page, mdx):
        page.fill("textarea.mdx", mdx)
        page.click("button:has-text('Run')")
        page.wait_for_selector(".result, .result-msg .notice", timeout=RUN)

    def table(page):
        return page.eval_on_selector_all("table.grid tr", "rows => rows.map(r => [...r.children].map(c => c.textContent.trim()))")

    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(viewport={"width": 1400, "height": 900})
        page.on("pageerror", lambda e: errors.append(str(e)))
        page.goto(f"{args.url}?sap-client={args.client}")
        page.wait_for_selector(".topbar select option[value=ZFOODMART]", state="attached", timeout=60000)
        page.select_option(".topbar select", "ZFOODMART")

        # the cube browser: cube, measures, a click inserts the unique name
        page.click(".browser .item:has-text('ZFMSALES')", timeout=60000)
        page.click(".browser .item:has-text('Measures')", timeout=60000)
        page.fill("textarea.mdx", "")
        page.click(".browser .item:has-text('Unit Sales')")
        check("a click inserts the unique name", page.input_value("textarea.mdx") == "[Measures].[Unit Sales]",
              page.input_value("textarea.mdx"))
        shot(page, "1-browser")

        # two axes: a grid, Product spanning the rows of its Store members
        run(page, "select {[Measures].[Unit Sales], [Measures].[Store Sales]} on columns,\n"
                  " crossjoin({[Product].[Product Family].Members}, {[Store].[Store Country].Members}) on rows\n"
                  "from [ZFMSALES] where [Time].[1997]")
        rows = table(page)
        check("grid header", rows[0] == ["Product", "Store", "Unit Sales", "Store Sales"], rows[:1])
        check("grid row of two members", ["Drink", "Canada", "", ""] in rows, rows)
        check("grid spanned row", ["USA", "24,597", "48,836.21"] in rows, rows)
        check("grid row headers side by side", page.eval_on_selector(
            "th.row-head[title='[Product].[Drink]']", "e => getComputedStyle(e).display") == "table-cell")
        check("slicer shown", "where 1997" in page.inner_text(".result-bar"), page.inner_text(".result-bar"))
        shot(page, "2-grid")
        page.click(".segmented button:has-text('Table')")
        rows = table(page)
        check("two axes as a table", ["Drink", "USA", "Store Sales", "48,836.21"] in rows, rows)
        page.click(".segmented button:has-text('Grid')")

        # three axes: a flat table, the highest axis first
        run(page, "select {[Measures].[Unit Sales]} on 0, {[Product].[Product Family].Members} on 1,"
                  " {[Store].[Store Country].Members} on 2 from [ZFMSALES]")
        rows = table(page)
        check("flat header", rows[0] == ["Store", "Product", "Measures", "Value"], rows[:1])
        check("flat rows", len(rows) == 13 and ["USA", "Food", "Unit Sales", "191,940"] in rows, rows)
        check("no grid toggle for three axes", page.locator(".segmented").count() == 0)
        shot(page, "3-flat")

        run(page, "select from [ZFMSALES]")
        check("no axes: one cell", table(page) == [["266,773"]], table(page))

        run(page, "select {[Measures].[Nope]} on 0 from [ZFMSALES]")
        message = page.inner_text(".result-msg .notice.err")
        check("error shown", "[Measures].[Nope]" in message, message)
        shot(page, "4-error")
        browser.close()

    check("no script errors", not errors, errors)
    print(f"{'FAILED' if failures else 'passed'}: {len(failures)} failure(s)")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
