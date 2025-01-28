#!/usr/bin/env bash

# installing FastQC from https://www.bioinformatics.babraham.ac.uk/projects/download.html
# FastQC v0.11.9 (Mac DMG image)

# Correct tool citation : Andrews, S. (2010). FastQC: a quality control tool for high throughput sequence data.

WORKING_DIRECTORY=/scratch_vol0/fungi/eDNA_new_caledonian_lagoon_diversity/01_raw_data
OUTPUT=/scratch_vol0/fungi/eDNA_new_caledonian_lagoon_diversity/02_quality_check

# Make the directory (mkdir) only if not existe already(-p)
mkdir -p $OUTPUT

eval "$(conda shell.bash hook)"
conda activate fastqc

cd $WORKING_DIRECTORY

for FILE in $(ls $WORKING_DIRECTORY/*.fastq)
do
      fastqc $FILE -o $OUTPUT
done ;


conda deactivate fastqc
conda activate multiqc

# Run multiqc for quality summary

multiqc $OUTPUT
