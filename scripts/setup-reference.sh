#!/usr/bin/env bash
# Fetch, build and run the eMondrian reference implementation (see docs/environment.md).
# Run from the repository root in Git Bash (Windows) or any bash. Needs: git, JDK 17+, Maven, Docker, internet.
# Pinned to the commits that were built successfully on 2026-10-02.
set -euo pipefail

MONDRIAN_COMMIT=746b824a306e8025732ad757acb47a50510e9e1e
EMONDRIAN_COMMIT=729fd39088af0db5c285ae7367e3fddc46e8ed37
SCHEMA_EDITOR_COMMIT=02c74c083c39b16e01f2120c94b00f1de6420269

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

[ -d mondrian ] || git clone -b eMondrian https://github.com/SergeiSemenkov/mondrian.git
git -C mondrian checkout "$MONDRIAN_COMMIT"
# our fixes of the fork (scripts/patches/*.patch, see docs/environment.md); skipped if already applied
for patch in scripts/patches/*.patch; do
  git -C mondrian apply --reverse --check "../$patch" 2>/dev/null || git -C mondrian apply "../$patch"
done

[ -d eMondrian ] || git clone https://github.com/SergeiSemenkov/eMondrian.git
git -C eMondrian checkout "$EMONDRIAN_COMMIT"

# 1. Mondrian fork -> local Maven repository (eMondrian depends on mondrian 9.3.0-emondrian.N)
(cd mondrian && mvn -B install -DskipTests > ../mondrian_build.log 2>&1)

# 2. SchemaEditor: run the script ourselves, Maven's exec plugin cannot start .sh files on Windows
(cd eMondrian && bash clone_schema_editor.sh && git -C src/SchemaEditor checkout "$SCHEMA_EDITOR_COMMIT")

# 3. eMondrian war (skip the exec plugin because of step 2)
(cd eMondrian && mvn -B package -DskipTests -Dexec.skip=true > ../emondrian_build.log 2>&1)

# 4. Docker image from eMondrian's own Dockerfile + container on port 8080
docker build -t emondrian:local -f eMondrian/docker/Dockerfile eMondrian/target
docker rm -f emondrian >/dev/null 2>&1 || true
docker run -d --name emondrian -p 8080:8080 emondrian:local

echo "eMondrian XMLA endpoint: http://localhost:8080/emondrian/xmla (give Tomcat a few seconds to start)"
