"""The texts in which olap4abap answers differently from the reference server on purpose: its name where the reference
server names itself (error prefixes, fault actor, provider name, Java class names in messages). Everything else in the
answers is the same, so the comparisons (scripts/xmla_test.py, scripts/compare-applicable.py) and the generators of test
expectations (scripts/generate-schema-def.py) put both answers through as_olap4abap before they compare them.
"""
import re

# (pattern, replacement), applied in this order; specific enough not to touch request data such as MondrianFoodMart
_RULES = [
    (r"mondrian\.olap\.fun\.MondrianEvaluationException", "olap4abap.EvaluationException"),
    (r"mondrian\.olap\.MondrianDef\$", "olap4abap.SchemaDef$"),
    (r"mondrian\.xmla\.", "olap4abap."),
    (r"Mondrian Error:", "olap4abap Error:"),
    (r"<faultactor>Mondrian</faultactor>", "<faultactor>olap4abap</faultactor>"),
    (r"The Mondrian XML:", "The olap4abap XML:"),
    (r"The emondrian DAX module", "The olap4abap DAX module"),
    (r"emondrian/dax/", "olap4abap/dax/"),
    (r"Mondrian also allows locale codes", "olap4abap also allows locale codes"),
    (r"Mondrian XML for Analysis Provider", "olap4abap XML for Analysis Provider"),
    (r"Mondrian XMLA Provider", "olap4abap XMLA Provider"),
    (r"<ProviderName>Mondrian</ProviderName>", "<ProviderName>olap4abap</ProviderName>"),
    (r"Provider=mondrian\b", "Provider=olap4abap"),
]


def as_olap4abap(text):
    """The text with the reference server's self-references written as olap4abap writes them (idempotent)."""
    for pattern, replacement in _RULES:
        text = re.sub(pattern, lambda _m, r=replacement: r, text)
    return text
