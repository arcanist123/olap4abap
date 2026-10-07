#!/usr/bin/env bash
# Makes the running eMondrian container serve only our reference schemas: copies reference/schema/FoodmartBW.xml,
# reference/schema/ZXMLWIDE.xml and reference/schema/datasources.xml into it (the original FoodMart catalog is no
# longer registered, so the container's answers can be compared one-to-one with the ABAP server), then restarts the
# container. Safe to run again.
# To get the original catalogs back, recreate the container from its image (see docs/environment.md).
set -euo pipefail
cd "$(dirname "$0")/.."

CONTAINER="${EMONDRIAN_CONTAINER:-emondrian}"
WEBINF=/usr/local/tomcat/webapps/emondrian/WEB-INF

docker cp reference/schema/FoodmartBW.xml "$CONTAINER:$WEBINF/schema/FoodmartBW.xml"
docker cp reference/schema/ZXMLWIDE.xml "$CONTAINER:$WEBINF/schema/ZXMLWIDE.xml"
docker cp reference/schema/datasources.xml "$CONTAINER:$WEBINF/datasources.xml"
# the FoodMart data with the empty member (id 0) in every dimension, see scripts/add-empty-members.py
if [ -f data/foodmart-bw/hsqldb-foodmart.jar ]; then
  docker cp data/foodmart-bw/hsqldb-foodmart.jar "$CONTAINER:$WEBINF/lib/hsqldb-foodmart.jar"
else
  echo "note: data/foodmart-bw/hsqldb-foodmart.jar not found, the container keeps its original data" >&2
fi
docker restart "$CONTAINER" >/dev/null
echo "deployed ZFOODMART and ZXMLWIDE as the only catalogs of $CONTAINER; give it ~30 s to start"
