#!/usr/bin/env bash
# Deploy the generated FoodMart data classes (data/foodmart-abap/, see scripts/generate-foodmart-abap.py) to the
# SAP system: create each class in package $ZZXXMLA1 if it is missing, then write its source and activate.
#
#   python scripts/export-foodmart-csv.py && python scripts/generate-foodmart-abap.py && scripts/deploy-foodmart-data.sh
#
# Connection settings come from .env.sap (git-ignored, see .env.sap.example), like scripts/sap-sync.sh.
# After a deploy run `scripts/sap-sync.sh pull` so src/ contains the classes.
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

PACKAGE="${SAP_PACKAGE:-\$ZZXXMLA1}"
DATA_DIR="data/foodmart-abap"

command -v sapcli >/dev/null || { echo "error: sapcli not found on PATH" >&2; exit 1; }
ls "$DATA_DIR"/*.clas.abap >/dev/null 2>&1 || { echo "error: no generated classes in $DATA_DIR, run scripts/generate-foodmart-abap.py" >&2; exit 1; }

SAPCLI=(sapcli --ashost "$SAP_ASHOST" --client "$SAP_CLIENT" --user "$SAP_USER")
[ -n "${SAP_PORT:-}" ] && SAPCLI+=(--port "$SAP_PORT")
[ "${SAP_USE_SSL:-false}" = "true" ] || SAPCLI+=(--no-ssl)

for file in "$DATA_DIR"/*.clas.abap; do
  name="$(basename "$file" .clas.abap | tr '[:lower:]' '[:upper:]')"
  suffix="${name##*_}"
  echo "== $name"
  # creating an existing class fails with ExceptionResourceAlreadyExists, which is fine
  "${SAPCLI[@]}" class create "$name" "FoodMart data: $suffix" "$PACKAGE" >/dev/null 2>&1 || true
  "${SAPCLI[@]}" class write -a "$name" "$file" 2>&1 | tail -4
done
