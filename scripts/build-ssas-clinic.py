#!/usr/bin/env python3
"""Loads the clinic InfoCube ZCLVISIT into the local SSAS (Tabular) as database ZCLHIER, with the BW hierarchy
ZCLDIAG_ICD as a level hierarchy, so that SSAS answers the same questions as the reference's catalog ZCLHIER
(reference/schema/ClinicBW.xml; docs/environment.md, SSAS (Tabular) as reference server).

1. The rows: the export of scripts/build-bw-reference-db.py (data/foodmart-bw/bw/, run it first; --no-export there
   reuses an export) goes into the SQL Server database olap4abap_ssas of the instance next to SSAS
   (localhost\\SSAS_TAB): the cube's BW tables as BW holds them, ZZXXMLA1_HL_ZCLDIAG_ICD from the copy of the
   hierarchy (the reference's hierarchy_levels) and the characteristics' views under their placeholder names, from
   HANA's SQL as it is (T-SQL runs it with QUOTED_IDENTIFIER on). So SSAS reads the same views as SAP and the
   reference. The database is dropped and created again; SSAS's service account reads it.
2. The model: a TMSL createOrReplace of database ZCLHIER (compatibility level 1600), derived from ClinicBW.xml, then a
   full refresh. Per Dimension a table of its name (its views joined on SID where its hierarchies have several), a
   column per DimensionAttribute (named as the attribute; a display attribute and its text visible, so each is a
   hierarchy, captioned as the level's member property; the key and its copy <char> Key hidden), and per hierarchy:
   - one level (the flat hierarchy of a characteristic): a column named as the level, from its nameColumn, sorted
     by the key attribute's OrderByColumn or else by its key (the SID), so the attribute hierarchy
     [ZCLPAT].[ZCLPAT] is the level's;
   - several levels (ZCLDIAG_ICD): a user hierarchy of the hierarchy's name with the levels' names, on hidden
     columns from each level's nameColumn, sorted by its ordinalColumn.
   Where the key attribute has a NameColumn (the text), a visible column "<level> Text" from it makes the text a
   hierarchy of its own next to the key ([ZCLDIAG].[ZCLDIAG Text]).
   The fact table is the hidden table ZCLVISIT, related to every dimension by its SID_ column, a measure per Measure
   (SUM, its formatString). The captions (dimensions, hierarchies, levels, measures) are an en-US translation.
   What Tabular cannot model is left out: member captions (a member's caption is its name; captionColumn, the key
   attribute's NameColumn), member properties, allMemberName (the All member is "All"), the default drill-through
   action and the cube's name (Tabular's cube is always "Model").

Usage: python scripts/build-ssas-clinic.py
"""
import importlib.util
import json
import pathlib
import re
import subprocess
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parent.parent
INSTANCE = r"localhost\SSAS_TAB"  # SSAS and the SQL Server it reads share the instance name
SQL_DATABASE = "olap4abap_ssas"
SSAS_DATABASE = "ZCLHIER"
SSAS_ACCOUNT = r"NT Service\MSOLAP$SSAS_TAB"
SCHEMA = ROOT / "reference" / "schema" / "ClinicBW.xml"
WORK = ROOT / "data" / "foodmart-bw" / "ssas"  # git-ignored: the generated SQL and TMSL
FACT = "ZCLVISIT"
ROWS_PER_INSERT = 1000  # SQL Server's limit of a VALUES list

spec = importlib.util.spec_from_file_location("bw_reference_db", ROOT / "scripts" / "build-bw-reference-db.py")
bw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bw)


def sql_type(field):
    if field["type"] in ("NUMC", "CHAR", "LANG", "DATS"):
        return f'NVARCHAR({max(field["length"], 1)})'
    if field["type"] == "INT4":
        return "INT"
    if field["type"] == "DEC":
        return f'DECIMAL({field["length"]},{field["decimals"]})'
    raise ValueError(field)


def literal(field, value):
    if field["type"] in ("INT4", "DEC"):
        value = bw.number(value)
        float(value)
        return value
    return "N'" + value.replace("'", "''") + "'"


def table_sql(data):
    table, fields = data["table"], data["fields"]
    columns = ",".join(f'"{f["name"]}" {sql_type(f)} NOT NULL' for f in fields)
    lines = [f'CREATE TABLE "{table}" ({columns});']
    for start in range(0, len(data["rows"]), ROWS_PER_INSERT):
        values = ",\n".join("(" + ",".join(literal(f, v) for f, v in zip(fields, row)) + ")"
                            for row in data["rows"][start:start + ROWS_PER_INSERT])
        lines.append(f'INSERT INTO "{table}" VALUES\n{values};')
    return lines


def sqlcmd(path, database="master"):
    """Runs a script with QUOTED_IDENTIFIER on (-I), as UTF-8 (-f 65001), trusting the instance's certificate (-C)."""
    result = subprocess.run(["sqlcmd", "-S", INSTANCE, "-E", "-C", "-b", "-I", "-f", "65001", "-d", database,
                             "-i", str(path)], capture_output=True, text=True, encoding="utf-8")
    if result.returncode:
        raise SystemExit(f"sqlcmd {path.name} failed:\n{result.stdout}{result.stderr}")


def load_sql_database(schema):
    tables = [t for t in json.loads((bw.EXPORT / "tables.json").read_text(encoding="utf-8")) if "/BIC/" in t
              and re.match(r"/BIC/[FSPT]ZCL", t)]
    lines = []
    for table in tables:
        lines += table_sql(json.loads(bw.table_file(table).read_text(encoding="utf-8")))
    for hierarchy in bw.HIERARCHIES:
        data = json.loads((bw.EXPORT / f"hierarchy_{hierarchy}.json").read_text(encoding="utf-8"))
        lines += table_sql(bw.hierarchy_levels(data))
    views = json.loads((bw.EXPORT / "views.json").read_text(encoding="utf-8"))
    needed = {t.get("name") for t in schema.iter("Table")} | {d.get("table") for d in schema.iter("Dimension")}
    for name, definition in views.items():
        if name in needed:
            lines.append("GO")  # CREATE VIEW must be the first statement of its batch
            lines.append(f'CREATE VIEW "{name}" AS ' + definition.replace("\r", " ").replace("\n", " ") + ";")
    lines += ["GO", f"CREATE USER [{SSAS_ACCOUNT}] FOR LOGIN [{SSAS_ACCOUNT}];",
              f"ALTER ROLE db_datareader ADD MEMBER [{SSAS_ACCOUNT}];"]
    WORK.mkdir(parents=True, exist_ok=True)
    create = WORK / "create.sql"
    create.write_text(f"""IF DB_ID('{SQL_DATABASE}') IS NOT NULL BEGIN
  ALTER DATABASE "{SQL_DATABASE}" SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE "{SQL_DATABASE}"; END;
CREATE DATABASE "{SQL_DATABASE}";
IF SUSER_ID('{SSAS_ACCOUNT}') IS NULL CREATE LOGIN [{SSAS_ACCOUNT}] FROM WINDOWS;
""", encoding="utf-8")
    load = WORK / "load.sql"
    load.write_text("SET NOCOUNT ON;\n" + "\n".join(lines) + "\n", encoding="utf-8")
    sqlcmd(create)
    sqlcmd(load, SQL_DATABASE)
    print(f"{SQL_DATABASE}: {len(tables)} BW tables, {len(bw.HIERARCHIES)} hierarchies, "
          f"{sum(1 for line in lines if line.startswith('CREATE VIEW'))} views")


def quoted(name):
    return '"' + name.replace('"', '""') + '"'


def dimension_table(dimension):
    """The Tabular table of a dimension: its source query, columns, hierarchies and translations."""
    name = dimension.get("name")
    attributes = {a.get("name"): a for a in dimension.findall("DimensionAttribute")}
    key = next(a for a in attributes.values() if a.get("usage") == "Key")
    tables = [dimension.get("table")] if dimension.get("table") else []
    tables += [h.find("Table").get("name") for h in dimension.findall("Hierarchy") if h.find("Table") is not None
               and h.find("Table").get("name") not in tables]
    select, columns, hierarchies, translations = [], [], [], []

    def column(column_name, source, data_type="string", **extra):
        if not any(c["name"] == column_name for c in columns):
            select.append(f'{source} AS {quoted(column_name)}')
            columns.append(dict(name=column_name, dataType=data_type, sourceColumn=column_name, **extra))

    def source(table_name, column_name):
        return f't{tables.index(table_name)}.{quoted(column_name)}'

    key_column = f"{key.get('name')}"
    column(key_column, source(tables[0], key.find("KeyColumn").get("columnName")), "int64", isHidden=True)
    order = key.find("OrderByColumn")
    # a display attribute and its text are hierarchies of their own, captioned as the level's member properties, in
    # the display folders Attributes and Texts; the key attribute's copy (<char> Key) stays hidden
    captions = {p.get("sourceAttribute"): p.get("caption") for p in dimension.iter("Property")}
    for attribute in attributes.values():
        if attribute is not key:
            visible = not attribute.get("name").endswith(" Key")
            folder = dict(displayFolder="Texts" if attribute.get("name").endswith(" Text") else "Attributes")
            column(attribute.get("name"), source(tables[0], attribute.find("KeyColumn").get("columnName")),
                   isHidden=not visible, **(folder if visible else {}))
            if visible and captions.get(attribute.get("name")):
                translations.append(("column", attribute.get("name"), captions[attribute.get("name")]))
    for hierarchy in dimension.findall("Hierarchy"):
        table_name = hierarchy.find("Table").get("name") if hierarchy.find("Table") is not None else tables[0]
        levels = hierarchy.findall("Level")
        if len(levels) == 1:
            level = levels[0]
            sort = key_column
            if order is not None:
                sort = f"{key.get('name')} Order"
                column(sort, source(table_name, order.get("columnName")), isHidden=True)
            column(level.get("name"), source(table_name, level.get("nameColumn")), sortByColumn=sort)
            translations.append(("column", level.get("name"), hierarchy.get("caption")))
            # the text as a hierarchy of its own next to the key, to see how Excel and SSAS treat it (texts repeat
            # and are blank without text, the members are keyed by the text)
            text = key.find("NameColumn")
            if text is not None and table_name == tables[0]:
                column(f"{level.get('name')} Text", source(table_name, text.get("columnName")), displayFolder="Texts")
                translations.append(("column", f"{level.get('name')} Text", f"{hierarchy.get('caption')} (Text)"))
        else:
            hierarchy_levels = []
            for n, level in enumerate(levels):
                level_column = f"{hierarchy.get('name')} {level.get('name')}"
                sort = f"{level_column} Pos"
                column(sort, source(table_name, level.get("ordinalColumn")), "int64", isHidden=True)
                column(level_column, source(table_name, level.get("nameColumn")), sortByColumn=sort, isHidden=True)
                hierarchy_levels.append(dict(name=level.get("name"), ordinal=n, column=level_column))
            hierarchies.append(dict(name=hierarchy.get("name"), levels=hierarchy_levels))
            translations.append(("hierarchy", hierarchy.get("name"), hierarchy.get("caption")))
    joins = " ".join(f"LEFT OUTER JOIN {quoted(t)} t{n} ON t{n}.\"SID\" = t0.\"SID\""
                     for n, t in enumerate(tables) if n)
    query = f"SELECT {', '.join(select)} FROM {quoted(tables[0])} t0 {joins}".strip()
    table = dict(name=name, columns=columns, partitions=[dict(name=name, source=dict(
        type="query", query=query, dataSource="SQL"))])
    if hierarchies:
        table["hierarchies"] = hierarchies
    return table, key_column, translations, dimension.get("caption")


def model(schema):
    cube = schema.find("Cube")
    dimensions = {d.get("name"): d for d in schema.findall("Dimension")}
    tables, relationships, culture_tables = [], [], []
    fact_columns, select = [], []
    for usage in cube.findall("DimensionUsage"):
        table, key_column, translations, caption = dimension_table(dimensions[usage.get("source")])
        tables.append(table)
        foreign_key = usage.get("foreignKey")
        fact_columns.append(dict(name=foreign_key, dataType="int64", sourceColumn=foreign_key, isHidden=True))
        select.append(quoted(foreign_key))
        relationships.append(dict(name=f"{FACT} {usage.get('source')}", fromTable=FACT, fromColumn=foreign_key,
                                  toTable=table["name"], toColumn=key_column))
        culture = dict(name=table["name"], translatedCaption=usage.get("caption") or caption)
        for kind, object_name, object_caption in translations:
            if object_caption:
                culture.setdefault({"column": "columns", "hierarchy": "hierarchies"}[kind], []).append(
                    dict(name=object_name, translatedCaption=object_caption))
        culture_tables.append(culture)
    measures, measure_translations = [], []
    for measure in cube.findall("Measure"):
        assert measure.get("aggregator") == "sum", measure.get("name")
        value_column = f"{measure.get('name')} Value"
        fact_columns.append(dict(name=value_column, dataType="decimal", sourceColumn=value_column, isHidden=True))
        select.append(f'{quoted(measure.get("column"))} AS {quoted(value_column)}')
        measures.append(dict(name=measure.get("name"), expression=f"SUM('{FACT}'[{value_column}])",
                             formatString=measure.get("formatString")))
        measure_translations.append(dict(name=measure.get("name"), translatedCaption=measure.get("caption")))
    fact_table = cube.find("Table").get("name")
    tables.append(dict(name=FACT, isHidden=True, columns=fact_columns, measures=measures, partitions=[dict(
        name=FACT, source=dict(type="query", query=f"SELECT {', '.join(select)} FROM {quoted(fact_table)}",
                               dataSource="SQL"))]))
    culture_tables.append(dict(name=FACT, translatedCaption=cube.get("caption"), measures=measure_translations))
    return dict(
        culture="en-US",
        dataSources=[dict(name="SQL", impersonationMode="impersonateServiceAccount", connectionString=(
            f"Provider=MSOLEDBSQL19.1;Data Source={INSTANCE};Initial Catalog={SQL_DATABASE};"
            "Integrated Security=SSPI;Trust Server Certificate=True"))],
        tables=tables, relationships=relationships,
        cultures=[dict(name="en-US", translations=dict(model=dict(name="Model", tables=culture_tables)))])


def ascmd(path):
    script = (f"Import-Module SqlServer; Invoke-ASCmd -Server '{INSTANCE}' -InputFile '{path}' "
              "| Out-String -Width 100000")
    result = subprocess.run(["powershell", "-NoProfile", "-Command", script], capture_output=True, text=True,
                            encoding="utf-8")
    errors = re.findall(r'<Error [^>]*Description="([^"]*)"', result.stdout)
    if result.returncode or errors:
        raise SystemExit(f"Invoke-ASCmd {path.name} failed:\n" + ("\n".join(errors) or result.stdout + result.stderr))


def deploy(schema):
    database = dict(name=SSAS_DATABASE, compatibilityLevel=1600, model=model(schema))
    tmsl = dict(sequence=dict(operations=[
        {"createOrReplace": {"object": {"database": SSAS_DATABASE}, "database": database}},
        {"refresh": {"type": "full", "objects": [{"database": SSAS_DATABASE}]}}]))
    path = WORK / "deploy.json"
    path.write_text(json.dumps(tmsl, indent=1), encoding="utf-8")
    ascmd(path)
    print(f"SSAS database {SSAS_DATABASE}: {len(database['model']['tables'])} tables, refreshed")


def main():
    schema = ET.parse(SCHEMA).getroot()
    load_sql_database(schema)
    deploy(schema)


if __name__ == "__main__":
    main()
