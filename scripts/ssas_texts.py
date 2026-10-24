"""Cleans an answer of the local SSAS before it is kept as a test case (docs/environment.md, SSAS license): what is
SSAS's own (its inline XSD, its error and description texts, its name and version) and what is this machine's (server
and instance names, Windows users, session ids, update timestamps) is replaced or left out, so that a captured answer
holds only our data and the protocol's structure. The capture scripts call as_captured for every SSAS answer
(capture-case.py, capture-execute.py and recapture-cases.py with --ssas); it fails if a text it knows of is left.

Replacements are what olap4abap writes where it has a value (its provider name and the SSAS version it reports,
ZZXXMLA1_CL_XMLA_PROPDEF), else a fixed placeholder; a fault keeps its code, its text is empty.
"""
import os
import re

# the instances and their pumps (scripts/ssas-http-setup.ps1): Tabular (scripts/build-ssas-clinic.py) and
# Multidimensional (scripts/build-ssas-clinic-md.py, the BW hierarchies as parent-child dimensions)
URLS = {"tabular": "http://127.0.0.1:8087/msmdpump.dll", "multidimensional": "http://127.0.0.1:8089/msmdpump.dll"}
URL = URLS["tabular"]
CATALOG = "ZCLHIER"  # the database of both models
MARKER = "Captured from the local SSAS (scripts/ssas_texts.py); recapture-cases.py asks SSAS again.\n"
MARKER_MD = "Captured from the local SSAS Multidimensional (scripts/ssas_texts.py); recapture-cases.py asks it again.\n"
PROVIDER = "olap4abap"
PROVIDER_PROPERTY = "olap4abap XML for Analysis Provider"
VERSION = "13.0.5026.0"  # the SSAS version olap4abap reports
SERVER = "localhost"
USER = "user"
SESSION = "00000000-0000-0000-0000-000000000000"
TIMESTAMP = "2000-01-01T00:00:00"

# columns holding times of the server, not of our data
_TIMESTAMP_ELEMENTS = ["DATE_MODIFIED", "DATE_QUERIED", "CRYPTOKEY_UPDATED", "LAST_SCHEMA_UPDATE", "LAST_DATA_UPDATE",
                       "LastSchemaUpdate", "LastDataUpdate", "CREATED_ON", "LAST_UPDATED"]
# columns of SSAS's own description texts, per rowset (None: every rowset)
_DESCRIPTION_ELEMENTS = {"PropertyDescription": None, "EnumDescription": None, "ElementDescription": None,
                         "Description": "DISCOVER_SCHEMA_ROWSETS", "DESCRIPTION": "MDSCHEMA_FUNCTIONS"}
# columns naming SSAS itself (DBSCHEMA_CATALOGS' ENCRYPTION_LEVEL is a product name)
_PRODUCT_ELEMENTS = ["ENCRYPTION_LEVEL"]
# rowsets that are SSAS's own text as a whole: not captured from SSAS
REFUSED = {"DISCOVER_KEYWORDS": "its rows are SSAS's keyword list"}


def marker(instance):
    """The text of ssas.txt, which marks a case captured from the instance."""
    return MARKER_MD if instance == "multidimensional" else MARKER


def url_of(folder):
    """The pump a case marked by ssas.txt is asked at: the instance its marker names."""
    text = (folder / "ssas.txt").read_text(encoding="utf-8")
    return URLS["multidimensional"] if text == MARKER_MD else URLS["tabular"]


def _machine_names():
    """This machine's names as SSAS writes them, each with its replacement: the Windows user, the instance on the
    computer, the computer."""
    computer = os.environ.get("COMPUTERNAME", "")
    user, domain = os.environ.get("USERNAME", ""), os.environ.get("USERDOMAIN", "")
    names = [(re.escape(domain) + r"\\" + re.escape(user), USER)] if user and domain else []
    if computer:
        names += [(re.escape(computer) + r"\\[A-Za-z0-9_$]+", SERVER), (re.escape(computer), SERVER)]
    return names


def _element(name, value, text):
    return re.sub(rf"(<{name}(?: [^>]*)?>)[^<]*(</{name}>)", lambda m: m.group(1) + value + m.group(2), text)


def _property(name, value, text):
    """The Value of a property's DISCOVER_PROPERTIES row."""
    return re.sub(rf"(<PropertyName>{name}</PropertyName>(?:(?!</row>).)*?<Value>)[^<]*(</Value>)",
                  lambda m: m.group(1) + value + m.group(2), text, flags=re.S)


def as_captured(text, request_type=None):
    """The answer as it is kept in reference/<case>/response.xml."""
    if request_type in REFUSED:
        raise ValueError(f"{request_type} is not captured from SSAS: {REFUSED[request_type]}")
    text = re.sub(r"<(xsd?):schema\b.*?</\1:schema>", "", text, flags=re.S)  # Discover writes xsd:, Execute xs:
    text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
    # faults, errors and warnings: the code stays, the text goes, the source is ours
    text = _element("faultstring", "", text)
    text = re.sub(r'(<(?:Error|Warning)\b[^>]*?\bDescription=")[^"]*(")', r"\1\2", text)
    text = re.sub(r'(<(?:Error|Warning)\b[^>]*?\bSource=")[^"]*(")', rf"\g<1>{PROVIDER}\2", text)
    for name, rowset in _DESCRIPTION_ELEMENTS.items():
        if rowset is None or rowset == request_type:
            text = _element(name, "", text)
    for name in _PRODUCT_ELEMENTS:
        text = _element(name, "", text)
    text = _element("ProviderName", PROVIDER, text)  # DISCOVER_DATASOURCES
    text = _element("DataSourceName", SERVER, text)
    text = _property("ProviderName", PROVIDER_PROPERTY, text)
    for name in ("ProviderVersion", "DBMSVersion"):
        text = _property(name, VERSION, text)
    text = _property("ServerName", SERVER, text)
    for name in _TIMESTAMP_ELEMENTS:
        text = _element(name, TIMESTAMP, text)
    text = re.sub(r'(\bSessionId=")[^"]*(")', rf"\g<1>{SESSION}\2", text)
    text = re.sub(r"IIS APPPOOL\\[A-Za-z0-9_.$-]+", USER, text, flags=re.I)
    for pattern, replacement in _machine_names():
        text = re.sub(pattern, replacement, text, flags=re.I)
    check(text)
    return text


def check(text):
    """Fails if the answer still holds a text that must not be kept."""
    stripped = re.sub(r"schemas[.-]microsoft[.-]com", "", text)  # the protocol's namespaces
    patterns = [r"Microsoft", r"Analysis Services", r"SSAS_TAB", r"SSAS_MULT", r"<xsd?:schema", r"<!--"] + [p for p, _ in _machine_names()]
    left = [m.group(0) for m in (re.search(p, stripped, flags=re.I) for p in patterns) if m]
    if left:
        raise ValueError(f"SSAS answer still holds {left}: add a rule to scripts/ssas_texts.py")
