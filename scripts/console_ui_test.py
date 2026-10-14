#!/usr/bin/env python3
"""Drives the MDX console (/zzxxmla1/schema/console.html, web/schema/console.js) in a headless browser against SAP:
the cube browser, a grid of two axes with its SOAP response, SQL statements (Trace SQL) and SOAP request, Format, a
flat table of three, a statement without axes and an error. Reads only (but for the console's traced calls).

    pip install playwright && playwright install chromium-headless-shell
    python scripts/console_ui_test.py
    python scripts/console_ui_test.py --shots out/       # with a screenshot per step
"""
import argparse
import json
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
        page.wait_for_selector(".result", timeout=RUN)

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

        # the exchange: the SOAP response and request as sent, the SQL statements from the call's trace
        page.click(".result-tabs button:has-text('SOAP response')")
        response = page.input_value(".result textarea.trace")
        check("SOAP response tab", "ExecuteResponse" in response and "<Axis name=\"Axis0\">" in response, response[:300])
        page.click(".result-tabs button:has-text('SOAP request')")
        request = page.input_value(".result textarea.trace")
        check("SOAP request tab", "<Statement>" in request and "Product Family" in request, request[:300])
        page.click(".result-tabs button:has-text('SQL statements')")
        page.wait_for_selector("table.sql-list, .result .notice.err", timeout=RUN)
        statements = page.eval_on_selector_all("table.sql-list pre.sql", "e => e.map(x => x.textContent)")
        check("SQL statements tab", statements and all("SELECT" in x.upper() for x in statements), statements[:2])
        summary = page.inner_text(".result-bar")
        check("SQL summary: statements and server time", "on the server" in summary, summary)
        shot(page, "2-sql")

        # the query plan: the resolved tree with marks; a statement's element is shown in it with its statements
        page.click(".sql-list button.mono >> nth=0")
        page.wait_for_selector(".plan .plan-node.selected", timeout=RUN)
        tree = page.inner_text(".plan-tree")
        check("query plan: parts, elements and marks", "ROWS (AXIS1)" in tree.upper() and "crossjoin" in tree.lower()
              and "[Measures].[Unit Sales]" in tree and "static" in tree, tree[:500])
        selected = page.inner_text(".plan .plan-node.selected")
        listed = page.eval_on_selector_all(".plan-sql table.sql-list tbody tr", "rows => rows.length")
        check("a statement's element selected in the plan, its statements listed", "SQL" in selected and listed > 0,
              f"{selected!r}, {listed} rows")
        page.click(".plan-node:has-text('Cells'), .plan-node:has-text('Axes') >> nth=0")
        phase = page.inner_text(".plan-sql .result-bar")
        check("a phase lists its statements", "Phase" in phase, phase)
        shot(page, "2-plan")
        with page.expect_download() as download:
            page.click("[aria-label='Download the query plan'] button:has-text('Text')")
        text = pathlib.Path(download.value.path()).read_text(encoding="utf-8")
        check("query plan as text: statement, plan, tree and statements", "Query plan of ZFMSALES" in text
              and "crossjoin" in text and "Plan: query" in text and "#1 " in text and "\n-- 1: " in text, text[:400])
        with page.expect_download() as download:
            page.click("[aria-label='Download the query plan'] button:has-text('JSON')")
        data = json.loads(pathlib.Path(download.value.path()).read_text(encoding="utf-8"))
        check("query plan as JSON", "crossjoin" in data["mdx"] and data["explain"]["parts"] and data["sql"]
              and "node" in data["sql"][0], str(data)[:300])
        page.click(".result-tabs button:has-text('Result')")
        page.uncheck("label:has-text('Trace SQL') input")
        run(page, "select from [ZFMSALES]")
        page.click(".result-tabs button:has-text('SQL statements')")
        message = page.inner_text(".result .result-msg")
        check("Trace SQL off: no statements", "Trace is off" in message, message)
        page.check("label:has-text('Trace SQL') input")
        page.click(".result-tabs button:has-text('Result')")

        # Format lays the statement out, Ctrl+Z takes it back; three axes: a flat table, the highest axis first
        three = ("select {[Measures].[Unit Sales]} on 0, {[Product].[Product Family].Members} on 1,"
                 " {[Store].[Store Country].Members} on 2 from [ZFMSALES]")
        page.fill("textarea.mdx", three)
        page.click("button:has-text('Format')")
        formatted = ("SELECT\n  {[Measures].[Unit Sales]} ON 0,\n  {[Product].[Product Family].Members} ON 1,\n"
                     "  {[Store].[Store Country].Members} ON 2\nFROM [ZFMSALES]")
        check("format", page.input_value("textarea.mdx") == formatted, page.input_value("textarea.mdx"))
        page.keyboard.press("Control+z")
        check("format undone", page.input_value("textarea.mdx") == three, page.input_value("textarea.mdx"))
        page.keyboard.press("Shift+Alt+f")
        check("format by key", page.input_value("textarea.mdx") == formatted, page.input_value("textarea.mdx"))
        page.click("button:has-text('Run')")
        page.wait_for_selector(".result", timeout=RUN)
        rows = table(page)
        check("flat header", rows[0] == ["Store", "Product", "Measures", "Value"], rows[:1])
        check("flat rows", len(rows) == 13 and ["USA", "Food", "Unit Sales", "191,940"] in rows, rows)
        check("no grid toggle for three axes", page.locator(".segmented").count() == 0)
        shot(page, "3-flat")

        run(page, "select from [ZFMSALES]")
        check("no axes: one cell", table(page) == [["266,773"]], table(page))

        run(page, "select {[Measures].[Nope]} on 0 from [ZFMSALES]")
        message = page.inner_text(".result .notice.err")
        check("error shown", "[Measures].[Nope]" in message, message)
        shot(page, "4-error")

        # the trace page shows a traced call as the console does: the console's last Execute with its query plan
        run(page, "select {[Measures].[Unit Sales]} on 0, {[Product].[Product Family].Members} on 1 from [ZFMSALES]")
        page.goto(args.url.replace("console.html", "trace.html") + f"?sap-client={args.client}")
        page.wait_for_selector("tr.clickable", timeout=60000)
        page.click("tr.clickable:has-text('Execute') >> nth=0")
        page.wait_for_selector(".detail .plan-tree", timeout=60000)
        tree = page.inner_text(".detail .plan-tree")
        check("trace page: the Execute's query plan", "[Product].[Product Family]" in tree and "Members" in tree, tree[:300])
        page.click(".detail .tabs button:has-text('SQL statements')")
        page.click(".detail .sql-list button.mono >> nth=0")
        page.wait_for_selector(".detail .plan .plan-node.selected", timeout=60000)
        check("trace page: a statement's element shown in the plan", "Members" in page.inner_text(".detail .plan-node.selected"),
              page.inner_text(".detail .plan-node.selected"))
        shot(page, "5-trace")
        browser.close()

    check("no script errors", not errors, errors)
    print(f"{'FAILED' if failures else 'passed'}: {len(failures)} failure(s)")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
