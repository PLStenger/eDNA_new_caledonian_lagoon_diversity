#!/bin/bash

cd /home/plstenge/eDNA_new_caledonian_lagoon_diversity/02_kraken2_core_nt/reports

for file in *report.txt; do
  base=$(basename "$file" report.txt)
  python3 /home/plstenge/coprolites/07_kraken2/KrakenTools/kreport2mpa.py -r "$file" -o "${base}.mpa"
done

for file in *.mpa; do
  name=$(basename "$file" .mpa)
  sed -i "1i #SampleName\t${name}" "$file"
done

python3 /home/plstenge/coprolites/07_kraken2/KrakenTools/combine_mpa.py -i *.mpa -o combined_mpa.tsv
