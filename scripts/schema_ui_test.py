#!/usr/bin/env python3
"""Drives the schema builder (/zzxxmla1/schema/, web/schema/) in a headless browser against SAP, as a user would.
Changes nothing on the server: it edits proposals and lets the server check them, and cancels the accept and
remove dialogs.

    pip install playwright && playwright install chromium-headless-shell
    python scripts/schema_ui_test.py
    python scripts/schema_ui_test.py --shots out/       # with a screenshot per step
"""
import argparse
import pathlib
import re
import sys

from playwright.sync_api import sync_playwright

CHECK = 90000  # ms: a check loads all catalogs in ZZXXMLA1_CL_SCHEMA


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--url", default="http://localhost:50000/zzxxmla1/schema")
    parser.add_argument("--client", default="001")
    parser.add_argument("--shots", help="folder for screenshots")
    args = parser.parse_args()
    url = f"{args.url}?sap-client={args.client}"
    failures, errors = [], []

    def check(name, condition, detail=""):
        print(f"{'ok  ' if condition else 'FAIL'} {name}{'' if condition else ': ' + str(detail)[:300]}")
        if not condition:
            failures.append(name)

    def shot(page, name):
        if args.shots:
            pathlib.Path(args.shots).mkdir(parents=True, exist_ok=True)
            page.screenshot(path=f"{args.shots}/{name}.png", full_page=True)

    def status(page):
        page.wait_for_selector(".status.ok, .status.err", timeout=CHECK)
        return page.inner_text(".status")

    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(viewport={"width": 1400, "height": 900})
        page.on("pageerror", lambda e: errors.append(str(e)))
        page.goto(url)
        page.wait_for_selector("text=ZFMSALESA", timeout=60000)
        check("start page lists providers and catalogs", page.locator("text=ZFOODMART").count() > 0)
        shot(page, "1-start")

        # removing a catalog asks first; cancelled, nothing changes and the row is not opened
        page.click("tr:has-text('ZFOODMART') button:has-text('Remove…')")
        dialog = page.inner_text(".dialog")
        check("remove dialog names the catalog and its file", "ZFOODMART" in dialog
              and "/WEB-INF/schema/FoodmartBW.xml" in dialog, dialog)
        shot(page, "1-remove")
        page.click(".dialog button:has-text('Cancel')")
        check("cancel keeps the start page", page.locator(".dialog").count() == 0 and "#" not in page.url, page.url)

        # the InfoCube's proposal: its cube name is ZFOODMART's, so the server refuses it until it is renamed
        page.fill("input[type=search]", "foodmart")
        page.click("tr:has-text('ZFMSALES') >> nth=0")
        text = status(page)
        check("proposal of ZFMSALES clashes with ZFOODMART's cube", "defined twice" in page.inner_text(".banner"), text)
        check("the hash names the proposal", page.url.endswith("#proposal/ZFMSALES"), page.url)
        page.click(".tree .item:has-text('ZFMSALES') >> nth=1")
        cube = page.locator(".form input[type=text]").first
        cube.fill("ZFMSALES_UI")
        cube.press("Enter")
        page.wait_for_selector(".status.busy", timeout=5000)
        check("renamed cube loads", "Loads" in status(page))

        # the proposal's flat hierarchy of the store (docs/bw-schema-design-guide.md), and a user hierarchy with a
        # member property next to it
        page.click(".tree .item:has-text('ZFMSTORE') >> nth=0")
        check("the store is one flat hierarchy", page.locator(".hier").count() == 1)
        page.click("text=Add hierarchy")
        user = page.locator(".hier").nth(1)
        for level in ["ZFMCNTRY", "ZFMSTATE", "ZFMCITY", "ZFMSNAME"]:
            user.locator("select[aria-label='Add a level']").select_option(level)
        page.wait_for_selector(".status.busy", timeout=5000)
        check("hierarchy Country > State > City > Store loads", "Loads" in status(page))
        user.locator("button.link").nth(3).click()
        user.locator("select[aria-label='Add a property']").select_option("ZFMSTYPE")
        page.wait_for_selector(".status.busy", timeout=5000)
        check("member property loads", "Loads" in status(page))
        shot(page, "2-hierarchy")

        # a second unnamed hierarchy clashes with the proposal's
        name = user.locator("header input[type=text]").first
        name.fill("")
        name.press("Enter")
        page.wait_for_selector(".status.busy", timeout=5000)
        status(page)
        check("unnamed hierarchy is refused", "defined twice" in page.inner_text(".banner"), page.inner_text(".banner"))
        check("and warned about, on both", page.locator(".hier .notice.warn").count() == 2)
        page.click("text=Undo")
        page.wait_for_selector(".status.busy", timeout=5000)
        check("undo restores the name", "Loads" in status(page) and name.input_value() == "ZFMSTORE Hierarchy",
              name.input_value())

        page.click(".tree .item:has-text('ZFMSALES_UI')")
        page.wait_for_selector(".status.ok", timeout=CHECK)
        page.click("text=Accept…")
        check("accept dialog names the new catalog's file", "/WEB-INF/schema/ZFMSALES.xml" in page.inner_text(".dialog"))
        shot(page, "3-accept")
        page.click(".dialog button:has-text('Cancel')")
        page.click("role=tab[name='XML']")
        xml = page.input_value("textarea.xml")
        check("XML has the hierarchy", '<Hierarchy name="ZFMSTORE Hierarchy" hasAll="true">' in xml
              and '<Property name="ZFMSTYPE" sourceAttribute="ZFMSTYPE"/>' in xml)
        check("no attribute is a hierarchy", re.search(
            r'<DimensionAttribute name="ZFMSTYPE"[^>]*attributeHierarchyEnabled="false"', xml) is not None)

        # the aDSO: a time characteristic marked as time gets its suggested level type
        page = browser.new_page(viewport={"width": 1400, "height": 900}, color_scheme="dark")
        page.on("pageerror", lambda e: errors.append(str(e)))
        page.goto(f"{args.url}/?sap-client={args.client}#proposal/ZFMSALESA")
        status(page)
        page.click(".tree .item:has-text('0CALMONTH')")
        page.click("text=Time dimension")
        page.wait_for_selector(".status.busy", timeout=5000)
        check("time dimension loads", "Loads" in status(page))
        check("with the suggested level type", page.locator("tr:has(.kind) select").input_value() == "TimeMonths")
        shot(page, "4-adso-time")

        # NUMC as numbers: the store's NUMC columns (the aDSO's key too) switch to the views' numbers, and back
        page.click(".tree .item:has-text('ZFMSTORE')")
        page.click("text=As numbers")
        page.wait_for_selector(".status.busy", timeout=5000)
        loads = "Loads" in status(page)
        page.click("role=tab[name='XML']")
        xml = page.input_value("textarea.xml")
        check("NUMC as numbers loads", loads and re.search(
            r'<DimensionAttribute name="ZFMSTORE Key"[^>]*>\s*<KeyColumn dataType="Integer" columnName="ZFMSTORE_INT"', xml)
            is not None and 'columnName="ZFMSQFT_INT"' in xml,
            [line.strip() for line in xml.splitlines() if "ZFMSTORE" in line and "Column" in line])
        page.click("role=tab[name='Outline']")
        page.click("text=As numbers")
        page.click("role=tab[name='XML']")
        xml = page.input_value("textarea.xml")
        check("and back as BW holds them", "_INT" not in xml and re.search(
            r'<DimensionAttribute name="ZFMSTORE Key"[^>]*>\s*<KeyColumn dataType="String" columnName="ZFMSTORE"', xml)
            is not None)
        page.click("role=tab[name='Outline']")

        # members with facts: proposed on every dimension of the cube, dropped from the one marked time (the server
        # refuses it there); switched off for the store, its annotation goes
        page.click(".tree .item:has-text('ZFMSALESA') >> nth=1")
        dims = page.locator("section:has(h3:text('Dimensions of the cube'))")
        boxes = dims.locator("input[aria-label='Only members with facts']")
        annotated = boxes.count()
        check("members with facts proposed on every other dimension", boxes.count() == dims.locator("tbody tr").count() - 1
              and all(boxes.nth(i).is_checked() for i in range(boxes.count())), boxes.count())
        check("not on the time dimension", "time" in dims.locator("tr:has-text('0CALMONTH')").inner_text())
        dims.locator("tr:has-text('ZFMSTORE') input[aria-label='Only members with facts']").uncheck()
        page.wait_for_selector(".status.busy", timeout=5000)
        loads = "Loads" in status(page)
        page.click("role=tab[name='XML']")
        xml = page.input_value("textarea.xml")
        store = re.search(r'<DimensionUsage source="ZFMSTORE"[^>]*?(/>|>.*?</DimensionUsage>)', xml, re.S).group(0)
        month = re.search(r'<DimensionUsage source="0CALMONTH"[^>]*?(/>|>.*?</DimensionUsage>)', xml, re.S).group(0)
        check("switched off for the store", loads and "membersWithFacts" not in store, store)
        check("the time dimension has none", "membersWithFacts" not in month, month)
        check("the others keep it", xml.count('<Annotation name="olap4abap.membersWithFacts">true</Annotation>')
              == annotated - 1, (annotated, xml.count('olap4abap.membersWithFacts')))
        page.click("role=tab[name='Outline']")

        # the double-click columns: the proposal's default drill-through action (each characteristic's value, its
        # text where it has one); a measure added; a renamed dimension's columns follow
        page.click(".tree .item:has-text('ZFMSALESA') >> nth=1")
        drill = page.locator("section:has(h3:text('Double-click columns'))")
        names = [drill.locator("tbody tr").nth(i).locator("input[type=text]").input_value()
                 for i in range(drill.locator("tbody tr").count())]
        check("the proposal's double-click columns", names[:4] == ["Product", "Customer", "Store", "Promotion"]
              and "Calendar Year/Month (Text)" in names and len(names) == 10, names)
        drill.locator("select[aria-label='Add a column']").select_option("m|ZFMUNITS")
        page.wait_for_selector(".status.busy", timeout=5000)
        check("a measure column loads", "Loads" in status(page)
              and drill.locator("tbody tr").last.locator("input[type=text]").input_value() == "ZFMUNITS")
        shot(page, "5-drill-through")
        page.click(".tree .item:has-text('ZFMSTORE')")
        page.wait_for_selector(".form label:text('Dimension name')")
        dim = page.locator(".form input[type=text]").first
        dim.fill("ZFMSTORE_UI")
        dim.press("Enter")
        try:
            page.wait_for_selector(".status.busy", timeout=5000)
        except Exception:
            pass  # the check may be over already
        loads = "Loads" in status(page)
        page.click("role=tab[name='XML']")
        xml = page.input_value("textarea.xml")
        check("a renamed dimension's column follows", loads and
              '<DrillThroughAttribute name="Store" dimension="ZFMSTORE_UI" sourceAttribute="ZFMSTORE Key"/>' in xml,
              [loads] + [line.strip() for line in xml.splitlines() if "DrillThroughAttribute name=\"Store\"" in line])
        browser.close()

    check("no script errors", not errors, errors)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
