#!/usr/bin/env bash

WORKING_DIRECTORY=/home/fungi/eDNA_new_caledonian_lagoon_diversity/05_QIIME2
OUTPUT=/home/fungi/eDNA_new_caledonian_lagoon_diversity/05_QIIME2/visual

# Make the directory (mkdir) only if not existe already(-p)
mkdir -p $OUTPUT

METADATA=/home/fungi/eDNA_new_caledonian_lagoon_diversity/98_database_files/sample-metadata.tsv
# negative control sample :
#NEG_CONTROL=/home/fungi/eDNA_new_caledonian_lagoon_diversity/99_contamination

TMPDIR=/home/fungi/eDNA_new_caledonian_lagoon_diversity/00_scripts

# https://chmi-sops.github.io/mydoc_qiime2.html

# https://docs.qiime2.org/2021.2/plugins/available/dada2/denoise-single/
# Aim: denoises single-end sequences, dereplicates them, and filters
# chimeras and singletons sequences
# Use: qiime dada2 denoise-single [OPTIONS]

# DADA2 method

cd $WORKING_DIRECTORY

source /Users/stengerpierre-louis/miniconda/bin/activate

eval "$(conda shell.bash hook)"
conda activate qiime2-2021.4

# I'm doing this step in order to deal the no space left in cluster :
export $TMPDIR
echo $TMPDIR

# dada2_denoise :
#################

# Aim: denoises paired-end sequences, dereplicates them, and filters
#      chimeras and singletons sequences

# https://github.com/benjjneb/dada2/issues/477

qiime dada2 denoise-single \
  --i-demultiplexed-seqs core/demux.qza \
  --o-table core/Table.qza \
  --o-representative-sequences core/RepSeq.qza \
  --o-denoising-stats core/Stats.qza \
  --p-trim-left 0 \
  --p-trunc-len 0 \
  --p-n-threads 4

##################################################################
# Control samples
##################################################################

qiime dada2 denoise-single \
  --i-demultiplexed-seqs core/demux_neg.qza \
  --o-table core/Table_neg.qza \
  --o-representative-sequences core/RepSeq_neg.qza \
  --o-denoising-stats core/Stats_neg.qza \
  --p-trim-left 0 \
  --p-trunc-len 0 \
  --p-n-threads 4


# sequence_contamination_filter :
#################################

# Aim: aligns feature sequences to a set of reference sequences
#      to identify sequences that hit/miss the reference
#      Use: qiime quality-control exclude-seqs [OPTIONS]

# Here --i-reference-sequences correspond to the negative control sample (if you don't have any, like here, take another one from an old project, the one here is from the same sequencing line (but not same project))

 # 001_mini_pipeline_for_contaminated_sequences

###################################################################################################
# Cette étape seulement si pas d'échantillon de control
###################################################################################################
#
#qiime tools import \
#  --input-path $NEG_CONTROL/contamination_seq.fasta \
#  --output-path $NEG_CONTROL/contamination_seq.qza \
#  --type 'FeatureData[Sequence]'
##
#qiime quality-control exclude-seqs --i-query-sequences core/RepSeq.qza \
#      					     --i-reference-sequences $NEG_CONTROL/contamination_seq.qza \
#      					     --p-method vsearch \
#      					     --p-threads 6 \
#      					     --p-perc-identity 1.00 \
#      					     --p-perc-query-aligned 1.00 \
#      					     --o-sequence-hits core/HitNegCtrl.qza \
#      					     --o-sequence-misses core/NegRepSeq.qza
###################################################################################################

qiime quality-control exclude-seqs --i-query-sequences core/RepSeq.qza \
      					     --i-reference-sequences core/RepSeq_neg.qza\
      					     --p-method vsearch \
      					     --p-threads 6 \
      					     --p-perc-identity 1.00 \
      					     --p-perc-query-aligned 1.00 \
      					     --o-sequence-hits core/HitNegCtrl.qza \
      					     --o-sequence-misses core/NegRepSeq.qza

# table_contamination_filter :
##############################

# Aim: filter features from table based on frequency and/or metadata
#      Use: qiime feature-table filter-features [OPTIONS]

qiime feature-table filter-features --i-table core/Table.qza \
     					      --m-metadata-file core/HitNegCtrl.qza \
     					      --o-filtered-table core/NegTable.qza \
     					      --p-exclude-ids

# table_contingency_filter :
############################

# Aim: filter features that show up in only one samples, based on
#      the suspicion that these may not represent real biological diversity
#      but rather PCR or sequencing errors (such as PCR chimeras)
#      Use: qiime feature-table filter-features [OPTIONS]

# contingency:
    # min_obs: 2  # Remove features that are present in only a single sample !
    # min_freq: 0 # Remove features with a total abundance (summed across all samples) of less than 0 !


qiime feature-table filter-features  --i-table core/Table_neg.qza \
        					       --p-min-samples 2 \
        					       --p-min-frequency 0 \
        					       --o-filtered-table core/ConTable.qza


# sequence_contingency_filter :
###############################

# Aim: Filter features from sequence based on table and/or metadata
       # Use: qiime feature-table filter-seqs [OPTIONS]

qiime feature-table filter-seqs --i-data core/RepSeq_neg.qza \
      					  --i-table core/ConTable.qza \
      					  --o-filtered-data core/ConRepSeq.qza


# sequence_summarize :
######################

# Aim: Generate tabular view of feature identifier to sequence mapping
       # Use: qiime feature-table tabulate-seqs [OPTIONS]

qiime feature-table summarize --i-table core/Table.qza --m-sample-metadata-file $METADATA --o-visualization visual/Table.qzv
qiime feature-table summarize --i-table core/ConTable.qza --m-sample-metadata-file $METADATA --o-visualization visual/ConTable.qzv
qiime feature-table summarize --i-table core/Table_neg.qza --m-sample-metadata-file $METADATA --o-visualization visual/Table_neg.qzv
qiime feature-table tabulate-seqs --i-data core/RepSeq_neg.qza --o-visualization visual/RepSeq_neg.qzv
qiime feature-table tabulate-seqs --i-data core/RepSeq.qza --o-visualization visual/RepSeq.qzv
qiime feature-table tabulate-seqs --i-data core/HitNegCtrl.qza --o-visualization visual/HitNegCtrl.qzv

mkdir -p export/core
mkdir -p export/visual

qiime tools export --input-path core/Table.qza --output-path export/core/Table
qiime tools export --input-path core/ConTable.qza --output-path export/core/ConTable
qiime tools export --input-path core/Table_neg.qza --output-path export/core/Table_neg
qiime tools export --input-path core/RepSeq_neg.qza --output-path export/core/RepSeq_neg
qiime tools export --input-path core/RepSeq.qza --output-path export/core/RepSeq
qiime tools export --input-path core/HitNegCtrl.qza --output-path export/core/HitNegCtrl
qiime tools export --input-path core/ConRepSeq.qza --output-path export/core/ConRepSeq
qiime tools export --input-path core/Stats.qza  --output-path export/core/Stats
qiime tools export --input-path core/Stats_neg.qza  --output-path export/core/Stats_neg

qiime tools export --input-path visual/Table_neg.qzv --output-path export/visual/Table_neg
qiime tools export --input-path visual/ConTable.qzv --output-path export/visual/ConTable
qiime tools export --input-path visual/Table.qzv --output-path export/visual/Table
qiime tools export --input-path visual/HitNegCtrl.qzv --output-path export/visual/HitNegCtrl
qiime tools export --input-path visual/RepSeq.qzv --output-path export/visual/RepSeq
qiime tools export --input-path visual/RepSeq_neg.qzv --output-path export/visual/RepSeq_neg
