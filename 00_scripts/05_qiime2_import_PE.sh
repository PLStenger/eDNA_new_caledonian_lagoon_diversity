#!/usr/bin/env bash

WORKING_DIRECTORY=/scratch_vol0/fungi/eDNA_new_caledonian_lagoon_diversity/03_cleaned_data/raw_sequences_comp
OUTPUT=/scratch_vol0/fungi/eDNA_new_caledonian_lagoon_diversity/05_QIIME2

# Make the directory (mkdir) only if not existe already(-p)
mkdir -p $OUTPUT

# You need a "manifest" for explaining and importing your data :
# In the fastq manifest formats, a manifest file maps sample identifiers to fastq.gz or fastq absolute filepaths that contain sequence and quality data for the sample, and indicates the direction of the reads in each fastq.gz / fastq absolute filepath. The manifest file will generally be created by you, and it is designed to be a simple format that doesn’t put restrictions on the naming of the demultiplexed fastq.gz / fastq files, since there is no broadly used naming convention for these files. There are no restrictions on the name of the manifest file.
# See https://docs.qiime2.org/2018.8/tutorials/importing/

MANIFEST=/scratch_vol0/fungi/eDNA_new_caledonian_lagoon_diversity/98_database_files/manifest
MANIFEST_control_samples=/scratch_vol0/fungi/eDNA_new_caledonian_lagoon_diversity/98_database_files/manifest_control
TMPDIR=/scratch_vol0

###############################################################
### For importing your data in a Qiime2 format
###############################################################

cd $WORKING_DIRECTORY

eval "$(conda shell.bash hook)"
conda activate qiime2-2021.4

# Make the directory (mkdir) only if not existe already(-p)
mkdir -p $OUTPUT/core
mkdir -p $OUTPUT/visual

# I'm doing this step in order to deal the no space left in cluster :
export TMPDIR='/scratch_vol0/fungi'
echo $TMPDIR

qiime tools import \
    --type 'SampleData[SequencesWithQuality]' \
    --input-path $MANIFEST \
    --output-path $OUTPUT/core/demux.qza \
    --input-format SingleEndFastqManifestPhred33V2

qiime tools import \
    --type 'SampleData[SequencesWithQuality]' \
    --input-path $MANIFEST_control_samples \
    --output-path $OUTPUT/core/demux_neg.qza \
    --input-format SingleEndFastqManifestPhred33V2



cd $OUTPUT

qiime demux summarize --i-data core/demux.qza --o-visualization visual/demux.qzv
qiime demux summarize --i-data core/demux_neg.qza --o-visualization visual/demux_neg.qzv

# for vizualisation :
# https://view.qiime2.org

qiime tools export --input-path visual/demux.qzv --output-path export/visual/demux
qiime tools export --input-path core/demux.qza --output-path export/core/demux
qiime tools export --input-path visual/demux_neg.qzv --output-path export/visual/demux_neg
qiime tools export --input-path core/demux_neg.qza --output-path export/core/demux_neg
