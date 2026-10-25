#!/usr/bin/env python3
"""Drives the MDX console (/zzxxmla1/schema/console.html, web/schema/console.js) in a headless browser against SAP:
the cube browser, a grid of two axes with its SOAP response, SQL statements (Trace SQL) and SOAP request, Format, a
flat table of three, a statement without axes and an error, a traced call opened from the trace page, and the mode
BW's MDX (a check of a statement in BW's names, its SQL statements, the traced check opened from the trace page).
Reads only (but for the console's traced calls).

    pip install playwright && playwright install chromium-headless-shell
    python scripts/console_ui_test.py
    python scripts/console_ui_test.py --shots out/       # with a screenshot per step
"""
import argparse
import json
import pathlib
import sys

from playwright.sync_api import sync_playwright

import sap_auth

RUN = 120000  # ms
# one of the probe's statements in BW's names (reference/auth/statements.json), on the clinic demo's aDSO
BW_MDX = 'SELECT {[Measures].[ZCLVISNO]} ON 0 FROM [$ZCLVISITA] WHERE ([ZCLDOC].[001], [ZCLDIAG].[A09])'


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
        page = browser.new_page(viewport={"width": 1400, "height": 900}, http_credentials=sap_auth.http_credentials())
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
        with page.expect_download() as download:
            page.click("table.sql-list tbody tr >> nth=0 >> button:has-text('Download')")
        text = pathlib.Path(download.value.path()).read_text(encoding="utf-8")
        check("a statement downloaded alone, formatted", download.value.suggested_filename.endswith("-1.sql")
              and text.startswith("-- 1: ") and "\nFROM " in text and text.rstrip().endswith(";"), text[:300])
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
        check("no grid toggle for three axes", page.locator(".result .segmented").count() == 0)
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

        # "Open in MDX Console": the traced call itself in the console, its answer, request and plan, not run again
        with page.context.expect_page() as opened:
            page.click(".detail a:has-text('Open in MDX Console')")
        handed = opened.value
        handed.on("pageerror", lambda e: errors.append(str(e)))
        handed.wait_for_selector("table.grid", timeout=RUN)
        check("console: the traced call's statement", "Product Family" in handed.input_value("textarea.mdx"))
        check("console: the traced call's answer", ["Drink"] == [r[0] for r in table(handed) if r[:1] == ["Drink"]],
              table(handed))
        check("console: marked as the traced call", "traced call" in handed.inner_text(".result .notice.info"))
        handed.click(".result-tabs button:has-text('SOAP request')")
        check("console: the traced call's request", "Product Family" in handed.input_value(".result textarea.trace"))
        handed.click(".result-tabs button:has-text('Query plan')")
        handed.wait_for_selector(".plan-tree", timeout=RUN)
        check("console: the traced call's query plan", "[Product].[Product Family]" in handed.inner_text(".plan-tree"))
        shot(handed, "6-handed-over")

        # the mode BW's MDX: a statement in BW's names checked at a key date (POST bw/check), its SQL statements
        page.goto(f"{args.url}?sap-client={args.client}")
        page.click(".topbar .segmented button:has-text(\"BW's MDX\")")
        check("BW's MDX: no catalog, a user and a key date", page.locator(".topbar select").count() == 0
              and page.input_value(".topbar input[type=date]") == "9999-12-31")
        page.fill("textarea.mdx", "")
        page.click(".browser .item:has(strong:text-is('Member'))")
        check("BW's MDX: a click inserts BW's name", page.input_value("textarea.mdx") == "[ZCLDOC].[001]",
              page.input_value("textarea.mdx"))
        page.fill(".topbar input[type=date]", "2024-06-15")
        page.fill("textarea.mdx", BW_MDX)
        page.click(".query button:has-text('Check')")
        page.wait_for_selector(".result .result-bar .status", timeout=RUN)
        bar = page.inner_text(".result .result-bar")
        check("BW's MDX: allowed at the key date", "OK" in bar and "2024-06-15" in bar, bar)
        resolved = page.input_value(".result textarea.trace")
        check("BW's MDX: the statement in olap4abap's names", "[ZCLDOC].[001]" in resolved
              and "[ZCLDIAG].[A09]" in resolved, resolved)
        selection = page.inner_text(".result ul.selection")
        check("BW's MDX: the selection checked", "Slicer" in selection and "ZCLDOC '001'" in selection, selection)
        check("BW's MDX: no query plan tab", page.locator(".result-tabs button:has-text('Query plan')").count() == 0)
        page.click(".result-tabs button:has-text('SQL statements')")
        page.wait_for_selector("table.sql-list, .result .notice.err", timeout=RUN)
        statements = page.eval_on_selector_all("table.sql-list pre.sql", "e => e.map(x => x.textContent)")
        check("BW's MDX: the SQL statements of the check", statements and all("SELECT" in x.upper() for x in statements),
              statements[:2])
        page.click(".result-tabs button:has-text('Response')")
        check("BW's MDX: the JSON answer", '"status": "OK"' in page.input_value(".result textarea.trace"))
        shot(page, "7-bw-check")
        page.click(".result-tabs button:has-text('Result')")
        page.fill("textarea.mdx", BW_MDX.replace("[001]", "[999]"))
        page.click(".query button:has-text('Check')")
        page.wait_for_selector(".result .result-bar .status", timeout=RUN)
        check("BW's MDX: an unknown name is ERROR with the fault", "ERROR" in page.inner_text(".result .result-bar")
              and "[999]" in page.inner_text(".result .notice.err"), page.inner_text(".result"))

        # the check on the trace page, and opened from there in the console's mode for BW's MDX
        page.goto(args.url.replace("console.html", "trace.html") + f"?sap-client={args.client}")
        page.wait_for_selector("tr.clickable", timeout=60000)
        page.click(".segmented button:has-text('Discover')")
        page.click(".segmented button:has-text('Execute')")
        page.wait_for_selector("tr.clickable:has-text('Check')", timeout=60000)
        page.click("tr.clickable:has-text('[ZCLDOC].[001]') >> nth=0")
        page.wait_for_selector(".detail header h2:has-text('2024-06-15')", timeout=60000)
        with page.context.expect_page() as opened:
            page.click(".detail a:has-text('Open in MDX Console')")
        handed = opened.value
        handed.on("pageerror", lambda e: errors.append(str(e)))
        handed.wait_for_selector(".result .result-bar .status", timeout=RUN)
        check("console: the traced check in the mode BW's MDX", handed.input_value("textarea.mdx") == BW_MDX
              and handed.input_value(".topbar input[type=date]") == "2024-06-15"
              and "OK" in handed.inner_text(".result .result-bar"), handed.inner_text(".result")[:300])
        shot(handed, "8-check-handed-over")
        # back to XMLA: the catalog again, the XMLA statement kept apart from BW's
        handed.click(".topbar .segmented button:has-text('XMLA')")
        handed.wait_for_selector(".topbar select", timeout=60000)
        check("back to XMLA: its own statement", handed.input_value("textarea.mdx") != BW_MDX)
        browser.close()

    check("no script errors", not errors, errors)
    print(f"{'FAILED' if failures else 'passed'}: {len(failures)} failure(s)")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
