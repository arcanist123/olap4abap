#!/usr/bin/env bash
# Write the schema definition classes from src/ into SAP and activate them: the eigenbase-xom port
# (ZZXXMLA1_CX_XOM, ZZXXMLA1_CL_XOM_PARSER, ZZXXMLA1_CL_XOM_OUTPUT) and the generated ZZXXMLA1_CL_SCHEMA_DEF with its
# tests (scripts/generate-schema-def.py). sapcli writes the files unchanged, which the ABAP FS edit tool does not do
# for backslash escapes. The classes must exist (created in $ZZXXMLA1). Logon data from .env.sap, as scripts/sap-sync.sh.
#
#   python scripts/generate-schema-def.py && scripts/deploy-schema-def.sh && scripts/sap-sync.sh pull
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

write() {  # class, include type, file
  echo "== $1 ($2)"
  "${SAPCLI[@]}" class write --type "$2" "$1" "$3" 2>&1 | tail -3
}

write ZZXXMLA1_CX_XOM main src/zzxxmla1_cx_xom.clas.abap
write ZZXXMLA1_CL_XOM_PARSER main src/zzxxmla1_cl_xom_parser.clas.abap
write ZZXXMLA1_CL_XOM_OUTPUT main src/zzxxmla1_cl_xom_output.clas.abap
write ZZXXMLA1_CL_SCHEMA_DEF main src/zzxxmla1_cl_schema_def.clas.abap
write ZZXXMLA1_CL_SCHEMA_DEF testclasses src/zzxxmla1_cl_schema_def.clas.testclasses.abap
for name in ZZXXMLA1_CX_XOM ZZXXMLA1_CL_XOM_PARSER ZZXXMLA1_CL_XOM_OUTPUT ZZXXMLA1_CL_SCHEMA_DEF; do
  echo "== activate $name"
  "${SAPCLI[@]}" class activate "$name" 2>&1 | tail -5
done
