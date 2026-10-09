#!/usr/bin/env bash
set -euo pipefail

#!/usr/bin/env bash
set -euo pipefail

# Create HDFS directories for the standalone MapReduce-only project
BASE=/projet-adn-mr
CONTAINER=mr_namenode
HADOOP_BIN=/opt/hadoop/bin/hadoop

docker exec -i $CONTAINER bash -lc "${HADOOP_BIN} fs -rm -r -f $BASE || true"
docker exec -i $CONTAINER bash -lc "${HADOOP_BIN} fs -mkdir -p $BASE/input"
docker exec -i $CONTAINER bash -lc "${HADOOP_BIN} fs -mkdir -p $BASE/output"

echo "Created HDFS base $BASE inside $CONTAINER"
docker exec -i $CONTAINER bash -lc "${HADOOP_BIN} fs -ls -R $BASE || true"
