#!/usr/bin/env python3
"""Loads the clinic InfoCube ZCLVISIT into the local SSAS Multidimensional instance (localhost\\SSAS_MULT) as database
and cube ZCLHIER, with every BW hierarchy of the clinic that has a copy as a parent-child dimension related to the
facts many-to-many through its closure, so that SSAS gives BW's values for link nodes, duplicate leaves, postable
nodes, intervals and the not-assigned node (docs/environment.md, The clinic in SSAS Multidimensional).

1. The rows: the SQL Server database olap4abap_ssas of scripts/build-ssas-clinic.py (dropped and loaded again by it,
   unless --no-load), plus per hierarchy of the export (data/foodmart-bw/bw/hierarchy_<h>.json, written by
   scripts/build-bw-reference-db.py from the copy of ZZXXMLA1_CL_BW_HIERARCHY_COPY at BW's current version):
   - H_<h>: a row per occurrence of the copy's node table (the virtual root left out), keyed by POS (the depth-first
     number, unique also inside an expanded link), PARENT_POS (the enclosing inner occurrence, NULL for a root),
     SID, DEPTH, NODE_NAME, CAPTION and LEAF; where the hierarchy shows the not-assigned node, REST_H after the roots
     (REST_TOP_SID) and below it every SID of the SID table under no leaf, ordered by name as olap4abap orders them;
   - HV_<h>: H_<h> with NAME and CAPTION: a leaf named and captioned as the characteristic's member (its view's
     nameColumn and the key attribute's NameColumn), a node named by its NODE_NAME and captioned by its CAPTION (a
     text node's text of RSTHIERNODE as build-bw-reference-db.py exports it, else its NODE_NAME);
   - B_<h>: the bridge, per occurrence POS the distinct SIDs of the leaf occurrences of its subtree (POS to END_POS;
     a leaf its own SID, a postable node its value through its first leaf), REST_H its values;
   - FACT_ZCLVISIT: the fact table under a name the data source view can hold, its key figures without /BIC/.
   SSAS's service account NT Service\\MSOLAP$SSAS_MULT reads the database.
2. The model: an ASSL Create of database ZCLHIER (Invoke-ASCmd), then ProcessFull. Derived from
   reference/schema/ClinicBW.xml:
   - per characteristic a dimension of its name: the key attribute named as the level (KeyColumn SID, NameColumn the
     level's nameColumn, ordered by name where the key attribute has an OrderByColumn, else by key), captioned by
     the key attribute's NameColumn through an en-US (1033) translation with a CaptionColumn; the other attributes
     member properties (AttributeHierarchyEnabled false; the <char> Key ones enabled and hidden, as drill-through
     columns), captioned as the level's properties; AttributeAllMemberName the hierarchy's allMemberName;
   - per BW hierarchy a parent-child dimension of its name: the hidden key attribute <h> Occurrence (POS, named and
     captioned from HV_<h>), the parent attribute <h> (PARENT_POS), levels named Level 01 to Level nn,
     NonLeafDataHidden (a postable node's value comes through the bridge already); [ZCLPAT_PRG].[ZCLPAT_PRG];
   - cube ZCLHIER: measure group Visits (the schema's sum measures, their format strings and captions) related to
     every characteristic dimension on its SID_ column and to every hierarchy dimension many-to-many through the
     measure group B_<h> (a hidden count on the bridge, granularity the occurrence and the characteristic's SID); the
     cube's default drill-through action Details with each characteristic's key.
3. The member map, data/foodmart-bw/ssas/members.json: per hierarchy and occurrence POS SSAS's unique name
   ([ZCLPAT_PRG].[ZCLPAT_PRG].&[17]) and olap4abap's ([ZCLPAT.ZCLPAT_PRG].[PROGRAMS].[CHRONIC]..., the path of names
   from the root), to rewrite statements into SSAS's names and answers into olap4abap's.
Only the cell values are taken from this model; the shape of a BW hierarchy (levels, parents, children counts,
order) is olap4abap's and BW's. The generated SQL and ASSL are kept in the git-ignored data/foodmart-bw/ssas/.

Usage: python scripts/build-ssas-clinic-md.py [--no-load]
"""
import argparse
import bisect
import importlib.util
import json
import pathlib
import re
import subprocess
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape

ROOT = pathlib.Path(__file__).resolve().parent.parent
SQL_INSTANCE = r"localhost\SSAS_TAB"  # the SQL Server of build-ssas-clinic.py
SSAS_INSTANCE = r"localhost\SSAS_MULT"
SSAS_ACCOUNT = r"NT Service\MSOLAP$SSAS_MULT"
DATABASE = "ZCLHIER"
CUBE = "ZCLHIER"
DSV = "DSV"
FACT_VIEW = "FACT_ZCLVISIT"
MEASURE_GROUP = "Visits"
LANGUAGE = 1033  # en-US, the language Excel sends
REST_NODE_NAME = "REST_H"
TEXT_NODE = "0HIER_NODE"  # NODE_IOBJ of a text node

spec = importlib.util.spec_from_file_location("ssas_clinic", ROOT / "scripts" / "build-ssas-clinic.py")
tabular = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tabular)
bw = tabular.bw
WORK = tabular.WORK
SQL_DATABASE = tabular.SQL_DATABASE


def exported_hierarchies():
    names = list(bw.HIERARCHIES) + list(bw.SSAS_HIERARCHIES)
    result = []
    for name in names:
        path = bw.EXPORT / f"hierarchy_{name}.json"
        if path.exists():
            data = json.loads(path.read_text(encoding="utf-8"))
            assert "rest_shown" in data, f"{path.name} of an earlier export: run build-bw-reference-db.py again"
            result.append(data)
        else:
            print(f"{name}: no export (no copy in SAP), left out")
    return result


def occurrences(data):
    """The rows of H_<h> and B_<h>: (POS, PARENT_POS, SID, DEPTH, NODE_NAME, CAPTION, LEAF) and (POS, SID)."""
    assert "texts" in data, f"{data['hierarchy']}: no node texts: run build-bw-reference-db.py again"
    fields = [f["name"] for f in data["nodes"]["fields"]]
    rows = []
    for raw in data["nodes"]["rows"]:
        row = {f: raw[i] for i, f in enumerate(fields)}
        rows.append(dict(sid=int(bw.number(row["SID"])), depth=int(bw.number(row["DEPTH"])),
                         pos=int(bw.number(row["POS"])), end=int(bw.number(row["END_POS"])),
                         name=row["NODE_NAME"],
                         caption=(data["texts"].get(row["NODE_NAME"]) if row["NODE_IOBJ"] == TEXT_NODE else None)
                         or row["NODE_NAME"]))
    rows.sort(key=lambda r: r["pos"])
    assert len({r["pos"] for r in rows}) == len(rows), f"{data['hierarchy']}: POS not unique"
    root = int(data["root_sid"])
    assert rows[0]["sid"] == root and rows[0]["depth"] == 0, data["hierarchy"]
    nodes, stack = [], [rows[0]]
    for row in rows[1:]:
        while stack[-1]["end"] < row["pos"]:
            stack.pop()
        parent = stack[-1]
        assert parent["depth"] == row["depth"] - 1, (data["hierarchy"], row)
        leaf = row["sid"] >= 0
        assert leaf == (row["end"] == row["pos"]) or not leaf, (data["hierarchy"], row)
        nodes.append(dict(pos=row["pos"], parent=None if parent is rows[0] else parent["pos"], sid=row["sid"],
                          depth=row["depth"], name=row["name"].strip(), caption=row["caption"].strip(), leaf=leaf,
                          end=row["end"]))
        if not leaf:
            stack.append(row)
    leaves = [n for n in nodes if n["leaf"]]
    leaf_pos = [n["pos"] for n in leaves]
    bridge = []
    for node in nodes:
        first, last = bisect.bisect_left(leaf_pos, node["pos"]), bisect.bisect_right(leaf_pos, node["end"])
        bridge += [(node["pos"], sid) for sid in sorted({n["sid"] for n in leaves[first:last]})]
    if data["rest_shown"]:
        sid_table = json.loads(bw.table_file(f"/BIC/S{data['characteristic']}").read_text(encoding="utf-8"))
        sid_index = [f["name"] for f in sid_table["fields"]].index("SID")
        assigned = {n["sid"] for n in leaves}
        rest = sorted({int(bw.number(r[sid_index])) for r in sid_table["rows"]} - assigned)
        rest_pos = rows[-1]["end"] + 1
        nodes.append(dict(pos=rest_pos, parent=None, sid=int(data["rest_top_sid"]), depth=1, name=REST_NODE_NAME,
                          caption=REST_NODE_NAME, leaf=False, end=rest_pos + len(rest)))
        # the values below it get their POS once their names are known (olap4abap orders them by name): rest_sids
        bridge += [(rest_pos, sid) for sid in rest]
        data["rest_sids"] = rest
        data["rest_pos"] = rest_pos
    return nodes, bridge


def sql_rows(table, columns, rows):
    lines = [f'CREATE TABLE "{table}" ({", ".join(columns)});']
    for start in range(0, len(rows), tabular.ROWS_PER_INSERT):
        values = ",\n".join("(" + ",".join(
            "NULL" if v is None else str(v) if isinstance(v, int) else "N'" + v.replace("'", "''") + "'"
            for v in row) + ")" for row in rows[start:start + tabular.ROWS_PER_INSERT])
        lines.append(f'INSERT INTO "{table}" VALUES\n{values};')
    return lines


def characteristic_columns(schema, characteristic):
    """The view of a characteristic and its columns that name and caption its members."""
    dimension = next(d for d in schema.findall("Dimension") if d.get("name") == characteristic)
    key = next(a for a in dimension.findall("DimensionAttribute") if a.get("usage") == "Key")
    hierarchy = next(h for h in dimension.findall("Hierarchy") if h.find("Level").get("sourceAttribute") ==
                     key.get("name"))
    table = hierarchy.find("Table").get("name") if hierarchy.find("Table") is not None else dimension.get("table")
    return table, hierarchy.find("Level").get("nameColumn"), key.find("NameColumn").get("columnName")


def sqlcmd_json(query):
    """The rows of a query as JSON, one value of unlimited length (-y 0, which writes no header)."""
    result = subprocess.run(["sqlcmd", "-S", SQL_INSTANCE, "-E", "-C", "-b", "-d", SQL_DATABASE, "-y", "0", "-f",
                             "65001", "-Q", f"SET NOCOUNT ON; SELECT ({query} FOR JSON PATH, INCLUDE_NULL_VALUES) AS j"],
                            capture_output=True, text=True, encoding="utf-8")
    if result.returncode:
        raise SystemExit(f"sqlcmd failed:\n{result.stdout}{result.stderr}")
    text = result.stdout.strip()
    return [] if text == "NULL" else json.loads(text)


def load_hierarchies(schema, hierarchies):
    lines = []
    measures = ", ".join(f'"{m.get("column")}" AS "{m.get("name")}"' for m in schema.find("Cube").findall("Measure"))
    keys = ", ".join(f'"{u.get("foreignKey")}"' for u in schema.find("Cube").findall("DimensionUsage"))
    lines += ["GO", f'CREATE VIEW "{FACT_VIEW}" AS SELECT {keys}, {measures} '
                    f'FROM "{schema.find("Cube").find("Table").get("name")}";']
    for data in hierarchies:
        h, c = data["hierarchy"], data["characteristic"]
        nodes, bridge = occurrences(data)
        lines += ["GO"] + sql_rows(f"H_{h}", ['"POS" INT NOT NULL PRIMARY KEY', '"PARENT_POS" INT NULL',
                                             '"SID" INT NOT NULL', '"DEPTH" INT NOT NULL',
                                             '"NODE_NAME" NVARCHAR(250) NOT NULL', '"CAPTION" NVARCHAR(250) NOT NULL',
                                             '"LEAF" INT NOT NULL'],
                                   [(n["pos"], n["parent"], n["sid"], n["depth"], n["name"], n["caption"],
                                     int(n["leaf"]))
                                    for n in nodes])
        lines += sql_rows(f"B_{h}", ['"POS" INT NOT NULL', '"SID" INT NOT NULL', 'PRIMARY KEY ("POS", "SID")'],
                          bridge)
        view, name_column, caption_column = characteristic_columns(schema, c)
        if data["rest_shown"]:
            # REST_H's values: leaves under it, after every other occurrence, ordered by name (olap4abap's order)
            lines.append(f'INSERT INTO "H_{h}" SELECT {data["rest_pos"]} + ROW_NUMBER() OVER (ORDER BY '
                         f'v."{name_column}", v."SID"), {data["rest_pos"]}, v."SID", 2, N\'\', N\'\', 1 FROM "{view}" v '
                         f'WHERE v."SID" IN (SELECT "SID" FROM "B_{h}" WHERE "POS" = {data["rest_pos"]});')
            lines.append(f'INSERT INTO "B_{h}" SELECT "POS", "SID" FROM "H_{h}" WHERE "PARENT_POS" = '
                         f'{data["rest_pos"]};')
        lines += ["GO", f'CREATE VIEW "HV_{h}" AS SELECT h."POS", h."PARENT_POS", h."SID", h."DEPTH", '
                        f'CAST(CASE WHEN h."LEAF" = 1 THEN v."{name_column}" ELSE h."NODE_NAME" END AS NVARCHAR(250)) '
                        f'AS "NAME", CAST(CASE WHEN h."LEAF" = 1 THEN v."{caption_column}" ELSE h."CAPTION" END '
                        f'AS NVARCHAR(250)) AS "CAPTION" FROM "H_{h}" h LEFT OUTER JOIN "{view}" v '
                        f'ON h."LEAF" = 1 AND v."SID" = h."SID";']
        print(f"{h}: {len(nodes)} occurrences, {len(bridge)} bridge rows"
              + (f", REST_H with {len(data['rest_sids'])} values" if data["rest_shown"] else ""))
    lines += ["GO", f"IF SUSER_ID('{SSAS_ACCOUNT}') IS NULL CREATE LOGIN [{SSAS_ACCOUNT}] FROM WINDOWS;",
              f"IF USER_ID('{SSAS_ACCOUNT}') IS NULL CREATE USER [{SSAS_ACCOUNT}] FOR LOGIN [{SSAS_ACCOUNT}];",
              f"ALTER ROLE db_datareader ADD MEMBER [{SSAS_ACCOUNT}];"]
    path = WORK / "load-md.sql"
    path.write_text("SET NOCOUNT ON;\n" + "\n".join(lines) + "\n", encoding="utf-8")
    original, tabular.INSTANCE = tabular.INSTANCE, SQL_INSTANCE
    tabular.sqlcmd(path, SQL_DATABASE)
    tabular.INSTANCE = original


# --- ASSL --------------------------------------------------------------------------------------------------------

def x(value):
    return escape(str(value))


class Columns:
    """The columns of the data source view's tables, from SQL Server's catalog."""

    def __init__(self, tables):
        names = ", ".join(f"'{t}'" for t in tables)
        rows = sqlcmd_json("SELECT TABLE_NAME AS t, COLUMN_NAME AS c, DATA_TYPE AS d, CHARACTER_MAXIMUM_LENGTH AS l "
                           f"FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME IN ({names}) "
                           "ORDER BY TABLE_NAME, ORDINAL_POSITION")
        self.tables = {t: [] for t in tables}
        for row in rows:
            self.tables[row["t"]].append(row)
        missing = [t for t, columns in self.tables.items() if not columns]
        assert not missing, f"not in {SQL_DATABASE}: {missing}"

    def column(self, table, name):
        return next(c for c in self.tables[table] if c["c"] == name)

    def item(self, table, name, tag="KeyColumn"):
        """A DataItem bound to a column."""
        column = self.column(table, name)
        # a key figure is exact as Currency (4 decimals; BW's have at most 3), a Double's sums are not
        data_type = {"int": "Integer", "bigint": "BigInt", "decimal": "Currency", "float": "Double",
                     "nvarchar": "WChar", "varchar": "WChar"}[column["d"]]
        size = f"<DataSize>{column['l']}</DataSize>" if data_type == "WChar" else ""
        return (f"<{tag}><DataType>{data_type}</DataType>{size}<Source xsi:type=\"ColumnBinding\">"
                f"<TableID>{x(table)}</TableID><ColumnID>{x(name)}</ColumnID></Source></{tag}>")

    def xsd(self):
        types = {"int": "xs:int", "bigint": "xs:long", "decimal": "xs:decimal", "float": "xs:double"}
        elements = []
        for table, columns in self.tables.items():
            kind = "View" if not table.startswith(("H_", "B_")) else "Table"
            items = []
            for c in columns:
                if c["d"] in types:
                    items.append(f'<xs:element name="{x(c["c"])}" msprop:DbColumnName="{x(c["c"])}" '
                                 f'type="{types[c["d"]]}" minOccurs="0"/>')
                else:
                    items.append(f'<xs:element name="{x(c["c"])}" msprop:DbColumnName="{x(c["c"])}" minOccurs="0">'
                                 f'<xs:simpleType><xs:restriction base="xs:string"><xs:maxLength value="{c["l"]}"/>'
                                 '</xs:restriction></xs:simpleType></xs:element>')
            elements.append(f'<xs:element name="{x(table)}" msprop:DbTableName="{x(table)}" msprop:DbSchemaName="dbo" '
                            f'msprop:TableType="{kind}"><xs:complexType><xs:sequence>{"".join(items)}'
                            '</xs:sequence></xs:complexType></xs:element>')
        return ('<xs:schema id="DSV" xmlns="" xmlns:xs="http://www.w3.org/2001/XMLSchema" '
                'xmlns:msdata="urn:schemas-microsoft-com:xml-msdata" '
                'xmlns:msprop="urn:schemas-microsoft-com:xml-msprop">'
                '<xs:element name="DSV" msdata:IsDataSet="true" msdata:UseCurrentLocale="true"><xs:complexType>'
                f'<xs:choice minOccurs="0" maxOccurs="unbounded">{"".join(elements)}</xs:choice>'
                '</xs:complexType></xs:element></xs:schema>')


def translation(caption, extra=""):
    if not caption:
        return ""
    return (f"<Translations><Translation><Language>{LANGUAGE}</Language><Caption>{x(caption)}</Caption>{extra}"
            "</Translation></Translations>")


def characteristic_dimension(dimension, columns):
    """A dimension of a characteristic: its flat hierarchy, the other attributes member properties."""
    name = dimension.get("name")
    attributes = {a.get("name"): a for a in dimension.findall("DimensionAttribute")}
    key = next(a for a in attributes.values() if a.get("usage") == "Key")
    hierarchy = next(h for h in dimension.findall("Hierarchy") if h.find("Level").get("sourceAttribute") ==
                     key.get("name"))
    level = hierarchy.find("Level")
    table = hierarchy.find("Table").get("name") if hierarchy.find("Table") is not None else dimension.get("table")
    properties = {p.get("sourceAttribute"): p for p in level.findall("Property")}
    caption_column = columns.item(table, key.find("NameColumn").get("columnName"), "CaptionColumn")
    relationships, others = [], []
    for attribute in attributes.values():
        if attribute is key or attribute.get("name") not in properties:
            continue
        a_name = attribute.get("name")
        relationships.append(f"<AttributeRelationship><AttributeID>{x(a_name)}</AttributeID><Name>{x(a_name)}</Name>"
                             f"{translation(properties[a_name].get('caption'))}</AttributeRelationship>")
        # a key is a drill-through column, which needs an attribute hierarchy: enabled, hidden
        enabled = "<AttributeHierarchyVisible>false</AttributeHierarchyVisible>" if a_name.endswith(" Key") else \
            "<AttributeHierarchyEnabled>false</AttributeHierarchyEnabled>"
        others.append(f"<Attribute><ID>{x(a_name)}</ID><Name>{x(a_name)}</Name><KeyColumns>"
                      f"{columns.item(table, attribute.find('KeyColumn').get('columnName'))}</KeyColumns>"
                      f"{enabled}</Attribute>")
    order = "Name" if key.find("OrderByColumn") is not None else "Key"
    key_attribute = (f"<Attribute><ID>{x(level.get('name'))}</ID><Name>{x(level.get('name'))}</Name><Usage>Key</Usage>"
                     f"<KeyColumns>{columns.item(table, key.find('KeyColumn').get('columnName'))}</KeyColumns>"
                     f"{columns.item(table, level.get('nameColumn'), 'NameColumn')}"
                     f"<OrderBy>{order}</OrderBy>{translation(level.get('caption'), caption_column)}"
                     f"<AttributeRelationships>{''.join(relationships)}</AttributeRelationships></Attribute>")
    return (f"<Dimension><ID>{x(name)}</ID><Name>{x(name)}</Name>"
            f"<Source xsi:type=\"DataSourceViewBinding\"><DataSourceViewID>{DSV}</DataSourceViewID></Source>"
            f"<AttributeAllMemberName>{x(hierarchy.get('allMemberName'))}</AttributeAllMemberName>"
            f"{translation(dimension.get('caption'))}"
            f"<Attributes>{key_attribute}{''.join(others)}</Attributes></Dimension>"), level.get("name")


def hierarchy_dimension(data, schema, columns):
    """A parent-child dimension of a BW hierarchy, keyed by occurrence."""
    h, c = data["hierarchy"], data["characteristic"]
    table = f"HV_{h}"
    depth = max(int(bw.number(r[[f["name"] for f in data["nodes"]["fields"]].index("DEPTH")]))
                for r in data["nodes"]["rows"])
    template = ";".join(f"Level {n:02}" for n in range(1, depth + 2))
    dimension = next(d for d in schema.findall("Dimension") if d.get("name") == c)
    schema_hierarchy = next((x_ for x_ in dimension.findall("Hierarchy") if x_.get("name") == h), None)
    all_name = schema_hierarchy.get("allMemberName") if schema_hierarchy is not None else f"All {h}"
    caption = schema_hierarchy.get("caption") if schema_hierarchy is not None else h
    occurrence = f"{h} Occurrence"
    return (f"<Dimension><ID>{x(h)}</ID><Name>{x(h)}</Name>"
            f"<Source xsi:type=\"DataSourceViewBinding\"><DataSourceViewID>{DSV}</DataSourceViewID></Source>"
            f"<AttributeAllMemberName>{x(all_name)}</AttributeAllMemberName>{translation(caption)}<Attributes>"
            f"<Attribute><ID>{x(occurrence)}</ID><Name>{x(occurrence)}</Name><Usage>Key</Usage>"
            f"<KeyColumns>{columns.item(table, 'POS')}</KeyColumns>{columns.item(table, 'NAME', 'NameColumn')}"
            f"<OrderBy>Key</OrderBy>{translation(caption, columns.item(table, 'CAPTION', 'CaptionColumn'))}"
            f"<AttributeHierarchyVisible>false</AttributeHierarchyVisible></Attribute>"
            f"<Attribute><ID>{x(h)}</ID><Name>{x(h)}</Name><Usage>Parent</Usage>"
            f"<KeyColumns>{columns.item(table, 'PARENT_POS').replace('</DataType>', '</DataType><NullProcessing>ZeroOrBlank</NullProcessing>')}</KeyColumns>"
            f"<OrderBy>Key</OrderBy><NamingTemplate>{x(template)}</NamingTemplate>"
            f"<MembersWithData>NonLeafDataHidden</MembersWithData>"
            f"<RootMemberIf>ParentIsBlankSelfOrMissing</RootMemberIf>{translation(caption)}</Attribute>"
            f"</Attributes></Dimension>")


def regular(dimension_id, attribute_id, item):
    return (f"<Dimension xsi:type=\"RegularMeasureGroupDimension\"><CubeDimensionID>{x(dimension_id)}"
            f"</CubeDimensionID><Attributes><Attribute><AttributeID>{x(attribute_id)}</AttributeID>"
            f"<KeyColumns>{item}</KeyColumns><Type>Granularity</Type></Attribute></Attributes></Dimension>")


def partition(name, table):
    return (f"<Partitions><Partition><ID>{x(name)}</ID><Name>{x(name)}</Name><Source xsi:type=\"DsvTableBinding\">"
            f"<DataSourceViewID>{DSV}</DataSourceViewID><TableID>{x(table)}</TableID></Source></Partition>"
            "</Partitions>")


def cube(schema, hierarchies, key_attributes, columns):
    cube_def = schema.find("Cube")
    dimensions, groups, usages = [], [], []
    for usage in cube_def.findall("DimensionUsage"):
        source = usage.get("source")
        dimensions.append(f"<Dimension><ID>{x(source)}</ID><Name>{x(source)}</Name><DimensionID>{x(source)}"
                          f"</DimensionID></Dimension>")
        usages.append(regular(source, key_attributes[source], columns.item(FACT_VIEW, usage.get("foreignKey"))))
    for data in hierarchies:
        h, c = data["hierarchy"], data["characteristic"]
        dimensions.append(f"<Dimension><ID>{x(h)}</ID><Name>{x(h)}</Name><DimensionID>{x(h)}</DimensionID>"
                          "</Dimension>")
        usages.append(f"<Dimension xsi:type=\"ManyToManyMeasureGroupDimension\"><CubeDimensionID>{x(h)}"
                      f"</CubeDimensionID><MeasureGroupID>B_{x(h)}</MeasureGroupID></Dimension>")
        groups.append(
            f"<MeasureGroup><ID>B_{x(h)}</ID><Name>B_{x(h)}</Name><Measures><Measure><ID>B_{x(h)} Count</ID>"
            f"<Name>B_{x(h)} Count</Name><AggregateFunction>Count</AggregateFunction><DataType>Integer</DataType>"
            f"<Source><DataType>Integer</DataType><DataSize>4</DataSize><Source xsi:type=\"RowBinding\">"
            f"<TableID>B_{x(h)}</TableID></Source></Source><Visible>false</Visible></Measure></Measures>"
            f"<Dimensions>{regular(h, f'{h} Occurrence', columns.item(f'B_{h}', 'POS'))}"
            f"{regular(c, key_attributes[c], columns.item(f'B_{h}', 'SID'))}</Dimensions>"
            f"{partition(f'B_{h}', f'B_{h}')}</MeasureGroup>")
    measures = []
    for measure in cube_def.findall("Measure"):
        assert measure.get("aggregator") == "sum", measure.get("name")
        measures.append(f"<Measure><ID>{x(measure.get('name'))}</ID><Name>{x(measure.get('name'))}</Name>"
                        f"<AggregateFunction>Sum</AggregateFunction><DataType>Currency</DataType>"
                        f"{columns.item(FACT_VIEW, measure.get('name'), 'Source')}"
                        f"<FormatString>{x(measure.get('formatString'))}</FormatString>"
                        f"{translation(measure.get('caption'))}</Measure>")
    visits = (f"<MeasureGroup><ID>{MEASURE_GROUP}</ID><Name>{MEASURE_GROUP}</Name><Measures>{''.join(measures)}"
              f"</Measures><Dimensions>{''.join(usages)}</Dimensions>{partition(MEASURE_GROUP, FACT_VIEW)}"
              "</MeasureGroup>")
    actions = []
    for action in cube_def.findall("DrillThroughAction"):
        drill_columns = "".join(
            f"<Column xsi:type=\"CubeAttributeBinding\"><CubeID>{CUBE}</CubeID><CubeDimensionID>"
            f"{x(a.get('dimension'))}</CubeDimensionID><AttributeID>{x(a.get('sourceAttribute'))}</AttributeID>"
            "<Type>All</Type></Column>" for a in action.findall("DrillThroughAttribute"))
        actions.append(f"<Action xsi:type=\"DrillThroughAction\"><ID>{x(action.get('name'))}</ID>"
                       f"<Name>{x(action.get('name'))}</Name><TargetType>Cells</TargetType>"
                       f"<Target>MeasureGroupMeasures(\"{MEASURE_GROUP}\")</Target><Type>DrillThrough</Type>"
                       f"<Default>{str(action.get('default') == 'true').lower()}</Default>"
                       f"<Columns>{drill_columns}</Columns></Action>")
    return (f"<Cube><ID>{CUBE}</ID><Name>{CUBE}</Name>{translation(cube_def.get('caption'))}"
            f"<Language>{LANGUAGE}</Language><Collation>Latin1_General_CI_AS</Collation>"
            f"<Source xsi:type=\"DataSourceViewBinding\"><DataSourceViewID>{DSV}</DataSourceViewID></Source>"
            f"<Dimensions>{''.join(dimensions)}</Dimensions>"
            f"<MeasureGroups>{visits}{''.join(groups)}</MeasureGroups><Actions>{''.join(actions)}</Actions></Cube>")


def database(schema, hierarchies):
    cube_def = schema.find("Cube")
    used = [u.get("source") for u in cube_def.findall("DimensionUsage")]
    tables = [FACT_VIEW]
    for dimension in schema.findall("Dimension"):
        if dimension.get("name") in used:
            tables.append(characteristic_columns(schema, dimension.get("name"))[0])
    for data in hierarchies:
        tables += [f"HV_{data['hierarchy']}", f"B_{data['hierarchy']}"]
    columns = Columns(tables)
    dimensions, key_attributes = [], {}
    for dimension in schema.findall("Dimension"):
        if dimension.get("name") in used:
            definition, key_attributes[dimension.get("name")] = characteristic_dimension(dimension, columns)
            dimensions.append(definition)
    dimensions += [hierarchy_dimension(data, schema, columns) for data in hierarchies]
    connection = (f"Provider=MSOLEDBSQL19.1;Data Source={SQL_INSTANCE};Initial Catalog={SQL_DATABASE};"
                  "Integrated Security=SSPI;Trust Server Certificate=True")
    return (f"<Create AllowOverwrite=\"true\" xmlns=\"http://schemas.microsoft.com/analysisservices/2003/engine\">"
            f"<ObjectDefinition><Database xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\" "
            f"xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"><ID>{DATABASE}</ID><Name>{DATABASE}</Name>"
            f"<Language>{LANGUAGE}</Language><Collation>Latin1_General_CI_AS</Collation>"
            f"<DataSources><DataSource xsi:type=\"RelationalDataSource\"><ID>SQL</ID><Name>SQL</Name>"
            f"<ConnectionString>{x(connection)}</ConnectionString><ImpersonationInfo>"
            f"<ImpersonationMode>ImpersonateServiceAccount</ImpersonationMode></ImpersonationInfo></DataSource>"
            f"</DataSources><DataSourceViews><DataSourceView><ID>{DSV}</ID><Name>{DSV}</Name>"
            f"<DataSourceID>SQL</DataSourceID><Schema>{columns.xsd()}</Schema></DataSourceView></DataSourceViews>"
            f"<Dimensions>{''.join(dimensions)}</Dimensions><Cubes>{cube(schema, hierarchies, key_attributes, columns)}"
            f"</Cubes></Database></ObjectDefinition></Create>")


def ascmd(path):
    script = (f"Import-Module SqlServer; Invoke-ASCmd -Server '{SSAS_INSTANCE}' -InputFile '{path}' "
              "| Out-String -Width 100000")
    result = subprocess.run(["powershell", "-NoProfile", "-Command", script], capture_output=True, text=True,
                            encoding="utf-8")
    errors = re.findall(r'<Error [^>]*Description="([^"]*)"', result.stdout)
    if result.returncode or errors:
        raise SystemExit(f"Invoke-ASCmd {path.name} failed:\n" + ("\n".join(errors) or result.stdout + result.stderr))


def deploy(schema, hierarchies):
    create = WORK / "deploy-md.xmla"
    create.write_text(database(schema, hierarchies), encoding="utf-8")
    ascmd(create)
    process = WORK / "process-md.xmla"
    process.write_text("<Process xmlns=\"http://schemas.microsoft.com/analysisservices/2003/engine\">"
                       f"<Type>ProcessFull</Type><Object><DatabaseID>{DATABASE}</DatabaseID></Object></Process>",
                       encoding="utf-8")
    ascmd(process)
    print(f"SSAS database {DATABASE} on {SSAS_INSTANCE}: {len(hierarchies)} hierarchies, processed")


def name_part(name):
    return "[" + name.replace("]", "]]") + "]"


def member_map(hierarchies):
    """Per hierarchy and occurrence SSAS's unique name and olap4abap's (the path of names from the root)."""
    result = {}
    for data in hierarchies:
        h, c = data["hierarchy"], data["characteristic"]
        rows = {r["POS"]: r for r in sqlcmd_json(f"SELECT POS, PARENT_POS, NAME FROM HV_{h}")}
        members = []
        for pos in sorted(rows):
            path, at = [], rows[pos]
            while at is not None:
                path.insert(0, at["NAME"] or "")
                at = rows.get(at["PARENT_POS"])
            members.append(dict(pos=pos, ssas=f"{name_part(h)}.{name_part(h)}.&[{pos}]",
                                olap4abap=f"[{c}.{h}]" + "".join("." + name_part(n) for n in path)))
        olap4abap = [m["olap4abap"] for m in members]
        if len(set(olap4abap)) != len(olap4abap):
            print(f"{h}: olap4abap's unique names repeat for {len(olap4abap) - len(set(olap4abap))} occurrences")
        result[h] = members
    path = WORK / "members.json"
    path.write_text(json.dumps(result, indent=1, ensure_ascii=False), encoding="utf-8")
    print(f"member map: {path.relative_to(ROOT)}")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--no-load", action="store_true", help="keep the SQL Server database as it is")
    args = parser.parse_args()
    schema = ET.parse(tabular.SCHEMA).getroot()
    hierarchies = exported_hierarchies()
    if not args.no_load:
        tabular.load_sql_database(schema)
        load_hierarchies(schema, hierarchies)
    else:
        for data in hierarchies:
            occurrences(data)  # the REST_H positions
    deploy(schema, hierarchies)
    member_map(hierarchies)


if __name__ == "__main__":
    main()
