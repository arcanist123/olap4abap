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

        # empty cells: the proposal omits them, the cube's pane switches it off and on
        omit = page.locator("label.switch:has-text('Omit empty cells') input")
        check("omit empty cells proposed", omit.is_checked())
        omit.uncheck()
        page.click("role=tab[name='XML']")
        check("switched off: no annotation", "omitEmptyCells" not in page.input_value("textarea.xml"))
        page.click("role=tab[name='Outline']")
        page.locator("label.switch:has-text('Omit empty cells') input").check()
        page.click("role=tab[name='XML']")
        check("switched on again", '<Annotation name="olap4abap.omitEmptyCells">true</Annotation>'
              in page.input_value("textarea.xml"))
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

        # fixed characteristics (docs/bw-schema-design-guide.md, section 3.8) on the clinic demo's aDSO, an edit on the
        # dimension's pane (POST fix): the period waits for the variant it is compounded with; the variant fixed to K4
        # keeps its dimension, the cube is annotated and shows it; undo takes it back; a value without SID is refused
        # and the K4 stays; unfixing the variant gives the plain schema
        page = browser.new_page(viewport={"width": 1400, "height": 900})
        page.on("pageerror", lambda e: errors.append(str(e)))
        page.goto(f"{args.url}/?sap-client={args.client}#proposal/ZCLVISITA")
        status(page)

        def xml_of():
            page.click("role=tab[name='XML']")
            text = page.input_value("textarea.xml")
            page.click("role=tab[name='Outline']")
            return text

        def open_dimension(name):
            page.click(f".tree .item:has-text('{name}') >> nth=0")
            page.wait_for_selector(".form label:text('Fixed value')")

        check("the proposal fixes nothing, its catalog is the provider's",
              page.input_value(".topbar input[type=text]") == "ZCLVISITA" and page.url.endswith("#proposal/ZCLVISITA")
              and "olap4abap.filter" not in xml_of(), page.url)
        open_dimension("ZCLFISCPR")
        check("the period waits for the variant", "fix it first" in page.inner_text(".form")
              and page.locator("input[aria-label='Fixed value of ZCLFISCPR']").count() == 0, page.inner_text(".form"))
        open_dimension("ZCLFISCVR")
        variant = page.locator("input[aria-label='Fixed value of ZCLFISCVR']")
        variant.focus()
        page.wait_for_function("document.querySelectorAll('#fixed-values-ZCLFISCVR option').length > 0", timeout=60000)
        offered = [page.locator("#fixed-values-ZCLFISCVR option").nth(i).get_attribute("value")
                   for i in range(page.locator("#fixed-values-ZCLFISCVR option").count())]
        check("the variants are offered", offered == ["K1", "K2", "K4"], offered)
        variant.fill("K4")
        page.click(".form button:text-is('Fix')")
        page.wait_for_selector(".form button:has-text('Unfix')", timeout=60000)
        shot(page, "6-fixed")
        loads = "Loads" in status(page)
        xml = xml_of()
        period = re.search(r'<Dimension [^>]*name="ZCLFISCPR".*?</Dimension>', xml, re.S)
        check("fixed to K4: annotated, the variant's dimension stays, the period by its own key, the schema loads",
              loads and re.search(r'<Annotation name="olap4abap\.filter\.ZCLFISCVR">\s*I EQ (?:\x27|&apos;|&#39;)K4(?:\x27|&apos;|&#39;)\s*</Annotation>', xml) is not None
              and page.locator(".tree .item:has-text('ZCLFISCVR')").count() > 0
              and period is not None and "COMPOUND_KEY" not in period.group(0), xml[:300])
        open_dimension("ZCLFISCPR")
        page.locator("input[aria-label='Fixed value of ZCLFISCPR']").focus()
        page.wait_for_function("document.querySelectorAll('#fixed-values-ZCLFISCPR option').length > 0", timeout=60000)
        periods = page.locator("#fixed-values-ZCLFISCPR option").count()
        check("the periods under K4 are offered", periods == 24, periods)
        page.click(".tree .item:has-text('ZCLVISITA') >> nth=1")
        check("the cube shows what it fixes", "ZCLFISCVR = K4" in page.inner_text(".form"), page.inner_text(".form"))
        page.click(".form button.link:has-text('ZCLFISCVR = K4')")
        page.wait_for_selector("input[aria-label='Fixed value of ZCLFISCVR']")
        check("its link opens the variant's dimension",
              page.input_value("input[aria-label='Fixed value of ZCLFISCVR']") == "K4")
        page.click(".topbar button:has-text('Undo')")
        check("undo takes the fix back", "olap4abap.filter" not in xml_of()
              and page.input_value("input[aria-label='Fixed value of ZCLFISCVR']") == "")
        variant = page.locator("input[aria-label='Fixed value of ZCLFISCVR']")
        variant.fill("K4")
        page.click(".form button:text-is('Fix')")
        page.wait_for_selector(".form button:has-text('Unfix')", timeout=60000)
        variant.fill("ZZ")
        page.click(".form button:has-text('Change')")
        page.wait_for_selector(".form .field-error", timeout=60000)
        check("a value without SID is refused, K4 stays", "has no value ZZ" in page.inner_text(".form")
              and re.search(r'<Annotation name="olap4abap\.filter\.ZCLFISCVR">\s*I EQ (?:\x27|&apos;|&#39;)K4(?:\x27|&apos;|&#39;)\s*</Annotation>', xml_of()) is not None, page.inner_text(".form"))
        page.click(".form button:has-text('Unfix')")
        page.wait_for_selector(".form button:text-is('Fix')", timeout=60000)
        loads = "Loads" in status(page)
        xml = xml_of()
        period = re.search(r'<Dimension [^>]*name="ZCLFISCPR".*?</Dimension>', xml, re.S)
        check("unfixed: no annotation, the period compounded again, the schema loads",
              loads and "olap4abap.filter" not in xml and period is not None and "COMPOUND_KEY" in period.group(0))

        # the selection editor on the same pane: a range in restrict members that the facts contradict is refused with
        # the values (the probe), the same range filtering the cube is applied
        open_dimension("ZCLFISCPR")
        page.click(".form button:text-is('Add row')")
        page.select_option("table.selection tr >> nth=1 >> select >> nth=1", "BT")
        page.fill("input[aria-label='Low value of row 1']", "2024001")
        page.fill("input[aria-label='High value of row 1']", "2024006")
        page.check("input[name='mode-ZCLFISCPR'] >> nth=1")
        page.click(".form button:text-is('Apply')")
        page.wait_for_selector(".form .field-error", timeout=60000)
        # the XML tab is looked at only after the next Apply: switching tabs drops a draft that is not applied
        check("restricting members the facts hold is refused, with the values, the rows stay",
              "2024007" in " ".join(page.locator(".form .field-error").all_inner_texts())
              and page.locator("table.selection tbody tr").count() == 1,
              [page.locator(".form .field-error").all_inner_texts(), page.locator("table.selection tbody tr").count()])
        page.check("input[name='mode-ZCLFISCPR'] >> nth=0")
        page.click(".form button:text-is('Apply')")
        page.wait_for_selector(".form button:has-text('Remove selection')", timeout=60000)
        shot(page, "7-selection")
        check("the range filters the cube (not restricting members, which was refused)",
              "olap4abap.members.ZCLFISCPR" not in xml_of() and re.search(r'<Annotation name="olap4abap\.filter\.ZCLFISCPR">\s*I BT (?:\x27|&apos;|&#39;)2024001'
                        r'(?:\x27|&apos;|&#39;) (?:\x27|&apos;|&#39;)2024006(?:\x27|&apos;|&#39;)\s*</Annotation>',
                        xml_of()) is not None and "Loads" in status(page))
        page.click(".form button:has-text('Remove selection')")
        page.wait_for_selector(".form button:has-text('Remove selection')", state="detached", timeout=60000)
        check("the selection is removed", "olap4abap.filter" not in xml_of())

        # the fiscal defaults of a proposal (0TSC0T001): the period's twelve regular periods in restrict members, shown
        # as rows; removed, the preset brings them back
        page = browser.new_page(viewport={"width": 1400, "height": 900})
        page.on("pageerror", lambda e: errors.append(str(e)))
        page.goto(f"{args.url}/?sap-client={args.client}#proposal/0TSC0T001")
        status(page)
        open_dimension("0FISCPER")
        rows = page.locator("table.selection tbody tr")
        check("the proposal's period selection is twelve rows in restrict members",
              rows.count() == 12 and page.is_checked("input[name='mode-0FISCPER'] >> nth=1")
              and page.input_value("input[aria-label='Low value of row 12']") == "*012", rows.count())
        page.click(".form button:has-text('Remove selection')")
        page.wait_for_selector(".form button:has-text('Remove selection')", state="detached", timeout=60000)
        check("removed: no rows, no annotation", page.locator("table.selection").count() == 0
              and "olap4abap.members.0FISCPER" not in xml_of())
        page.click(".form button:has-text('Regular periods 001–012')")
        page.click(".form button:text-is('Apply')")
        page.wait_for_selector(".form button:has-text('Remove selection')", timeout=60000)
        xml = xml_of()
        check("the preset restricts the periods again, K4 stays",
              "olap4abap.members.0FISCPER" in xml and xml.count("I CP") == 12 and "olap4abap.filter.0FISCVARNT" in xml
              and "Loads" in status(page), xml[:600])
        browser.close()

    check("no script errors", not errors, errors)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
