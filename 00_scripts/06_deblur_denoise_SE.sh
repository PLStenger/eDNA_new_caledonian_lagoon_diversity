#!/usr/bin/env bash

WORKING_DIRECTORY=/scratch_vol0/fungi/eDNA_new_caledonian_lagoon_diversity/05_QIIME2
OUTPUT=/scratch_vol0/fungi/eDNA_new_caledonian_lagoon_diversity/05_QIIME2/visual

# Make the directory (mkdir) only if not exists already (-p)
mkdir -p $OUTPUT

METADATA=/scratch_vol0/fungi/eDNA_new_caledonian_lagoon_diversity/98_database_files/sample-metadata.tsv
TMPDIR=/scratch_vol0

# Move to working directory
cd $WORKING_DIRECTORY

eval "$(conda shell.bash hook)"
conda activate qiime2-2021.4

# Set temporary directory
export TMPDIR='/scratch_vol0/fungi'
echo $TMPDIR

# Deblur denoise step
####################

qiime quality-filter q-score \
  --i-demux core/demux.qza \
  --o-filtered-sequences core/demux_filtered.qza \
  --o-filter-stats core/demux_filter_stats.qza

qiime deblur denoise-16S \
  --i-demultiplexed-seqs core/demux_filtered.qza \
  --o-table core/Table.qza \
  --o-representative-sequences core/RepSeq.qza \
  --p-trim-length 150 \
  --p-sample-stats \
  --o-stats core/Stats.qza \
  --verbose

qiime deblur denoise-16S \
  --i-demultiplexed-seqs core/demux_neg.qza \
  --o-table core/Table_neg.qza \
  --o-representative-sequences core/RepSeq_neg.qza \
  --p-trim-length 150 \
  --p-sample-stats \
  --o-stats core/Stats_neg.qza \
  --verbose


# Contamination filtering
#########################

qiime quality-control exclude-seqs --i-query-sequences core/RepSeq.qza \
                                   --i-reference-sequences core/RepSeq_neg.qza \
                                   --p-method vsearch \
                                   --p-threads 6 \
                                   --p-perc-identity 1.00 \
                                   --p-perc-query-aligned 1.00 \
                                   --o-sequence-hits core/HitNegCtrl.qza \
                                   --o-sequence-misses core/NegRepSeq.qza

qiime feature-table filter-features --i-table core/Table.qza \
                                    --m-metadata-file core/HitNegCtrl.qza \
                                    --o-filtered-table core/NegTable.qza \
                                    --p-exclude-ids

# Contingency filtering
########################

qiime feature-table filter-features --i-table core/Table_neg.qza \
                                    --p-min-samples 2 \
                                    --p-min-frequency 0 \
                                    --o-filtered-table core/ConTable.qza

qiime feature-table filter-seqs --i-data core/RepSeq_neg.qza \
                                --i-table core/ConTable.qza \
                                --o-filtered-data core/ConRepSeq.qza

# Summarization and export
##########################

qiime feature-table summarize --i-table core/Table.qza --m-sample-metadata-file $METADATA --o-visualization visual/Table.qzv
qiime feature-table summarize --i-table core/ConTable.qza --m-sample-metadata-file $METADATA --o-visualization visual/ConTable.qzv
qiime feature-table summarize --i-table core/Table_neg.qza --m-sample-metadata-file $METADATA --o-visualization visual/Table_neg.qzv
qiime feature-table tabulate-seqs --i-data core/RepSeq_neg.qza --o-visualization visual/RepSeq_neg.qzv
qiime feature-table tabulate-seqs --i-data core/RepSeq.qza --o-visualization visual/RepSeq.qzv
qiime feature-table tabulate-seqs --i-data core/HitNegCtrl.qza --o-visualization visual/HitNegCtrl.qzv

mkdir -p export/core
mkdir -p export/visual

for FILE in Table ConTable Table_neg RepSeq RepSeq_neg HitNegCtrl ConRepSeq Stats Stats_neg; do
    qiime tools export --input-path core/${FILE}.qza --output-path export/core/${FILE}
done

for FILE in Table ConTable Table_neg RepSeq RepSeq_neg HitNegCtrl ConRepSeq Stats Stats_neg; do
    qiime tools export --input-path visual/${FILE}.qzv --output-path export/visual/${FILE}
done
