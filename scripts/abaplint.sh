#!/usr/bin/env bash
# Checks src/ against the ABAP syntax of NetWeaver 7.50, the release the code must run on (docs/mvp-scope.md). The
# development system is newer and activates syntax 7.50 rejects, so run this after every change.
#
#   scripts/abaplint.sh
#
# abaplint (run with npx, version pinned below) parses offline with the grammar of the release in abaplint.json and
# checks the syntax against stubs: SAP's standard objects from github.com/abaplint/deps (abaplint clones it into a
# temporary folder) and our own in abaplint/stubs/ (table ZZXXMLA1_FILE, which ZZXXMLA1_CL_CREATE_TABLES creates, and
# the BW type pools).
# check_syntax skips ZZXXMLA1_MAIN_ENDPOINT only because the deps stub of IF_HTTP_SERVER lacks SSL_ACTIVE; its 7.50
# grammar is still checked. abaplint does not check the parameters of built-in functions, so the release-specific
# ones are searched for below (pcre = needs 7.55).
set -euo pipefail
cd "$(dirname "$0")/.."

ABAPLINT_VERSION=2.120.65
status=0
npx -y "@abaplint/cli@$ABAPLINT_VERSION" abaplint.json || status=1

if grep -n -i -E "\bpcre *=" src/*.abap; then
  echo "error: pcre = (built-in function parameter) needs 7.55; use regex = on 7.50" >&2
  status=1
fi
exit $status
