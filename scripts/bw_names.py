"""olap4abap's unique names of BW hierarchy members as the path of names the reference and members.json use.

olap4abap names a member of a BW hierarchy by the key of its path, InfoObject and name per level, as SSAS names a member
by a composite key: [ZCLDIAG.ZCLDIAG_ICD].[Level 02].&[0HIER_NODE]&[DIAGNOSES]&[0HIER_NODE]&[RESPIRATORY]. The
reference server knows no such hierarchy; it serves ZCLDIAG_ICD as a level hierarchy whose members are named by the
path of names, [ZCLDIAG.ZCLDIAG_ICD].[DIAGNOSES].[RESPIRATORY], which is unique there (every node name occurs once).
as_name_paths rewrites the first form into the second, in plain text and in XML (&amp;), so that answers compare.
"""
import re

KEY = r"&(?:amp;)?\[((?:[^\]]|\]\])*)\]"
BW_UNIQUE_NAME = re.compile(rf"(\[[^\[\]]+\])\.\[Level \d\d\]\.((?:{KEY})+)")


def as_name_path(match):
    keys = re.findall(KEY, match.group(2))
    if len(keys) % 2:
        return match.group(0)
    return match.group(1) + "".join(f".[{name}]" for name in keys[1::2])


def as_name_paths(text):
    """The text with every unique name of a BW hierarchy member as the path of names."""
    return BW_UNIQUE_NAME.sub(as_name_path, text)
