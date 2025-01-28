#!/usr/bin/env bash

# trimmomatic version 0.39
# trimmomatic manual : http://www.usadellab.org/cms/uploads/supplementary/Trimmomatic/TrimmomaticManual_V0.32.pdf

WORKING_DIRECTORY=/scratch_vol0/fungi/eDNA_new_caledonian_lagoon_diversity/01_raw_data
OUTPUT=/scratch_vol0/fungi/eDNA_new_caledonian_lagoon_diversity/03_cleaned_data

# Make the directory (mkdir) only if not already exists (-p)
mkdir -p $OUTPUT

ADAPTERFILE=/scratch_vol0/fungi/eDNA_new_caledonian_lagoon_diversity/99_softwares/adapters_sequences.fasta

# Arguments :
# ILLUMINACLIP:"$ADAPTERFILE":2:30:10 LEADING:30 TRAILING:30 SLIDINGWINDOW:26:30 MINLEN:150

eval "$(conda shell.bash hook)"
conda activate trimmomatic

cd $WORKING_DIRECTORY

####################################################
# Cleaning step for single-end reads
####################################################

for FILE in *.fastq
do
   OUTPUT_CLEANED=${FILE//.fastq/_cleaned.fastq}

   trimmomatic SE -Xmx60G -threads 8 -phred33 $FILE $OUTPUT/$OUTPUT_CLEANED ILLUMINACLIP:"$ADAPTERFILE":2:30:10 LEADING:30 TRAILING:30 SLIDINGWINDOW:26:30 MINLEN:150

done
