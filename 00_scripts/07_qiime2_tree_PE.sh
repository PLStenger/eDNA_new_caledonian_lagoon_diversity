#!/usr/bin/env bash

WORKING_DIRECTORY=/home/fungi/eDNA_new_caledonian_lagoon_diversity/05_QIIME2
OUTPUT=/home/fungi/eDNA_new_caledonian_lagoon_diversity/05_QIIME2/visual
TMPDIR=/home

# Make the directory (mkdir) only if not existe already(-p)
mkdir -p $OUTPUT

# Aim: construct a rooted phylogenetic tree

cd $WORKING_DIRECTORY

# Make the directory (mkdir) only if not existe already(-p)
mkdir -p tree
mkdir -p export/tree

eval "$(conda shell.bash hook)"
conda activate qiime2-2021.4

# I'm doing this step in order to deal the no space left in cluster :
export TMPDIR='/home/fungi'
echo $TMPDIR

#carry out a multiple seqeunce alignment using Mafft

#   --i-sequences core/ConRepSeq.qza \

 qiime alignment mafft \
  --i-sequences core/RepSeq.qza \
  --o-alignment tree/aligned-RepSeq.qza

##mask (or filter) the alignment to remove positions that are highly variable. These positions are generally considered to add noise to a resulting phylogenetic tree.
qiime alignment mask \
  --i-alignment tree/aligned-RepSeq.qza \
  --o-masked-alignment tree/masked-aligned-RepSeq.qza

##create the tree using the Fasttree program
qiime phylogeny fasttree \
  --i-alignment tree/masked-aligned-RepSeq.qza \
  --o-tree tree/unrooted-tree.qza

##root the tree using the longest root
qiime phylogeny midpoint-root \
  --i-tree tree/unrooted-tree.qza \
  --o-rooted-tree tree/rooted-tree.qza
  
  
# This out put is in Newick format, see http://scikit-bio.org/docs/latest/generated/skbio.io.format.newick.html  
# See it on https://itol.embl.de


qiime tools export --input-path tree/unrooted-tree.qza --output-path export/tree/unrooted-tree
qiime tools export --input-path tree/rooted-tree.qza --output-path export/tree/rooted-tree
qiime tools export --input-path tree/aligned-RepSeq.qza --output-path export/tree/aligned-RepSeq
qiime tools export --input-path tree/masked-aligned-RepSeq.qza --output-path export/tree/masked-aligned-RepSeq
