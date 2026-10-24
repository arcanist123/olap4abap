"""Checks that nothing the repository publishes breaks our license rules (docs/environment.md, SAP license; CLAUDE.md,
Conventions and Working agreements):

- timing: no runtimes or speed comparisons (SAP's license, section 3.a.c; SSAS's license too). Every number with a time
  unit is a hit; one that times something else (a build, a refresh interval) is allowed in the allow-list.
- sap-internal: none of the SAP-internal names listed in the git-ignored .local/sap-internal-names.txt (one per line,
  # for comments): the classes, methods and programs whose inside we must not describe (section 13). Without the file
  the rule checks nothing.
- reference-name: no Mondrian or eMondrian in our code (src/*.abap after the license header, web/): comments call it
  the reference; Java names (MondrianDef, mondrian.olap) are allowed, they name what a class ports.

Usage: python scripts/license-scan.py              tracked files of the working tree
       python scripts/license-scan.py --staged     the staged files as staged (the pre-commit hook)
       python scripts/license-scan.py --message F  the commit message in file F (the commit-msg hook)
The hooks are in .githooks (git config core.hooksPath .githooks). An exception is a line of
scripts/license-scan-allow.txt: rule | path glob | regex of the matched line | reason (required).
"""
import fnmatch
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
ALLOW_FILE = ROOT / "scripts" / "license-scan-allow.txt"
NAMES_FILE = ROOT / ".local" / "sap-internal-names.txt"
MESSAGE_PATH = "COMMIT_MSG"

# captured answers of the reference servers and Mondrian's test statements: their data, not our text
EXCLUDED = ["reference/*", "tests/*", "LICENSE", "NOTICE", "*.png", "*.ico", "*.zip", "*.gz",
            "scripts/license-scan-allow.txt"]
TIMING = re.compile(
    r"\b\d+(?:[.,]\d+)?\s?(?:ms|s|secs?|seconds?|minutes?)\b"
    r"|\b\d+(?:[.,]\d+)?\s?(?:x|times)\s+(?:faster|slower|quicker)\b"
    r"|\bspeed-?up of\b",
    re.IGNORECASE)
REFERENCE_NAME = re.compile(r"\be?mondrian\b(?!\.)", re.IGNORECASE)
CODE_FILES = ["src/*.abap", "web/*"]


def read_allow_list():
    rules = []
    for number, line in enumerate(ALLOW_FILE.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        fields = [field.strip() for field in line.split("|", 3)]
        if len(fields) != 4 or len(fields[3]) < 10:
            sys.exit(f"{ALLOW_FILE.name}:{number}: needs rule | path glob | regex | reason")
        rule, glob, pattern, reason = fields
        if rule not in ("timing", "sap-internal", "reference-name"):
            sys.exit(f"{ALLOW_FILE.name}:{number}: unknown rule {rule}")
        regex = re.compile(pattern)
        if not pattern or regex.search("") or regex.fullmatch("x" * 40):
            sys.exit(f"{ALLOW_FILE.name}:{number}: the regex must name the allowed text, not match anything")
        rules.append((rule, glob, regex))
    return rules


def read_names():
    if not NAMES_FILE.exists():
        return None
    names = [line.strip() for line in NAMES_FILE.read_text(encoding="utf-8").splitlines()
             if line.strip() and not line.startswith("#")]
    if not names:
        return None
    return re.compile(r"(?<![\w/])(?:" + "|".join(re.escape(name) for name in names) + r")(?![\w])", re.IGNORECASE)


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, check=True).stdout


def code_lines(lines):
    """The lines of a code file without its license header (the leading comment block of an ABAP include)."""
    index = 0
    while index < len(lines) and lines[index].startswith("*"):
        index += 1
    return range(index, len(lines))


def scan(path, text, names, allowed):
    hits = []
    lines = text.splitlines()
    checks = [("timing", TIMING, range(len(lines)))]
    if names:
        checks.append(("sap-internal", names, range(len(lines))))
    if any(fnmatch.fnmatch(path, glob) for glob in CODE_FILES):
        checks.append(("reference-name", REFERENCE_NAME, code_lines(lines)))
    for rule, regex, numbers in checks:
        for index in numbers:
            line = lines[index]
            if not regex.search(line):
                continue
            if any(r == rule and fnmatch.fnmatch(path, glob) and allow.search(line) for r, glob, allow in allowed):
                continue
            hits.append(f"{path}:{index + 1}: {rule}: {line.strip()[:160]}")
    return hits


def main(argv):
    allowed = read_allow_list()
    names = read_names()
    if argv[:1] == ["--message"]:
        text = pathlib.Path(argv[1]).read_text(encoding="utf-8")
        text = "\n".join(line for line in text.splitlines() if not line.startswith("#"))
        files = [(MESSAGE_PATH, text)]
    else:
        if argv[:1] == ["--staged"]:
            paths = git("diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z").decode().split("\0")
            read = lambda path: git("show", f":{path}")
        else:
            paths = git("ls-files", "-z").decode().split("\0")
            read = lambda path: (ROOT / path).read_bytes()
        files = []
        for path in filter(None, paths):
            if any(fnmatch.fnmatch(path, glob) for glob in EXCLUDED) or not (argv or (ROOT / path).is_file()):
                continue
            data = read(path)
            if b"\0" in data[:8000]:
                continue
            files.append((path, data.decode("utf-8", errors="replace")))
    hits = [hit for path, text in files for hit in scan(path, text, names, allowed)]
    for hit in hits:
        print(hit)
    if hits:
        print(f"\n{len(hits)} hit(s) of the license rules (scripts/license-scan.py): remove them, or allow one in "
              f"{ALLOW_FILE.relative_to(ROOT).as_posix()} with its reason.", file=sys.stderr)
        return 1
    if names is None:
        print("note: no .local/sap-internal-names.txt, the sap-internal rule checked nothing", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
