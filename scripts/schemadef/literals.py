"""ABAP string templates for embedding text (a schema, an expected output) in generated ABAP source: one APPEND per
line, long lines split into pieces, so that no source line exceeds ABAP's limit. Used by scripts/generate-schema-def.py."""

PIECE = 180  # characters of a literal per source line


def template(text):
    return (text.replace("\\", "\\\\").replace("|", "\\|").replace("{", "\\{").replace("}", "\\}")
            .replace("\t", "\\t").replace("\r", "\\r"))


def pieces(text):
    """The text as string template pieces of at most PIECE characters, not splitting an escape sequence."""
    escaped = template(text)
    result, start = [], 0
    while start < len(escaped) or not result:
        end = min(start + PIECE, len(escaped))
        while 0 < end < len(escaped) and escaped[end - 1] == "\\" and \
                (len(escaped[start:end]) - len(escaped[start:end].rstrip("\\"))) % 2 == 1:
            end -= 1
        result.append(escaped[start:end])
        start = end
    return result


def append_lines(out, text, table):
    for line in text.split("\n"):
        parts = pieces(line)
        if len(parts) == 1:
            out(f"    APPEND |{parts[0]}| TO {table}.")
        else:
            out(f"    APPEND |{parts[0]}|")
            for p in parts[1:-1]:
                out(f"        && |{p}|")
            out(f"        && |{parts[-1]}| TO {table}.")
