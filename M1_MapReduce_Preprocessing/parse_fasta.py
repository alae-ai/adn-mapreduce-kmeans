#!/usr/bin/env python3
"""
Standalone FASTA parser for Projet-ADN-MapReduce-Only
Reads FASTA files from input directory and writes JSONL records to output_dir/sequences_kept.jsonl
This script is independent from the original project.
"""
import os
import sys
import json
import argparse
import hashlib
from pathlib import Path

VALID_BASES = set("ATCG")
MIN_FRAGMENT = 30
MIN_LENGTH = 100


def clean_and_split(seq):
    s = seq.upper().replace('\n','').replace('\r','').replace(' ','')
    import re
    frags = [f for f in re.split(r'[^ATCG]+', s) if len(f) >= MIN_FRAGMENT]
    return frags


def compute_metrics(frags):
    if not frags:
        return {"length":0, "gc_content":0.0, "seq_hash":""}
    full = ''.join(frags)
    l = len(full)
    gc = round((full.count('G')+full.count('C'))/l,4)
    h = hashlib.md5(full.encode()).hexdigest()
    return {"length":l, "gc_content":gc, "seq_hash":h}


def parse_fasta_file(path):
    records = []
    with open(path, 'r', encoding='utf-8', errors='ignore') as f:
        header = None
        seq_lines = []
        for line in f:
            if line.startswith('>'):
                if header is not None:
                    seq = ''.join(seq_lines)
                    frags = clean_and_split(seq)
                    metrics = compute_metrics(frags)
                    status = 'KEPT' if metrics['length'] >= MIN_LENGTH else 'REJECTED_TOO_SHORT'
                    rec = {
                        'accession_id': header.split()[0].lstrip('>'),
                        'fragments': frags if status=='KEPT' else [],
                        'length': metrics['length'],
                        'gc_content': metrics['gc_content'],
                        'seq_hash': metrics['seq_hash'],
                        'status': status
                    }
                    records.append(rec)
                header = line.strip()
                seq_lines = []
            else:
                seq_lines.append(line.strip())
        if header is not None:
            seq = ''.join(seq_lines)
            frags = clean_and_split(seq)
            metrics = compute_metrics(frags)
            status = 'KEPT' if metrics['length'] >= MIN_LENGTH else 'REJECTED_TOO_SHORT'
            rec = {
                'accession_id': header.split()[0].lstrip('>'),
                'fragments': frags if status=='KEPT' else [],
                'length': metrics['length'],
                'gc_content': metrics['gc_content'],
                'seq_hash': metrics['seq_hash'],
                'status': status
            }
            records.append(rec)
    return records


def parse_directory(input_dir, output_dir):
    Path(output_dir).mkdir(parents=True, exist_ok=True)
    out_path = os.path.join(output_dir, 'sequences_kept.jsonl')
    total = 0
    with open(out_path, 'w', encoding='utf-8') as out:
        for root, dirs, files in os.walk(input_dir):
            for fn in files:
                if fn.lower().endswith(('.fasta', '.fsa', '.fa')):
                    fpath = os.path.join(root, fn)
                    recs = parse_fasta_file(fpath)
                    for r in recs:
                        out.write(json.dumps(r, ensure_ascii=False) + '\n')
                        total += 1
    print(f'Wrote {total} records to {out_path}')


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--input', required=True, help='Raw FASTA directory')
    p.add_argument('--output', required=True, help='Output directory for jsonl')
    args = p.parse_args()
    parse_directory(args.input, args.output)
