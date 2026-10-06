"""Reads Mondrian's generated MondrianDef.java (the classes eigenbase-xom builds from Mondrian.xml) into a model:
per class its superclass, interfaces, abstractness, the parse steps of its DOMWrapper constructor in order, and the
attribute and child order of displayXML. Used by scripts/generate-schema-def.py."""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
SOURCE = ROOT / "mondrian" / "mondrian" / "src" / "generated" / "java" / "mondrian" / "olap" / "MondrianDef.java"

CLASS_RE = re.compile(r"^\tpublic (?:static )?(abstract )?(class|interface) (\w+)"
                      r"(?: extends ([\w.]+))?(?: implements ([\w., ]+))?", re.M)
ATTR_RE = re.compile(r'^\t\t\t\t(\w+) = \((\w+)\)_parser\.getAttribute\("(\w+)", "(\w+)", (null|"[^"]*"), '
                     r'(null|_\w+_values), (true|false)\);', re.M)
ELEM_RE = re.compile(r'^\t\t\t\t(\w+) = \((\w+)\)_parser\.getElement\((\w+)\.class, (true|false)\);', re.M)
ARRAY_RE = re.compile(r'^\t\t\t\t_tempArray = _parser\.getArray\((\w+)\.class, (\d+), (\d+)\);\n'
                      r'\t\t\t\t(\w+) = new \w+\[_tempArray\.length\];', re.M)
TEXT_RE = re.compile(r'^\t\t\t\t(\w+) = _parser\.getText\(\);', re.M)
VALUES_RE = re.compile(r'public static final String\[\] (_\w+_values) = \{([^}]*)\};')
ADD_RE = re.compile(r'\.add\("(\w+)", (\w+)\)')
DISPLAY_CHILD_RE = re.compile(r'displayXMLElement(?:Array)?\(_out, (?:\(org\.eigenbase\.xom\.ElementDef\) )?(\w+)\);')


class JavaClass:
    def __init__(self, name, kind, abstract, parent, interfaces):
        self.name = name
        self.kind = kind            # class or interface
        self.abstract = abstract or kind == "interface"
        self.parent = parent        # None for ElementDef / NodeDef
        self.interfaces = interfaces
        self.steps = []             # parse steps in constructor order
        self.values = {}            # _x_values -> list
        self.display_attrs = []     # attribute names in displayXML order
        self.display_children = []  # child field names in displayXML order
        self.has_constructor = False


def load(path=SOURCE):
    text = path.read_text(encoding="utf-8")
    matches = list(CLASS_RE.finditer(text))
    classes = {}
    for i, m in enumerate(matches):
        body = text[m.end(): matches[i + 1].start() if i + 1 < len(matches) else len(text)]
        parent = m.group(4)
        if parent and parent.startswith("org.eigenbase"):
            parent = None
        interfaces = [s.strip() for s in (m.group(5) or "").split(",") if s.strip()]
        c = JavaClass(m.group(3), m.group(2), bool(m.group(1)), parent, interfaces)
        c.has_constructor = f"public {c.name}(org.eigenbase.xom.DOMWrapper _def)" in body
        ctor = body.split("public String getName()")[0]
        steps = []
        for r in ATTR_RE.finditer(ctor):
            steps.append((r.start(), dict(kind="attribute", field=r.group(1), java_type=r.group(4), name=r.group(3),
                                          default=None if r.group(5) == "null" else r.group(5)[1:-1],
                                          values=None if r.group(6) == "null" else r.group(6),
                                          required=r.group(7) == "true")))
        for r in ELEM_RE.finditer(ctor):
            steps.append((r.start(), dict(kind="element", field=r.group(1), type=r.group(3), required=r.group(4) == "true")))
        for r in ARRAY_RE.finditer(ctor):
            steps.append((r.start(), dict(kind="array", field=r.group(4), type=r.group(1),
                                          min=int(r.group(2)), max=int(r.group(3)))))
        for r in TEXT_RE.finditer(ctor):
            steps.append((r.start(), dict(kind="text", field=r.group(1))))
        c.steps = [s for _, s in sorted(steps, key=lambda p: p[0])]
        for v in VALUES_RE.finditer(body):
            c.values[v.group(1)] = re.findall(r'"([^"]*)"', v.group(2))
        display = body.split("public void displayXML(")[1].split("public boolean displayDiff(")[0] \
            if "public void displayXML(" in body else ""
        c.display_attrs = [a.group(1) for a in ADD_RE.finditer(display)]
        c.display_children = DISPLAY_CHILD_RE.findall(display)
        c.display_text = "_out.cdata(" in display
        classes[c.name] = c
    return classes


def is_subtype(classes, name, of):
    """Java's of.isAssignableFrom(name)."""
    seen = [name]
    while seen:
        n = seen.pop()
        if n == of:
            return True
        c = classes.get(n)
        if c is None:
            continue
        if c.parent:
            seen.append(c.parent)
        seen.extend(c.interfaces)
    return False


def concrete_subtypes(classes, of):
    return [n for n, c in classes.items() if not c.abstract and c.has_constructor and is_subtype(classes, n, of)]


if __name__ == "__main__":
    classes = load()
    concrete = [c for c in classes.values() if not c.abstract]
    print(len(classes), "classes,", len(concrete), "concrete")
    for c in classes.values():
        if not c.abstract and not c.has_constructor:
            print("NO CONSTRUCTOR", c.name)
        fields = [s["field"] for s in c.steps]
        attrs = [s["name"] for s in c.steps if s["kind"] == "attribute"]
        if not c.abstract and attrs != c.display_attrs:
            print("ATTR ORDER DIFFERS", c.name, attrs, c.display_attrs)
        kids = [s["field"] for s in c.steps if s["kind"] in ("element", "array")]
        if not c.abstract and kids != c.display_children:
            print("CHILD ORDER DIFFERS", c.name, kids, c.display_children)
    used = {s["type"] for c in classes.values() for s in c.steps if s["kind"] in ("element", "array")}
    for t in sorted(used):
        subs = concrete_subtypes(classes, t)
        if subs != [t]:
            print("POLYMORPHIC", t, subs)
    for c in classes.values():
        for s in c.steps:
            if s["kind"] == "attribute" and s["java_type"] not in ("String", "Boolean"):
                print("TYPE", c.name, s["name"], s["java_type"], s["default"])
