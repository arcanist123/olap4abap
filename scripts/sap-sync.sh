#!/usr/bin/env bash
# Sync the ABAP package between an SAP system and this repository.
#
#   scripts/sap-sync.sh ping    check connection and show the package
#   scripts/sap-sync.sh pull    SAP -> repo: export the package into src/ with vsp (abapGit's own serializer on the
#                               system) - overwrites src/
#   scripts/sap-sync.sh push    repo -> SAP: create the package if missing, import src/ with sapcli and activate -
#                               overwrites objects
#
# push uses sapcli, which has no DDIC tables: the *.tabl.xml files are left out, so a table is changed in SAP by hand
# (SE11) and pulled.
#
# Git is the only thing that writes to the remote: after `pull`, review `git diff` and commit from here.
# Connection settings come from .env.sap (git-ignored, see .env.sap.example) or the environment.
# Needs: bash (Git Bash on Windows), vsp and unzip (pull), sapcli (ping, push) on PATH.
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

[ "${1:-}" = pull ] || command -v sapcli >/dev/null || die "sapcli not found on PATH"

SAPCLI=(sapcli --ashost "$SAP_ASHOST" --client "$SAP_CLIENT" --user "$SAP_USER")
[ -n "${SAP_PORT:-}" ] && SAPCLI+=(--port "$SAP_PORT")
[ "${SAP_USE_SSL:-false}" = "true" ] || SAPCLI+=(--no-ssl)
[ "${SAP_SKIP_SSL_VALIDATION:-false}" = "true" ] && SAPCLI+=(--skip-ssl-validation)

cmd_ping() {
  "${SAPCLI[@]}" package stat "$PACKAGE"
}

cmd_pull() {
  command -v vsp >/dev/null || die "vsp not found on PATH"
  command -v unzip >/dev/null || die "unzip not found on PATH"
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  # export into a temp dir first, so a failed export never wipes the existing src/; vsp serializes with the abapGit
  # installed on the system (needs abapGit's developer edition and ZADT_VSP there, docs/environment.md), so the files
  # are the ones abapGit writes
  local scheme=http
  [ "${SAP_USE_SSL:-false}" = "true" ] && scheme=https
  SAP_URL="$scheme://$SAP_ASHOST${SAP_PORT:+:$SAP_PORT}/" vsp export "$PACKAGE" --subpackages=false -o "$tmp/pkg.zip"
  mkdir "$tmp/pkg"
  unzip -q "$tmp/pkg.zip" -d "$tmp/pkg"
  # vsp puts the package's files into a folder named after it; with FOLDER_LOGIC FULL the root package is the
  # starting folder itself
  local pkg_dir
  pkg_dir="$tmp/pkg/$SRC_DIR/$(echo "$PACKAGE" | tr '[:upper:]' '[:lower:]')"
  [ -d "$pkg_dir" ] || pkg_dir="$tmp/pkg/$SRC_DIR"
  ls "$pkg_dir"/*.xml >/dev/null 2>&1 || die "export has no files in $pkg_dir, nothing copied"
  rm -rf "$ROOT/$SRC_DIR"
  cp -r "$pkg_dir" "$ROOT/$SRC_DIR"
  echo "exported $PACKAGE into $SRC_DIR/ - review with: git status && git diff"
}

cmd_push() {
  [ -f "$ROOT/.abapgit.xml" ] && [ -d "$ROOT/$SRC_DIR" ] || die "no .abapgit.xml / $SRC_DIR/ - run pull on a system that has the code first"
  # create the package when missing (idempotent); local package, no transport layer
  "${SAPCLI[@]}" package create "$PACKAGE" "olap4abap: XMLA server with an MDX engine" \
    --software-component "$SOFTWARE_COMPONENT" --record-changes --no-error-existing
  # import src/ without the tables, which sapcli does not know, and activate: checkin reads the current directory, so a
  # copy is imported; a transport request can be passed as $1 for non-local packages
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  cp "$ROOT/.abapgit.xml" "$tmp/"
  cp -r "$ROOT/$SRC_DIR" "$tmp/$SRC_DIR"
  rm -f "$tmp/$SRC_DIR"/*.tabl.xml
  (cd "$tmp" && "${SAPCLI[@]}" checkin package "$PACKAGE" ${1:+"$1"} --software-component "$SOFTWARE_COMPONENT"     --starting-folder "$SRC_DIR")
  echo "imported $SRC_DIR/ into $PACKAGE"
}

case "${1:-}" in
  ping) cmd_ping ;;
  pull) cmd_pull ;;
  push) shift; cmd_push "$@" ;;
  *) sed -n '2,10p' "$0"; exit 1 ;;
esac
