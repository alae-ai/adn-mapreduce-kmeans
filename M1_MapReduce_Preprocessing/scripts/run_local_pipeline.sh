#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT_DIR/output_local"

echo "Step 1: k-mer mapper"
cat "$ROOT_DIR/data_clean/sequences_kept.jsonl" | python3 "$ROOT_DIR/M2_MapReduce_Kmers/mapper_kmers.py" > /tmp/kmers.map

echo "Step 2: sort"
sort /tmp/kmers.map > /tmp/kmers.sorted

echo "Step 3: k-mer reducer"
python3 "$ROOT_DIR/M2_MapReduce_Kmers/reducer_kmers.py" < /tmp/kmers.sorted > /tmp/kmers.reduced

echo "Step 4: vector mapper (identity)"
python3 "$ROOT_DIR/M3_MapReduce_Vectors/mapper_vectors.py" < /tmp/kmers.reduced > /tmp/vectors.mapper

echo "Step 5: vector reducer -> CSV"
python3 "$ROOT_DIR/M3_MapReduce_Vectors/reducer_vectors.py" < /tmp/vectors.mapper > "$ROOT_DIR/output_local/vectors.csv"

echo "Step 6: similarity mapper"
python3 "$ROOT_DIR/M4_MapReduce_Similarity/mapper_similarity.py" < "$ROOT_DIR/output_local/vectors.csv" > /tmp/sim.map

echo "Step 7: similarity sort & reducer"
sort /tmp/sim.map > /tmp/sim.sorted
python3 "$ROOT_DIR/M4_MapReduce_Similarity/reducer_similarity.py" < /tmp/sim.sorted > "$ROOT_DIR/output_local/similarity.csv"

# alignment step expects similarity pairs; run mapper_alignment locally
if [ -s "$ROOT_DIR/output_local/similarity.csv" ]; then
  echo "Step 8: alignment"
  python3 "$ROOT_DIR/M5_MapReduce_Alignment/mapper_alignment.py" < "$ROOT_DIR/output_local/similarity.csv" > "$ROOT_DIR/output_local/alignment.csv"
else
  echo "No similarity pairs found; skipping alignment"
fi

echo "Local pipeline finished. Outputs in $ROOT_DIR/output_local"
