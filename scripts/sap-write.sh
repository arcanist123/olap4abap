#!/usr/bin/env bash
# Writes ABAP class sources from src/ into SAP with sapcli and activates them, unchanged byte for byte (the ABAP FS
# edit tool decodes backslash escapes). The classes must exist. Logon data from .env.sap, as scripts/sap-sync.sh.
#
#   scripts/sap-write.sh zzxxmla1_cl_sql [zzxxmla1_cl_schema ...]   # main source and, if present, local types and test include
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
ENV_FILE="${SAP_ENV_FILE:-$ROOT/.env.sap}"
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi
: "${SAP_ASHOST:?set SAP_ASHOST in .env.sap}"
: "${SAP_CLIENT:?set SAP_CLIENT in .env.sap}"
: "${SAP_USER:?set SAP_USER in .env.sap}"
: "${SAP_PASSWORD:?set SAP_PASSWORD in .env.sap}"
export SAP_PASSWORD
SAPCLI=(sapcli --ashost "$SAP_ASHOST" --client "$SAP_CLIENT" --user "$SAP_USER")
[ -n "${SAP_PORT:-}" ] && SAPCLI+=(--port "$SAP_PORT")
[ "${SAP_USE_SSL:-false}" = "true" ] || SAPCLI+=(--no-ssl)

status=0
for base in "$@"; do
  base="$(echo "$base" | tr '[:upper:]' '[:lower:]')"
  name="$(echo "$base" | tr '[:lower:]' '[:upper:]')"
  kind="clas"
  [ -f "src/$base.intf.abap" ] && kind="intf"
  if [ "$kind" = "intf" ]; then
    "${SAPCLI[@]}" interface write "$name" "src/$base.intf.abap" >/dev/null
  else
    # the local types first: the main source may use them
    if [ -f "src/$base.clas.locals_def.abap" ]; then
      "${SAPCLI[@]}" class write --type definitions "$name" "src/$base.clas.locals_def.abap" >/dev/null
    fi
    if [ -f "src/$base.clas.locals_imp.abap" ]; then
      "${SAPCLI[@]}" class write --type implementations "$name" "src/$base.clas.locals_imp.abap" >/dev/null
    fi
    "${SAPCLI[@]}" class write --type main "$name" "src/$base.clas.abap" >/dev/null
    if [ -f "src/$base.clas.testclasses.abap" ]; then
      "${SAPCLI[@]}" class write --type testclasses "$name" "src/$base.clas.testclasses.abap" >/dev/null
    fi
  fi
done
for base in "$@"; do
  name="$(echo "$base" | tr '[:lower:]' '[:upper:]')"
  kind="class"
  [ -f "src/$(echo "$base" | tr '[:upper:]' '[:lower:]').intf.abap" ] && kind="interface"
  out="$("${SAPCLI[@]}" "$kind" activate "$name" 2>&1 || true)"
  errors="$(echo "$out" | grep -E '^\s+E:' || true)"
  echo "== $name: $(echo "$out" | grep -E '^Errors' | tr -d '\n')"
  if [ -n "$errors" ]; then
    echo "$out" | grep -E -B1 '^\s+(E|W):'
    status=1
  fi
done
exit $status
