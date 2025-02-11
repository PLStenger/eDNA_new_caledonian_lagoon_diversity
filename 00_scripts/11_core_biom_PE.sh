#!/usr/bin/env bash

WORKING_DIRECTORY=/scratch_vol0/fungi/eDNA_new_caledonian_lagoon_diversity/05_QIIME2
OUTPUT=/scratch_vol0/fungi/eDNA_new_caledonian_lagoon_diversity/05_QIIME2/visual

DATABASE=/scratch_vol0/fungi/eDNA_new_caledonian_lagoon_diversity/98_database_files
TMPDIR=/scratch_vol0

#########################################

cd $WORKING_DIRECTORY

eval "$(conda shell.bash hook)"
conda activate qiime2-2021.4

# Make the directory (mkdir) only if not existe already(-p)
mkdir -p subtables
mkdir -p export/subtables

# I'm doing this step in order to deal the no space left in cluster :
export TMPDIR='/scratch_vol0/fungi'
echo $TMPDIR

# Aim: Filter sample from table based on a feature table or metadata

        
mv core/RarTable.qza subtables/RarTable-all.qza

 
# Aim: Identify "core" features, which are features observed,
     # in a user-defined fraction of the samples
        
qiime feature-table core-features \
        --i-table subtables/RarTable-all.qza \
        --p-min-fraction 0.1 \
        --p-max-fraction 1.0 \
        --p-steps 10 \
        --o-visualization visual/CoreBiom-all.qzv  
        
qiime tools export --input-path subtables/RarTable-all.qza --output-path export/subtables/RarTable-all    
qiime tools export --input-path visual/CoreBiom-all.qzv --output-path export/visual/CoreBiom-all
biom convert -i export/subtables/RarTable-all/feature-table.biom -o export/subtables/RarTable-all/table-from-biom.tsv --to-tsv
sed '1d ; s/\#OTU ID/ASV_ID/' export/subtables/RarTable-all/table-from-biom.tsv > export/subtables/RarTable-all/ASV.tsv


