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
        browser.close()

    check("no script errors", not errors, errors)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
