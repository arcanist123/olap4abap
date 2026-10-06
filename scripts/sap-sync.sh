#!/usr/bin/env bash
# Sync the ABAP package between an SAP system and this repository using sapcli (ADT, no SAP GUI, no abapGit).
#
#   scripts/sap-sync.sh ping    check connection and show the package
#   scripts/sap-sync.sh pull    SAP -> repo: export the package into src/ (abapGit file format) - overwrites src/
#   scripts/sap-sync.sh push    repo -> SAP: create the package if missing, import src/ and activate - overwrites objects
#
# Git is the only thing that writes to the remote: after `pull`, review `git diff` and commit from here.
# Connection settings come from .env.sap (git-ignored, see .env.sap.example) or the environment.
# Needs: bash (Git Bash on Windows), sapcli on PATH.
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

die() { echo "error: $*" >&2; exit 1; }

: "${SAP_ASHOST:?set SAP_ASHOST in .env.sap}"
: "${SAP_CLIENT:?set SAP_CLIENT in .env.sap}"
: "${SAP_USER:?set SAP_USER in .env.sap}"
: "${SAP_PASSWORD:?set SAP_PASSWORD in .env.sap}"
export SAP_PASSWORD   # sapcli reads the password from the environment, so it never appears on a command line

PACKAGE_DEFAULT='$ZZXXMLA1'
PACKAGE="${SAP_PACKAGE:-$PACKAGE_DEFAULT}"
SOFTWARE_COMPONENT="${SAP_SOFTWARE_COMPONENT:-LOCAL}"   # LOCAL = local ($) package, not transportable
SRC_DIR="src"

command -v sapcli >/dev/null || die "sapcli not found on PATH"

SAPCLI=(sapcli --ashost "$SAP_ASHOST" --client "$SAP_CLIENT" --user "$SAP_USER")
[ -n "${SAP_PORT:-}" ] && SAPCLI+=(--port "$SAP_PORT")
[ "${SAP_USE_SSL:-false}" = "true" ] || SAPCLI+=(--no-ssl)
[ "${SAP_SKIP_SSL_VALIDATION:-false}" = "true" ] && SAPCLI+=(--skip-ssl-validation)

cmd_ping() {
  "${SAPCLI[@]}" package stat "$PACKAGE"
}

cmd_pull() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  # export into a temp dir first, so a failed export never wipes the existing src/
  "${SAPCLI[@]}" checkout package "$PACKAGE" "$tmp/pkg"
  [ -f "$tmp/pkg/.abapgit.xml" ] || die "export has no .abapgit.xml, nothing copied"
  [ -d "$tmp/pkg/$SRC_DIR" ]    || die "export has no $SRC_DIR/ folder (check .abapgit.xml STARTING_FOLDER), nothing copied"
  # classes have no local includes (CLAUDE.md): sapcli writes SAP's template of every class's local definitions and
  # implementations, which are dropped; one with code is refused
  local locals include with_code=()
  for locals in "$tmp/pkg/$SRC_DIR"/*.clas.locals_def.abap "$tmp/pkg/$SRC_DIR"/*.clas.locals_imp.abap; do
    [ -e "$locals" ] || continue
    if grep -Eqv '^[[:space:]]*(\*.*|".*)?[[:space:]]*$' "$locals"; then
      with_code+=("$(basename "$locals")")
    else
      rm "$locals"
    fi
  done
  [ ${#with_code[@]} -eq 0 ] || die "local includes with code (move them into global classes), nothing copied: ${with_code[*]}"
  # a test include that is only SAP's template is dropped as well
  for include in "$tmp/pkg/$SRC_DIR"/*.clas.testclasses.abap; do
    [ -e "$include" ] || continue
    grep -Eqv '^[[:space:]]*(\*.*|".*)?[[:space:]]*$' "$include" || rm "$include"
  done
  rm -rf "$ROOT/$SRC_DIR"
  cp "$tmp/pkg/.abapgit.xml" "$ROOT/.abapgit.xml"
  cp -r "$tmp/pkg/$SRC_DIR" "$ROOT/$SRC_DIR"
  # sapcli writes an interface's metadata as <name>.prog.xml; abapGit expects <name>.intf.xml
  local xml
  for xml in "$ROOT/$SRC_DIR"/*.prog.xml; do
    [ -e "$xml" ] || continue
    if grep -q 'serializer="LCL_OBJECT_INTF"' "$xml"; then
      mv "$xml" "${xml%.prog.xml}.intf.xml"
    fi
  done
  echo "exported $PACKAGE into $SRC_DIR/ - review with: git status && git diff"
}

cmd_push() {
  [ -f "$ROOT/.abapgit.xml" ] && [ -d "$ROOT/$SRC_DIR" ] || die "no .abapgit.xml / $SRC_DIR/ - run pull on a system that has the code first"
  # create the package when missing (idempotent); local package, no transport layer
  "${SAPCLI[@]}" package create "$PACKAGE" "olap4abap: XMLA server with an MDX engine" \
    --software-component "$SOFTWARE_COMPONENT" --record-changes --no-error-existing
  # import src/ (reads the current directory) and activate; a transport request can be passed as $1 for non-local packages
  "${SAPCLI[@]}" checkin package "$PACKAGE" ${1:+"$1"} --software-component "$SOFTWARE_COMPONENT" --starting-folder "$SRC_DIR"
  echo "imported $SRC_DIR/ into $PACKAGE"
}

case "${1:-}" in
  ping) cmd_ping ;;
  pull) cmd_pull ;;
  push) shift; cmd_push "$@" ;;
  *) sed -n '2,10p' "$0"; exit 1 ;;
esac
