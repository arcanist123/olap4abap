#!/usr/bin/env python3
"""Generates ZZXXMLA1_CL_SCHEMA_DEF, the definition of a schema (the port of Mondrian's MondrianDef), and its unit tests.

    python scripts/generate-schema-def.py            # writes src/zzxxmla1_cl_schema_def.clas.abap and .testclasses.abap

The class follows the classes eigenbase-xom generated from Mondrian's meta-model Mondrian.xml into
mondrian/mondrian/src/generated/java/mondrian/olap/MondrianDef.java (read by scripts/schemadef/model.py): one ABAP
structure per element class, a parse method per class that reads the element as its Java constructor does (the
attributes with their defaults and legal values, the child elements in the same order, the text), and a write method
per class that writes it as its displayXML does. A field of an abstract class (RelationOrJoin, CubeDimension, ...) is
a ty_node: the element's class name and a reference to its structure.

The tests are the schemas in tests/schemadef/ and the real schemas listed in SCHEMAS: each is read by Mondrian in the
eMondrian container (scripts/schemadef/DumpSchemaDef.java, against the web app's jars) and the test expects
ZZXXMLA1_CL_SCHEMA_DEF to write it back exactly as Mondrian's toXML does, or to fail with Mondrian's message.

Where Mondrian names itself in a message (its Java class names), the expected texts are olap4abap's, through
scripts/reference_texts.py. Both files start with scripts/abap-license-header.txt. Neither file is edited by hand. Deploy both with sapcli (scripts/deploy-schema-def.sh), then scripts/sap-sync.sh pull.
"""
import argparse
import pathlib
import re
import subprocess
import sys
import tempfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent / "schemadef"))
import model  # noqa: E402
from literals import append_lines  # noqa: E402

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from reference_texts import as_olap4abap  # noqa: E402

ROOT = model.ROOT
CONTAINER = "emondrian"
LIB = "/usr/local/tomcat/webapps/emondrian/WEB-INF/lib"
JAVA_PREFIX = "olap4abap.SchemaDef$"  # Mondrian's mondrian.olap.MondrianDef$ (scripts/reference_texts.py)
CASES = ROOT / "tests" / "schemadef"
SCHEMAS = {
    "foodmart_bw": ROOT / "reference" / "schema" / "FoodmartBW.xml",
    "foodmart_server": ROOT / "eMondrian" / "src" / "main" / "webapp" / "WEB-INF" / "schema" / "Foodmart.xml",
    "foodmart_demo": ROOT / "mondrian" / "demo" / "FoodMart.xml",
    "steel_wheels": ROOT / "mondrian" / "demo" / "SteelWheels.xml",
}
# how the tests name the third-party schemas (the others by their path)
LABELS = {
    "foodmart_server": "Foodmart.xml of the reference server",
    "foodmart_demo": "the demo schema FoodMart.xml",
    "steel_wheels": "the demo schema SteelWheels.xml",
}
HEADER = (ROOT / "scripts" / "abap-license-header.txt").read_text(encoding="utf-8").rstrip("\n").split("\n")
# names that would be longer than ABAP allows (30 characters for ty_t_<stem>, parse_<stem>, components)
STEMS = {"CalculatedMemberProperty": "calc_member_property"}
FIELDS = {"attributeHierarchyDisplayFolder": "attr_hierarchy_display_folder"}


def snake(name):
    s = re.sub(r"([A-Z]+)([A-Z][a-z])", r"\1_\2", name)
    s = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", s)
    return s.lower()


class Generator:
    def __init__(self, classes):
        self.classes = classes
        self.concrete = [c for c in classes.values() if not c.abstract]
        self.lines = []

    def stem(self, name):
        s = STEMS.get(name, snake(name))
        assert len("ty_t_" + s) <= 30 and len("parse_" + s) <= 30, name
        return s

    def field(self, java):
        f = FIELDS.get(java, snake(java))
        assert len(f) <= 30, java
        return f

    def polymorphic(self, type_name):
        return model.concrete_subtypes(self.classes, type_name) != [type_name] or self.classes[type_name].abstract

    def matching(self, type_name):
        """The class names a tag may have to match a field of this class (abstract ones fail when constructed)."""
        return [n for n, c in self.classes.items() if c.kind == "class" and model.is_subtype(self.classes, n, type_name)]

    def ordered(self):
        """Concrete classes so that a structure comes after the structures it contains."""
        done, result = set(), []

        def visit(c, path=()):
            if c.name in done:
                return
            assert c.name not in path, path
            for s in c.steps:
                if s["kind"] in ("element", "array") and not self.polymorphic(s["type"]):
                    visit(self.classes[s["type"]], path + (c.name,))
            done.add(c.name)
            result.append(c)

        for c in self.concrete:
            visit(c)
        return result

    def out(self, text=""):
        assert len(text) <= 255, text
        self.lines.append(text)

    # --- definition --------------------------------------------------------------------------------------------

    def component(self, s):
        if s["kind"] == "attribute":
            abap = {"Boolean": "abap_bool"}.get(s["java_type"], "string")
            notes = [f'attribute {s["name"]}']
            if s["java_type"] != "String":
                notes.append(s["java_type"])
            if s["required"]:
                notes.append("required")
            if s["default"] is not None:
                notes.append(f'default {s["default"]}')
            return abap, ", ".join(notes)
        if s["kind"] == "text":
            return "string", "text"
        poly = self.polymorphic(s["type"])
        if s["kind"] == "element":
            abap = "ty_node" if poly else f'REF TO ty_{self.stem(s["type"])}'
            return abap, f'{s["type"]}{", required" if s["required"] else ""}'
        abap = "ty_t_node" if poly else f'ty_t_{self.stem(s["type"])}'
        limits = f', at least {s["min"]}' if s["min"] else ""
        return abap, f'array of {s["type"]}{limits}'

    def definition(self):
        o = self.out
        for line in HEADER:
            o(line)
        o('"! The definition of a schema: the port of SchemaDef, the classes eigenbase-xom generates from')
        o('"! the reference\'s meta-model of a schema. Generated by scripts/generate-schema-def.py from the reference\'s classes: do not')
        o('"! edit by hand. parse reads a schema as the reference does (XOMUtil\'s parser, then new SchemaDef.Schema): one')
        o('"! structure per element class, attributes with their defaults and legal values, child elements in the order of')
        o('"! the definition, an error with the reference\'s message. to_xml writes a definition as toXML does.')
        o('"! Values as the reference holds them: a String attribute or a text that is null is initial (an empty attribute is no')
        o('"! attribute), a Boolean is abap_true, abap_false or abap_undefined (null), an Integer or Long is its decimal text,')
        o('"! an element a reference (not bound: null), an array a table. A field whose class is abstract (RelationOrJoin,')
        o('"! CubeDimension, ...) is a ty_node with the class of the element and a reference to its structure, e.g.')
        o('"! CAST zzxxmla1_cl_schema_def=>ty_table( node-def ) for node-name Table.')
        o("CLASS zzxxmla1_cl_schema_def DEFINITION")
        o("  PUBLIC")
        o("  FINAL")
        o("  CREATE PRIVATE.")
        o("")
        o("  PUBLIC SECTION.")
        o("    TYPES:")
        o('      "! An element of a field whose class is abstract: name is the class of the element (getName, e.g. Table),')
        o('      "! def a reference to its structure (e.g. ty_table); initial for null.')
        o("      BEGIN OF ty_node,")
        o("        name TYPE string,")
        o("        def  TYPE REF TO data,")
        o("      END OF ty_node,")
        o("      ty_t_node TYPE STANDARD TABLE OF ty_node WITH EMPTY KEY.")
        for c in self.ordered():
            stem = self.stem(c.name)
            o("    TYPES:")
            o(f'      "! {c.name}')
            o(f"      BEGIN OF ty_{stem},")
            fields = [(self.field(s["field"]),) + self.component(s) for s in c.steps]
            assert len({f for f, _, _ in fields}) == len(fields), c.name
            width = max(len(f) for f, _, _ in fields)
            for f, abap, note in fields:
                o(f"        {f.ljust(width)} TYPE {abap},  \" {note}")
            o(f"      END OF ty_{stem},")
            o(f"      ty_t_{stem} TYPE STANDARD TABLE OF ty_{stem} WITH EMPTY KEY.")
        o("")
        o('    "! Reads a schema: the root element, whatever its name, as a Schema.')
        o("    CLASS-METHODS parse")
        o("      IMPORTING xml           TYPE string")
        o("      RETURNING VALUE(result) TYPE ty_schema")
        o("      RAISING   zzxxmla1_cx_xom.")
        o('    "! Writes a schema as ElementDef.toXML does.')
        o("    CLASS-METHODS to_xml")
        o("      IMPORTING schema        TYPE ty_schema")
        o("      RETURNING VALUE(result) TYPE string.")
        o("")
        o("  PROTECTED SECTION.")
        o("  PRIVATE SECTION.")
        o('    "! ElementDef.constructElement of an element of an abstract class: the structure of the element\'s class.')
        o("    CLASS-METHODS parse_node")
        o("      IMPORTING element       TYPE REF TO if_ixml_element")
        o("      RETURNING VALUE(result) TYPE ty_node")
        o("      RAISING   zzxxmla1_cx_xom.")
        o('    "! The comma-separated names as a table (legal values, classes of a field).')
        o("    CLASS-METHODS value_list")
        o("      IMPORTING text          TYPE string")
        o("      RETURNING VALUE(result) TYPE string_table.")
        o("    CLASS-METHODS write_node")
        o("      IMPORTING node TYPE ty_node")
        o("                out  TYPE REF TO zzxxmla1_cl_xom_output.")
        for c in self.concrete:
            stem = self.stem(c.name)
            o(f"    CLASS-METHODS parse_{stem}")
            o("      IMPORTING element       TYPE REF TO if_ixml_element")
            o(f"      RETURNING VALUE(result) TYPE ty_{stem}")
            o("      RAISING   zzxxmla1_cx_xom.")
            o(f"    CLASS-METHODS write_{stem}")
            o(f"      IMPORTING def TYPE ty_{stem}")
            o("                out TYPE REF TO zzxxmla1_cl_xom_output.")
        o("ENDCLASS.")

    # --- implementation ----------------------------------------------------------------------------------------

    def string_list(self, items):
        assert all("," not in i and "`" not in i for i in items), items
        return "value_list( `" + ",".join(items) + "` )"

    def values(self, c, name):
        """A legal values array of the class or, inherited, of a superclass."""
        while name not in c.values:
            c = self.classes[c.parent]
        return c.values[name]

    def parse_method(self, c):
        o = self.out
        stem = self.stem(c.name)
        o(f"  METHOD parse_{stem}.")
        o("    TRY.")
        o("        DATA(parser) = NEW zzxxmla1_cl_xom_parser( element ).")
        if any(s["kind"] in ("element", "array") for s in c.steps):
            o("        DATA child TYPE REF TO if_ixml_element.")
        for s in c.steps:
            f = self.field(s["field"])
            if s["kind"] == "attribute":
                args = [f'name = `{s["name"]}`']
                if s["default"] is not None:
                    args.append(f'default = `{s["default"]}`')
                if s["required"]:
                    args.append("required = abap_true")
                java_type = s["java_type"]
                if java_type == "Boolean":
                    call = "get_boolean"
                elif java_type in ("Integer", "Long"):
                    call = "get_number"
                    args.append(f"java_type = `{java_type}`")
                else:
                    assert java_type == "String", java_type
                    call = "get_string"
                    if s["values"]:
                        args.append(f'values = {self.string_list(self.values(c, s["values"]))}')
                self.call(f"        result-{f} = parser->{call}( ", args, " )")
            elif s["kind"] == "text":
                o(f"        result-{f} = parser->get_text( ).")
            else:
                classes = self.string_list(self.matching(s["type"]))
                java = f'java_class = `{JAVA_PREFIX}{s["type"]}`'
                poly = self.polymorphic(s["type"])
                if s["kind"] == "element":
                    req = "abap_true" if s["required"] else "abap_false"
                    self.call("        child = parser->get_element( ", [f"classes = {classes}", java, f"required = {req}"], " )")
                    o("        IF child IS BOUND.")
                    if poly:
                        o(f"          result-{f} = parse_node( child ).")
                    else:
                        o(f'          result-{f} = NEW #( parse_{self.stem(s["type"])}( child ) ).')
                    o("        ENDIF.")
                else:
                    head = "        LOOP AT parser->get_array( "
                    self.call(head, [f"classes = {classes}", java, f'min = {s["min"]}', f'max = {s["max"]}'],
                              " ) INTO child")
                    target = "parse_node( child )" if poly else f'parse_{self.stem(s["type"])}( child )'
                    o(f"          INSERT {target} INTO TABLE result-{f}.")
                    o("        ENDLOOP.")
        o("      CATCH zzxxmla1_cx_xom INTO DATA(error).")
        o(f"        RAISE EXCEPTION TYPE zzxxmla1_cx_xom EXPORTING error_message = |In {c.name}: {{ error->error_message }}|.")
        o("    ENDTRY.")
        o("  ENDMETHOD.")
        o("")

    def call(self, head, args, tail, end="."):
        """A call on one line if it fits, else one argument per line."""
        line = head + " ".join(args) + tail + end
        if len(line) <= 120:
            self.out(line)
            return
        indent = " " * len(head)
        self.out(head + args[0])
        for a in args[1:-1]:
            self.out(indent + a)
        self.out(indent + args[-1] + tail + end)

    def write_method(self, c):
        o = self.out
        stem = self.stem(c.name)
        attrs = [s for s in c.steps if s["kind"] == "attribute"]
        by_name = {s["name"]: s for s in attrs}
        o(f"  METHOD write_{stem}.")
        if attrs:
            o(f"    out->begin_tag( name = `{c.name}` attributes = VALUE #(")
            for name in c.display_attrs:
                s = by_name[name]
                value = f'def-{self.field(s["field"])}'
                if s["java_type"] == "Boolean":
                    value = f"zzxxmla1_cl_xom_output=>boolean_text( {value} )"
                o(f"      ( name = `{name}` value = {value} )")
            o("    ) ).")
        else:
            o(f"    out->begin_tag( `{c.name}` ).")
        steps = {s["field"]: s for s in c.steps}
        n = 0
        for java_field in c.display_children:
            s = steps[java_field]
            f = self.field(java_field)
            poly = self.polymorphic(s["type"])
            if s["kind"] == "element":
                if poly:
                    o(f"    write_node( node = def-{f} out = out ).")
                else:
                    o(f"    IF def-{f} IS BOUND.")
                    o(f'      write_{self.stem(s["type"])}( def = def-{f}->* out = out ).')
                    o("    ENDIF.")
            else:
                n += 1
                o(f"    LOOP AT def-{f} INTO DATA(item_{n}).")
                if poly:
                    o(f"      write_node( node = item_{n} out = out ).")
                else:
                    o(f'      write_{self.stem(s["type"])}( def = item_{n} out = out ).')
                o("    ENDLOOP.")
        texts = [s for s in c.steps if s["kind"] == "text"]
        assert len(texts) == (1 if c.display_text else 0), c.name
        for s in texts:
            o(f'    out->cdata( def-{self.field(s["field"])} ).')
        o(f"    out->end_tag( `{c.name}` ).")
        o("  ENDMETHOD.")
        o("")

    def implementation(self):
        o = self.out
        o("")
        o("")
        o("")
        o("CLASS zzxxmla1_cl_schema_def IMPLEMENTATION.")
        o("")
        o("  METHOD parse.")
        o("    result = parse_schema( zzxxmla1_cl_xom_parser=>parse_document( xml ) ).")
        o("  ENDMETHOD.")
        o("")
        o("  METHOD to_xml.")
        o("    DATA(out) = NEW zzxxmla1_cl_xom_output( ).")
        o("    write_schema( def = schema out = out ).")
        o("    result = out->get_output( ).")
        o("  ENDMETHOD.")
        o("")
        o("  METHOD value_list.")
        o("    SPLIT text AT `,` INTO TABLE result.")
        o("  ENDMETHOD.")
        o("")
        o("  METHOD parse_node.")
        o("    result-name = zzxxmla1_cl_xom_parser=>class_name( element ).")
        o("    CASE result-name.")
        for c in self.concrete:
            o(f"      WHEN `{c.name}`.")
            o(f"        result-def = NEW ty_{self.stem(c.name)}( parse_{self.stem(c.name)}( element ) ).")
        o("      WHEN OTHERS.")
        o("        \" an abstract class: Class.newInstance fails with an InstantiationException without message")
        o("        RAISE EXCEPTION TYPE zzxxmla1_cx_xom")
        o(f"          EXPORTING error_message = |Unable to instantiate object of class {JAVA_PREFIX}{{ result-name }}: null|.")
        o("    ENDCASE.")
        o("  ENDMETHOD.")
        o("")
        o("  METHOD write_node.")
        o("    FIELD-SYMBOLS <def> TYPE any.")
        o("    IF node-def IS NOT BOUND.")
        o("      RETURN.")
        o("    ENDIF.")
        o("    ASSIGN node-def->* TO <def>.")
        o("    CASE node-name.")
        for c in self.concrete:
            stem = self.stem(c.name)
            o(f"      WHEN `{c.name}`.")
            o(f"        write_{stem}( def = <def> out = out ).")
        o("    ENDCASE.")
        o("  ENDMETHOD.")
        o("")
        for c in self.concrete:
            self.parse_method(c)
            self.write_method(c)
        o("ENDCLASS.")

    def source(self):
        self.lines = []
        self.definition()
        self.implementation()
        return "\n".join(self.lines)  # as SAP returns a source: no line break at the end


# --- tests -------------------------------------------------------------------------------------------------------

def run_reference(files):
    """The reference server's reading of each schema file: its toXML, or "ERROR: <message>", in olap4abap's texts."""
    with tempfile.TemporaryDirectory() as tmp:
        names = []
        for name, path in files.items():
            text = path.read_text(encoding="utf-8").replace("\r\n", "\n")
            (pathlib.Path(tmp) / f"{name}.xml").write_text(text, encoding="utf-8", newline="\n")
            names.append(f"{name}.xml")
        java = ROOT / "scripts" / "schemadef" / "DumpSchemaDef.java"
        subprocess.run(["docker", "exec", CONTAINER, "rm", "-rf", "/tmp/schemadef"], check=True)
        subprocess.run(["docker", "cp", tmp, f"{CONTAINER}:/tmp/schemadef"], check=True)
        subprocess.run(["docker", "cp", str(java), f"{CONTAINER}:/tmp/schemadef/DumpSchemaDef.java"], check=True)
        output = subprocess.run(
            ["docker", "exec", CONTAINER, "sh", "-c",
             f"cd /tmp/schemadef && java -Dfile.encoding=UTF-8 -Dstdout.encoding=UTF-8 -cp '{LIB}/*:.' "
             f"DumpSchemaDef.java {' '.join(names)}"],
            check=True, capture_output=True).stdout.decode("utf-8")
    results, current = {}, None
    for line in output.split("\n"):
        if line.startswith("=== "):
            current = line[4:-4]
            results[current] = []
        elif current is not None:
            results[current].append(line)
    return {name: as_olap4abap("\n".join(lines).rstrip("\n")) for name, lines in results.items()}


def tests(files, expected):
    lines = list(HEADER)
    out = lines.append
    out('"! Generated by scripts/generate-schema-def.py: do not edit by hand. Each test reads a schema (from tests/schemadef')
    out('"! or a real schema) and expects it written back exactly as SchemaDef.Schema.toXML writes it, or the')
    out('"! error with the reference\'s message (scripts/schemadef/DumpSchemaDef.java in the reference server\'s container).')
    out("CLASS ltc_schema_def DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.")
    out("  PRIVATE SECTION.")
    for name, path in files.items():
        out(f'    "! {LABELS.get(name) or path.relative_to(ROOT).as_posix()}')
        out(f"    METHODS {name} FOR TESTING.")
    out("    METHODS assert_schema")
    out("      IMPORTING input TYPE string_table")
    out("                exp   TYPE string_table.")
    out("ENDCLASS.")
    out("")
    out("CLASS ltc_schema_def IMPLEMENTATION.")
    out("")
    for name, path in files.items():
        assert len(name) <= 30, name
        out(f"  METHOD {name}.")
        out("    DATA input TYPE string_table.")
        out("    DATA exp TYPE string_table.")
        append_lines(out, path.read_text(encoding="utf-8").replace("\r\n", "\n").rstrip("\n"), "input")
        append_lines(out, expected[name], "exp")
        out("    assert_schema( input = input exp = exp ).")
        out("  ENDMETHOD.")
        out("")
    out("  METHOD assert_schema.")
    out("    \" the definition written back line by line, or the error as the reference's dump prints it")
    out("    DATA act TYPE string_table.")
    out("    TRY.")
    out("        DATA(xml) = zzxxmla1_cl_schema_def=>to_xml(")
    out("          zzxxmla1_cl_schema_def=>parse( concat_lines_of( table = input sep = cl_abap_char_utilities=>newline ) ) ).")
    out("        SPLIT xml AT cl_abap_char_utilities=>newline INTO TABLE act.")
    out("      CATCH zzxxmla1_cx_xom INTO DATA(error).")
    out("        act = VALUE #( ( |ERROR: { error->error_message }| ) ).")
    out("    ENDTRY.")
    out("    cl_abap_unit_assert=>assert_equals( act = act exp = exp ).")
    out("  ENDMETHOD.")
    out("")
    out("ENDCLASS.")
    for line in lines:
        assert len(line) <= 255, line
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", default=str(ROOT / "src"), help="directory for the two files (default src/)")
    args = parser.parse_args()
    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    classes = model.load()
    (out / "zzxxmla1_cl_schema_def.clas.abap").write_text(Generator(classes).source(), encoding="utf-8", newline="\n")

    files = {p.stem: p for p in sorted(CASES.glob("*.xml"))}
    files.update(SCHEMAS)
    expected = run_reference(files)
    (out / "zzxxmla1_cl_schema_def.clas.testclasses.abap").write_text(tests(files, expected), encoding="utf-8",
                                                                         newline="\n")
    for name in files:
        status = "error" if expected[name].startswith("ERROR: ") else "ok"
        print(f"{name}: {status}")


if __name__ == "__main__":
    main()
