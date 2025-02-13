#!/usr/bin/env bash

WORKING_DIRECTORY=/scratch_vol0/fungi/eDNA_new_caledonian_lagoon_diversity/05_QIIME2
OUTPUT=/scratch_vol0/fungi/eDNA_new_caledonian_lagoon_diversity/05_QIIME2/visual

DATABASE=/scratch_vol0/fungi/eDNA_new_caledonian_lagoon_diversity/98_database_files
TMPDIR=/scratch_vol0


# Aim: classify reads by taxon using a fitted classifier

# https://docs.qiime2.org/2019.10/tutorials/moving-pictures/
# In this step, you will take the denoised sequences from step 5 (rep-seqs.qza) and assign taxonomy to each sequence (phylum -> class -> …genus -> ). 
# This step requires a trained classifer. You have the choice of either training your own classifier using the q2-feature-classifier or downloading a pretrained classifier.

# https://docs.qiime2.org/2019.10/tutorials/feature-classifier/


# Aim: Import data to create a new QIIME 2 Artifact
# https://gitlab.com/IAC_SolVeg/CNRT_BIOINDIC/-/blob/master/snk/12_qiime2_taxonomy


###############################################################
### For all
###############################################################

#############################################################################################################################################################################################
# Amplification with 12S-Mifish-UE, 12S-Mimammal-UEB, 12S-Teleo, COI-Leray-Geller and 16S-Vert-Vences combined in same sequenced sample
#############################################################################################################################################################################################

###############################################################
# 12S-Mifish-UE
# Ferreira et al 2024
# https://www.nature.com/articles/s41598-024-69963-7.pdf
#
# Mais, citation original de Miya et al 2015:
# Miya,M.etal.MiFish,asetofuniversalPCRprimersformetabarcodingenvironmentalDNAfromfishes:Detectionofmorethan230 subtropical marine species. R. Soc. Open Sci. 2, 150088 (2015).
#
# miFISH-U + miFISH-E (∼ 170 bp) 12S 
# 
# (F)
# miFISH-U_F: GTCGGTAAAACTCGTGCCAGC 
# miFISH-E_F: GTTGGTAAATCTCGTGCCAGC
#      
# (R)
# miFISH-U_R: CATAGTGGGGTATCTAATCCCAGTTTG 
# miFISH-E_R: CATAGTGGGGTATCTAATCCTAGTTTG
###############################################################

###############################################################
# 12S-Mimammal-UEB
# Ushio et al 2017 mais regarder optimisation par Schenekar et al 2023
#
# MiMammal-UEB_5-7_fwd ACACTCTTTCCCTACACGACGCTCTTCCGATCT (N)5-7 GGRYTGGTHAATTTCGTGCCAGC 
# MiMammal-UEB_5-7_rev GTGACTGGAGTTCAGACGTGTGCTCTTCCGATCT(N)5-7 CATAGTGRGGTATCTAATCYCAGTTTG
#
###############################################################

###############################################################
# 12S-Teleo
# voir Polanco et al 2021 pour comparaison avec Mifish mais pas de séquences

# Valentini et al 2016
# teleo_F (L1848) ACACCGCCCGTCACTCT
# teleo_R (H1913) CTTCCGGTACACTTACCATG
# 
###############################################################

###############################################################
# COI-Leray-Geller
###############################################################
# a 313 bp fragment from the COI gene using seven-tailed primer pairs of mICOIintF and jgHCO2190 (Geller et al., 2013; Leray et al., 2013)
# These primers included six base pair tags on the 5′ end of each primer (Table S1) :

# Primer Label	Primer Sequence (5'-3')
# m1COIintF_Tag1	AGACGCGGWACWGGWTGAACWGTWTAYCCYCC
# m1COIintF_Tag2	AGTGTAGGWACWGGWTGAACWGTWTAYCCYCC
# m1COIintF_Tag3	ACTAGCGGWACWGGWTGAACWGTWTAYCCYCC
# m1COIintF_Tag4	ACAGTCGGWACWGGWTGAACWGTWTAYCCYCC
# m1COIintF_Tag5	ATCGACGGWACWGGWTGAACWGTWTAYCCYCC
# m1COIintF_Tag6	ATGTCGGGWACWGGWTGAACWGTWTAYCCYCC
# m1COIintF_Tag7	ATAGCAGGWACWGGWTGAACWGTWTAYCCYCC
# jgHCO_Tag1	AGACGCTAIACYTCIGGRTGICCRAARAAYCA
# jgHCO_Tag2	AGTGTATAIACYTCIGGRTGICCRAARAAYCA
# jgHCO_Tag3	ACTAGCTAIACYTCIGGRTGICCRAARAAYCA
# jgHCO_Tag4	ACAGTCTAIACYTCIGGRTGICCRAARAAYCA
# jgHCO_Tag5	ATCGACTAIACYTCIGGRTGICCRAARAAYCA
# jgHCO_Tag6	ATGTCGTAIACYTCIGGRTGICCRAARAAYCA
# jgHCO_Tag7	ATAGCATAIACYTCIGGRTGICCRAARAAYCA


###############################################################
# 16S-Vert-Vences
###############################################################


cd $WORKING_DIRECTORY

eval "$(conda shell.bash hook)"
conda activate qiime2-2021.4

# I'm doing this step in order to deal the no space left in cluster :
export TMPDIR='/scratch_vol0/fungi'
echo $TMPDIR

# Make the directory (mkdir) only if not existe already(-p)
mkdir -p taxonomy
mkdir -p export/taxonomy


#qiime tools import \
#  --type 'FeatureData[Sequence]' \
#  --input-path /scratch_vol0/fungi/eDNA_new_caledonian_lagoon_diversity/98_database_files/MI_Fish_mito-all_version_4_09_from_2025_02_08.fasta \
#  --output-path MI_Fish.qza

# All fish and mammals:

#qiime rescript get-ncbi-data \
#    --p-query '(txid7777[ORGN] OR txid7898[ORGN] OR txid118072[ORGN] OR txid117569[ORGN] OR txid117565[ORGN] OR txid7878[ORGN] OR txid40674[ORGN]) AND (12S OR "12S ribosomal RNA" OR "12S rRNA") NOT "environmental sample"[Title] NOT "environmental samples"[Title] NOT "environmental"[Title] NOT "uncultured"[Title] NOT "unclassified"[Title] NOT "unidentified"[Title] NOT "unverified"[Title]' \
#    --o-sequences taxonomy/12S-16S-18S-tax.qza \
#    --o-taxonomy taxonomy/DataSeq.qza \
#    --p-n-jobs 1

# from https://www.researchgate.net/publication/349299040_Mitohelper_A_mitochondrial_reference_sequence_analysis_tool_for_fish_eDNA_studies
# and https://github.com/aomlomics/mitohelper/tree/master/QIIME-compatible
#scp -r /scratch_vol0/fungi/eDNA_new_caledonian_lagoon_diversity/98_database_files/12S-16S-18S-seqs.qza /scratch_vol0/fungi/eDNA_new_caledonian_lagoon_diversity/05_QIIME2/taxonomy
#scp -r /scratch_vol0/fungi/eDNA_new_caledonian_lagoon_diversity/98_database_files/12S-16S-18S-tax.qza /scratch_vol0/fungi/eDNA_new_caledonian_lagoon_diversity/05_QIIME2/taxonomy

scp -r /scratch_vol0/fungi/eDNA_new_caledonian_lagoon_diversity/98_database_files/12S-seqs-derep-uniq.qza /scratch_vol0/fungi/eDNA_new_caledonian_lagoon_diversity/05_QIIME2/taxonomy
scp -r /scratch_vol0/fungi/eDNA_new_caledonian_lagoon_diversity/98_database_files/12S-tax-derep-uniq.qza /scratch_vol0/fungi/eDNA_new_caledonian_lagoon_diversity/05_QIIME2/taxonomy


 qiime feature-classifier fit-classifier-naive-bayes \
   --i-reference-reads taxonomy/12S-seqs-derep-uniq.qza \
   --i-reference-taxonomy taxonomy/12S-tax-derep-uniq.qza \
   --o-classifier taxonomy/Classifier.qza


 qiime feature-classifier classify-sklearn \
   --i-classifier taxonomy/Classifier.qza \
   --i-reads core/RepSeq.qza \
   --o-classification taxonomy/taxonomy_reads-per-batch_RepSeq_sklearn.qza
 
 qiime feature-classifier classify-sklearn \
   --i-classifier taxonomy/Classifier.qza \
   --i-reads core/RarRepSeq.qza \
   --o-classification taxonomy/taxonomy_reads-per-batch_RarRepSeq_sklearn.qza
 
#qiime feature-classifier classify-consensus-blast \
#  --i-query core/RepSeq.qza \
#  --i-reference-reads taxonomy/12S-16S-18S-seqs.qza \
#  --i-reference-taxonomy taxonomy/12S-16S-18S-tax.qza \
#  --p-perc-identity 0.70 \
#  --o-classification taxonomy/taxonomy_reads-per-batch_RepSeq_blast.qza \
#  --verbose

qiime feature-classifier classify-consensus-vsearch \
    --i-query core/RepSeq.qza  \
    --i-reference-reads taxonomy/12S-16S-18S-seqs.qza \
    --i-reference-taxonomy taxonomy/12S-16S-18S-tax.qza \
    --p-perc-identity 0.77 \
    --p-query-cov 0.3 \
    --p-top-hits-only \
    --p-maxaccepts 1 \
    --p-strand 'both' \
    --p-unassignable-label 'Unassigned' \
    --p-threads 12 \
    --o-classification taxonomy/taxonomy_reads-per-batch_RepSeq_vsearch.qza
    
qiime feature-classifier classify-consensus-vsearch \
    --i-query core/RarRepSeq.qza  \
    --i-reference-reads taxonomy/12S-16S-18S-seqs.qza \
    --i-reference-taxonomy taxonomy/12S-16S-18S-tax.qza \
    --p-perc-identity 0.77 \
    --p-query-cov 0.3 \
    --p-top-hits-only \
    --p-maxaccepts 1 \
    --p-strand 'both' \
    --p-unassignable-label 'Unassigned' \
    --p-threads 12 \
    --o-classification taxonomy/taxonomy_reads-per-batch_RarRepSeq_vsearch.qza

 qiime taxa barplot \
  --i-table core/RarTable.qza \
  --i-taxonomy taxonomy/taxonomy_reads-per-batch_RarRepSeq_vsearch.qza \
  --m-metadata-file $DATABASE/sample-metadata.tsv \
  --o-visualization taxonomy/taxa-bar-plots_reads-per-batch_RarRepSeq_vsearch.qzv 
  
  
   qiime taxa barplot \
  --i-table core/RarTable.qza \
  --i-taxonomy taxonomy/taxonomy_reads-per-batch_RepSeq_vsearch.qza \
  --m-metadata-file $DATABASE/sample-metadata.tsv \
  --o-visualization taxonomy/taxa-bar-plots_reads-per-batch_RepSeq_vsearch.qzv 


qiime tools export --input-path taxonomy/taxonomy_reads-per-batch_RepSeq_sklearn.qza --output-path export/taxonomy/taxonomy_reads-per-batch_RepSeq_sklearn
qiime tools export --input-path taxonomy/taxonomy_reads-per-batch_RarRepSeq_sklearn.qza --output-path export/taxonomy/taxonomy_reads-per-batch_RarRepSeq_sklearn

qiime tools export --input-path taxonomy/taxa-bar-plots_reads-per-batch_RarRepSeq_vsearch.qzv --output-path export/taxonomy/taxa-bar-plots_reads-per-batch_RarRepSeq_vsearch
qiime tools export --input-path taxonomy/taxa-bar-plots_reads-per-batch_RepSeq_vsearch.qzv --output-path export/taxonomy/taxa-bar-plots_reads-per-batch_RepSeq_vsearch

qiime tools export --input-path taxonomy/taxonomy_reads-per-batch_RepSeq_vsearch.qzv --output-path export/taxonomy/taxonomy_reads-per-batch_RepSeq_vsearch_visual
qiime tools export --input-path taxonomy/taxonomy_reads-per-batch_RarRepSeq_vsearch.qzv --output-path export/taxonomy/taxonomy_reads-per-batch_RarRepSeq_vsearch_visual

qiime tools export --input-path taxonomy/taxonomy_reads-per-batch_RarRepSeq_vsearch.qza --output-path export/taxonomy/taxonomy_reads-per-batch_RarRepSeq_vsearch
qiime tools export --input-path taxonomy/taxonomy_reads-per-batch_RepSeq_vsearch.qza --output-path export/taxonomy/taxonomy_reads-per-batch_RepSeq_vsearch
qiime tools export --input-path taxonomy/taxonomy_reads-per-batch_RarRepSeq.qza --output-path export/taxonomy/taxonomy_reads-per-batch_RarRepSeq



