#!/usr/bin/env bash

WORKING_DIRECTORY=/scratch_vol1/fungi/Coral_block_colonisation/05_QIIME2/Original_reads_TUFA
OUTPUT=/scratch_vol1/fungi/Coral_block_colonisation/05_QIIME2/Original_reads_TUFA/visual

DATABASE=/scratch_vol1/fungi/Coral_block_colonisation/98_database_files
TMPDIR=/scratch_vol1




cd $WORKING_DIRECTORY

eval "$(conda shell.bash hook)"
conda activate qiime2-2021.4

# I'm doing this step in order to deal the no space left in cluster :
export TMPDIR='/scratch_vol1/fungi'
echo $TMPDIR

threads=FALSE

# Make the directory (mkdir) only if not existe already(-p)
mkdir -p taxonomy
mkdir -p export/taxonomy

# I'm doing this step in order to deal the no space left in cluster :
export TMPDIR='/scratch_vol1/fungi'
echo $TMPDIR



 qiime taxa barplot \
  --i-table core/ConTable.qza \
  --i-taxonomy taxonomy/taxonomy_reads-per-batch_RarRepSeq_vsearch.qza \
  --m-metadata-file $DATABASE/sample-metadata.tsv \
  --o-visualization taxonomy/taxa-bar-plots_reads-per-batch_RarRepSeq_vsearch.qzv 
  
  
  qiime tools export --input-path taxonomy/taxa-bar-plots_reads-per-batch_RarRepSeq_vsearch.qzv --output-path export/taxonomy/taxa-bar-plots_reads-per-batch_RarRepSeq_vsearch
