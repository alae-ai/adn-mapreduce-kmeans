#!/usr/bin/env bash
set -euo pipefail

# Example runner for MapReduce-only pipeline steps using Hadoop Streaming
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STREAM_JAR="${HADOOP_STREAMING_JAR:-/opt/hadoop/share/hadoop/tools/lib/hadoop-streaming-*.jar}"

# container and hadoop binary path
CONTAINER=mr_namenode
HADOOP_BIN=/opt/hadoop/bin/hadoop
# 1) Upload sequences_kept.jsonl expected at ROOT_DIR/data_clean/sequences_kept.jsonl
docker exec -i $CONTAINER bash -lc "${HADOOP_BIN} fs -put -f /project/data_clean_2/sequences_kept.jsonl /projet-adn-mr/input/ || true"

# 2) Run k-mer extraction
docker exec -i $CONTAINER bash -lc "${HADOOP_BIN} fs -rm -r -f /projet-adn-mr/output/kmers || true"
docker exec -i $CONTAINER bash -lc "${HADOOP_BIN} jar /opt/hadoop/share/hadoop/tools/lib/hadoop-streaming-*.jar -files /project/M2_MapReduce_Kmers/mapper_kmers.py,/project/M2_MapReduce_Kmers/reducer_kmers.py -mapper 'python3 mapper_kmers.py' -reducer 'python3 reducer_kmers.py' -input /projet-adn-mr/input/sequences_kept.jsonl -output /projet-adn-mr/output/kmers"

# 3) Build vectors CSV
docker exec -i $CONTAINER bash -lc "${HADOOP_BIN} fs -rm -r -f /projet-adn-mr/output/vectors_parts || true"
docker exec -i $CONTAINER bash -lc "${HADOOP_BIN} jar /opt/hadoop/share/hadoop/tools/lib/hadoop-streaming-*.jar -files /project/M3_MapReduce_Vectors/mapper_vectors.py,/project/M3_MapReduce_Vectors/reducer_vectors.py -mapper 'python3 mapper_vectors.py' -reducer 'python3 reducer_vectors.py' -input /projet-adn-mr/output/kmers/* -output /projet-adn-mr/output/vectors_parts"

# 4) Merge parts to single CSV (fetch to host /tmp then push back)
docker exec -i $CONTAINER bash -lc "${HADOOP_BIN} fs -getmerge /projet-adn-mr/output/vectors_parts /tmp/vectors.csv || true"
docker exec -i $CONTAINER bash -lc "${HADOOP_BIN} fs -rm -f /projet-adn-mr/output/vectors.csv || true"
docker exec -i $CONTAINER bash -lc "${HADOOP_BIN} fs -put -f /tmp/vectors.csv /projet-adn-mr/output/vectors.csv || true"

# 5) Similarity MapReduce
docker exec -i $CONTAINER bash -lc "${HADOOP_BIN} fs -rm -r -f /projet-adn-mr/output/similarity || true"
docker exec -i $CONTAINER bash -lc "${HADOOP_BIN} jar /opt/hadoop/share/hadoop/tools/lib/hadoop-streaming-*.jar -files /project/M4_MapReduce_Similarity/mapper_similarity.py,/project/M4_MapReduce_Similarity/reducer_similarity.py -mapper 'python3 mapper_similarity.py' -reducer 'python3 reducer_similarity.py' -input /projet-adn-mr/output/vectors.csv -output /projet-adn-mr/output/similarity"

# 6) Alignment MapReduce (requires sequences file accessible)
docker exec -i $CONTAINER bash -lc "${HADOOP_BIN} fs -put -f /project/data_clean_2/sequences_kept.jsonl /projet-adn-mr/input/sequences_kept.jsonl || true"
docker exec -i $CONTAINER bash -lc "${HADOOP_BIN} fs -rm -r -f /projet-adn-mr/output/alignment || true"
docker exec -i $CONTAINER bash -lc "${HADOOP_BIN} jar /opt/hadoop/share/hadoop/tools/lib/hadoop-streaming-*.jar -files /project/M5_MapReduce_Alignment/mapper_alignment.py,/project/M5_MapReduce_Alignment/reducer_alignment.py,/project/data_clean_2/sequences_kept.jsonl -mapper 'python3 mapper_alignment.py' -reducer 'python3 reducer_alignment.py' -input /projet-adn-mr/output/similarity/* -output /projet-adn-mr/output/alignment"

# 7) KMeans iterative (simple driver)
# Create initial centroids by sampling first 3 vectors (use container to getmerge to /tmp)
docker exec -i $CONTAINER bash -lc "${HADOOP_BIN} fs -getmerge /projet-adn-mr/output/vectors_parts /tmp/vectors.csv || true"
head -n 4 /tmp/vectors.csv | tail -n 3 > /tmp/initial_centroids.txt || true
# format centroids as id,vals
awk -F"," 'NR>1{print NR-1","substr($0,index($0,$2))}' /tmp/initial_centroids.txt > /tmp/centroids.txt || true
docker exec -i $CONTAINER bash -lc "${HADOOP_BIN} fs -rm -r -f /projet-adn-mr/output/kmeans || true"

ITER=0
MAXITER=10
while [ $ITER -lt $MAXITER ]; do
  echo "KMeans iteration $ITER"
  # copy centroids to local and run streaming
  docker exec -i $CONTAINER bash -lc "${HADOOP_BIN} fs -put -f /tmp/centroids.txt /projet-adn-mr/input/centroids.txt"
  docker exec -i $CONTAINER bash -lc "${HADOOP_BIN} jar /opt/hadoop/share/hadoop/tools/lib/hadoop-streaming-*.jar -files /project/M6_MapReduce_KMeans/mapper_kmeans_assign.py,/project/M6_MapReduce_KMeans/reducer_kmeans_update.py,/projet-adn-mr/input/centroids.txt -mapper 'python3 mapper_kmeans_assign.py' -reducer 'python3 reducer_kmeans_update.py' -input /projet-adn-mr/output/vectors_parts/* -output /projet-adn-mr/output/kmeans_iter_$ITER"

  # fetch new centroids
  docker exec -i $CONTAINER bash -lc "${HADOOP_BIN} fs -getmerge /projet-adn-mr/output/kmeans_iter_$ITER /tmp/centroids_new.txt || true"

  # check convergence (simple string compare)
  if [ -f /tmp/centroids.txt ]; then
    if cmp -s /tmp/centroids.txt /tmp/centroids_new.txt; then
      echo "Converged at iteration $ITER"
      break
    fi
  fi
  mv /tmp/centroids_new.txt /tmp/centroids.txt
  ITER=$((ITER+1))
done

# final centroids at /tmp/centroids.txt
# push final centroids to HDFS
docker exec -i $CONTAINER bash -lc "${HADOOP_BIN} fs -put -f /tmp/centroids.txt /projet-adn-mr/output/kmeans/centroids.txt || true"

# 8) Export outputs to local
# host-side getmerge/pull handled below using docker-exec -> getmerge -> mv

mkdir -p "$ROOT_DIR/output"
docker exec -i $CONTAINER bash -lc "${HADOOP_BIN} fs -getmerge /projet-adn-mr/output/vectors_parts /tmp/vectors_out.csv || true"
mv /tmp/vectors_out.csv "$ROOT_DIR/output/vectors.csv" || true
docker exec -i $CONTAINER bash -lc "${HADOOP_BIN} fs -getmerge /projet-adn-mr/output/similarity /tmp/sim_out.csv || true"
mv /tmp/sim_out.csv "$ROOT_DIR/output/similarity.csv" || true
docker exec -i $CONTAINER bash -lc "${HADOOP_BIN} fs -getmerge /projet-adn-mr/output/alignment /tmp/align_out.csv || true"
mv /tmp/align_out.csv "$ROOT_DIR/output/alignment.csv" || true
docker exec -i $CONTAINER bash -lc "${HADOOP_BIN} fs -getmerge /projet-adn-mr/output/kmeans/centroids.txt /tmp/centroids_final.txt || true"
mv /tmp/centroids_final.txt "$ROOT_DIR/output/centroids.txt" || true

echo "MapReduce-only pipeline completed. Outputs in $ROOT_DIR/output"
