#!/usr/bin/env bash

# Script UNESCO eDNA Expeditions - NEW CALEDONIA LAGOON - VERSION CORRIGÉE
# Correction: Format TSV pour les manifests (pas CSV)

WORKING_DIRECTORY=/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity/05_QIIME2
DATABASE=/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity/98_database_files
RAW_DATA=/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity/01_raw_data
QIIME_ENV="qiime2-amplicon-2025.7"

cd $WORKING_DIRECTORY

echo "======================================================================="
echo "UNESCO eDNA EXPEDITIONS - NEW CALEDONIA LAGOON DIVERSITY"
echo "VERSION CORRIGÉE - Manifests au format TSV"
echo "======================================================================="
echo ""

#################################################################################
# PRIMERS UNESCO eDNA Expeditions (5 marqueurs)
#################################################################################

MIFISH_F="GTCGGTAAAACTCGTGCCAGC"
MIFISH_R="CATAGTGGGGTATCTAATCCCAGTTTG"
MIMAMMAL_F="CCAAACTGGGATTAGATACCCCACTAT"
MIMAMMAL_R="AGAATGAAGGGTAGATGTAAGCTT"
TELEO_F="ACACCGCCCGTCACTCT"
TELEO_R="CTTCCGGTACACTTACCATG"
COI_F="GGWACWGGWTGAACWGTWTAYCCYCC"
COI_R="TANACYTCNGGRTGNCCRAARAAYCA"
VERT16S_F="AGACGAGAAGACCCTRTG"
VERT16S_R="GATCCAACATCGAGGTCGTAA"

#################################################################################
# MÉTADONNÉES ÉCHANTILLONS
#################################################################################

cat > sample_mapping.tsv << 'EOF'
sample-id	srr
Poe1	SRR29659654
Kouare1	SRR29659655
GrandLagonNord1	SRR29659657
Pouebo1	SRR29659658
Entrecasteaux1	SRR29659660
GrandLagonNord2	SRR29659906
Kouare2	SRR29659907
Entrecasteaux2	SRR29659651
Pouebo2	SRR29659652
Poe2	SRR29659653
Pouebo2bis	SRR29659656
GrandLagonNord3	SRR29659899
Poe3	SRR29659903
Kouare3	SRR29659904
Entrecasteaux3	SRR29659905
Entrecasteaux4	SRR29659896
Kouare4	SRR29659898
Poe4	SRR29659900
Pouebo4	SRR29659902
Control	SRR29659756
EOF

#################################################################################
# ÉTAPE 1: SÉPARATION PAR MARQUEUR (si pas déjà fait)
#################################################################################

if [ ! -d "01-cutadapt/12S-MiFish" ] || [ -z "$(ls -A 01-cutadapt/12S-MiFish/*.fastq.gz 2>/dev/null)" ]; then
    echo "=== ÉTAPE 1: Séparation des lectures par marqueur ==="
    echo ""
    
    mkdir -p 01-cutadapt/12S-MiFish
    mkdir -p 01-cutadapt/12S-Mimammal
    mkdir -p 01-cutadapt/12S-Teleo
    mkdir -p 01-cutadapt/COI
    mkdir -p 01-cutadapt/16S-Vert
    mkdir -p 01-cutadapt/logs
    
    separate_sample() {
        local sample_name=$1
        local srr_id=$2
        local fastq_file="${RAW_DATA}/${srr_id}.fastq"
        
        if [ ! -f "$fastq_file" ]; then
            echo "⚠️  Fichier manquant: $fastq_file"
            return 1
        fi
        
        echo "Traitement: $sample_name ($srr_id)"
        
        # 12S MiFish
        cutadapt -g "$MIFISH_F" -a "$MIFISH_R" --discard-untrimmed --minimum-length 50 --cores 2 \
            -o "01-cutadapt/12S-MiFish/${sample_name}_12S-MiFish.fastq.gz" "$fastq_file" \
            > "01-cutadapt/logs/${sample_name}_12S-MiFish.log" 2>&1
        
        # 12S Mimammal
        cutadapt -g "$MIMAMMAL_F" -a "$MIMAMMAL_R" --discard-untrimmed --minimum-length 50 --cores 2 \
            -o "01-cutadapt/12S-Mimammal/${sample_name}_12S-Mimammal.fastq.gz" "$fastq_file" \
            > "01-cutadapt/logs/${sample_name}_12S-Mimammal.log" 2>&1
        
        # 12S Teleo
        cutadapt -g "$TELEO_F" -a "$TELEO_R" --discard-untrimmed --minimum-length 50 --cores 2 \
            -o "01-cutadapt/12S-Teleo/${sample_name}_12S-Teleo.fastq.gz" "$fastq_file" \
            > "01-cutadapt/logs/${sample_name}_12S-Teleo.log" 2>&1
        
        # COI
        cutadapt -g "$COI_F" -a "$COI_R" --discard-untrimmed --minimum-length 100 --cores 2 \
            -o "01-cutadapt/COI/${sample_name}_COI.fastq.gz" "$fastq_file" \
            > "01-cutadapt/logs/${sample_name}_COI.log" 2>&1
        
        # 16S Vert
        cutadapt -g "$VERT16S_F" -a "$VERT16S_R" --discard-untrimmed --minimum-length 100 --cores 2 \
            -o "01-cutadapt/16S-Vert/${sample_name}_16S-Vert.fastq.gz" "$fastq_file" \
            > "01-cutadapt/logs/${sample_name}_16S-Vert.log" 2>&1
    }
    
    while IFS=$'\t' read -r sample_name srr_id; do
        if [ "$sample_name" != "sample-id" ]; then
            separate_sample "$sample_name" "$srr_id"
        fi
    done < sample_mapping.tsv
    
    echo "✓ Séparation terminée"
else
    echo "✓ Séparation déjà effectuée (skip)"
fi
echo ""

#################################################################################
# ÉTAPE 2: IMPORT QIIME2 - FORMAT TSV CORRIGÉ
#################################################################################

echo "=== ÉTAPE 2: Import QIIME2 par marqueur (format TSV) ==="
echo ""

mkdir -p 02-qiime2/by_marker

import_marker_corrected() {
    local marker_name=$1
    local marker_dir=$2
    
    echo "--- Import QIIME2: $marker_name ---"
    
    # CORRECTION: Créer un manifest au format TSV (tabulations)
    manifest_file="02-qiime2/by_marker/manifest_${marker_name}.tsv"
    
    # Header avec TABULATION
    printf "sample-id\tabsolute-filepath\n" > "$manifest_file"
    
    # Parcourir les fichiers FASTQ
    for fastq_file in ${marker_dir}/*.fastq.gz; do
        if [ -f "$fastq_file" ]; then
            base_name=$(basename "$fastq_file" "_${marker_name}.fastq.gz")
            abs_path=$(realpath "$fastq_file")
            
            # Ajouter avec TABULATION
            printf "%s\t%s\n" "$base_name" "$abs_path" >> "$manifest_file"
        fi
    done
    
    sample_count=$(($(wc -l < "$manifest_file") - 1))
    echo "  ✓ Manifest TSV créé: $sample_count échantillons"
    
    # Vérifier le format du manifest
    echo "  Aperçu du manifest:"
    head -3 "$manifest_file" | cat -A  # cat -A montre les tabs
    
    # Import dans QIIME2
    if [ ! -f "02-qiime2/by_marker/demux_${marker_name}.qza" ]; then
        conda run -n $QIIME_ENV qiime tools import \
            --type 'SampleData[SequencesWithQuality]' \
            --input-path "$manifest_file" \
            --output-path "02-qiime2/by_marker/demux_${marker_name}.qza" \
            --input-format SingleEndFastqManifestPhred33V2
        
        if [ $? -eq 0 ]; then
            echo "  ✓ Import QIIME2 réussi: demux_${marker_name}.qza"
        else
            echo "  ❌ ERREUR lors de l'import QIIME2"
            return 1
        fi
    else
        echo "  ✓ Import existe déjà: demux_${marker_name}.qza"
    fi
    
    echo ""
}

import_marker_corrected "12S-MiFish" "01-cutadapt/12S-MiFish"
import_marker_corrected "12S-Mimammal" "01-cutadapt/12S-Mimammal"
import_marker_corrected "12S-Teleo" "01-cutadapt/12S-Teleo"
import_marker_corrected "COI" "01-cutadapt/COI"
import_marker_corrected "16S-Vert" "01-cutadapt/16S-Vert"

#################################################################################
# ÉTAPE 3: DADA2 PAR MARQUEUR
#################################################################################

echo "=== ÉTAPE 3: DADA2 denoising par marqueur ==="
echo ""

mkdir -p 03-dada2

run_dada2_single() {
    local marker_name=$1
    local demux_file=$2
    local trim_left=$3
    local trunc_len=$4
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "DADA2: $marker_name"
    echo "Paramètres: trim-left=$trim_left, trunc-len=$trunc_len"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [ ! -f "$demux_file" ]; then
        echo "  ❌ ERREUR: Fichier demux manquant: $demux_file"
        echo "  L'import QIIME2 a échoué pour ce marqueur"
        return 1
    fi
    
    if [ ! -f "03-dada2/table_${marker_name}.qza" ]; then
        conda run -n $QIIME_ENV qiime dada2 denoise-single \
            --i-demultiplexed-seqs "$demux_file" \
            --p-trim-left $trim_left \
            --p-trunc-len $trunc_len \
            --p-n-threads 4 \
            --o-table "03-dada2/table_${marker_name}.qza" \
            --o-representative-sequences "03-dada2/rep_seqs_${marker_name}.qza" \
            --o-denoising-stats "03-dada2/stats_${marker_name}.qza"
        
        if [ $? -eq 0 ]; then
            echo "  ✓ DADA2 terminé pour $marker_name"
            
            # Stats
            conda run -n $QIIME_ENV qiime metadata tabulate \
                --m-input-file "03-dada2/stats_${marker_name}.qza" \
                --o-visualization "03-dada2/stats_${marker_name}.qzv"
        else
            echo "  ❌ ERREUR DADA2 pour $marker_name"
            return 1
        fi
    else
        echo "  ✓ DADA2 existe déjà pour $marker_name"
    fi
    
    echo ""
}

run_dada2_single "12S-MiFish" "02-qiime2/by_marker/demux_12S-MiFish.qza" 0 220
run_dada2_single "12S-Mimammal" "02-qiime2/by_marker/demux_12S-Mimammal.qza" 0 220
run_dada2_single "12S-Teleo" "02-qiime2/by_marker/demux_12S-Teleo.qza" 0 220
run_dada2_single "COI" "02-qiime2/by_marker/demux_COI.qza" 0 250
run_dada2_single "16S-Vert" "02-qiime2/by_marker/demux_16S-Vert.qza" 0 240

#################################################################################
# ÉTAPE 4: ASSIGNATION TAXONOMIQUE
#################################################################################

echo "=== ÉTAPE 4: Assignation taxonomique par marqueur ==="
echo ""

mkdir -p 04-taxonomy
mkdir -p export/taxonomy

assign_taxonomy() {
    local marker_name=$1
    local rep_seqs_file=$2
    local classifier=$3
    local output_name=$4
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Assignation taxonomique: $marker_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [ ! -f "$rep_seqs_file" ]; then
        echo "  ❌ ERREUR: Fichier rep-seqs manquant: $rep_seqs_file"
        echo "  DADA2 n'a pas fonctionné pour ce marqueur"
        return 1
    fi
    
    if [ ! -f "$DATABASE/$classifier" ]; then
        echo "  ⚠️  ERREUR: Classificateur manquant: $DATABASE/$classifier"
        echo "  Vous devez d'abord créer les bases de données marines"
        return 1
    fi
    
    if [ ! -f "04-taxonomy/${output_name}.qza" ]; then
        conda run -n $QIIME_ENV qiime feature-classifier classify-sklearn \
            --i-classifier "$DATABASE/$classifier" \
            --i-reads "$rep_seqs_file" \
            --o-classification "04-taxonomy/${output_name}.qza" \
            --p-confidence 0.7 \
            --p-n-jobs 4
    fi
    
    # Export TSV
    conda run -n $QIIME_ENV qiime tools export \
        --input-path "04-taxonomy/${output_name}.qza" \
        --output-path "export/taxonomy/${output_name}_temp/"
    
    mv "export/taxonomy/${output_name}_temp/taxonomy.tsv" "export/taxonomy/${output_name}.tsv"
    rm -rf "export/taxonomy/${output_name}_temp/"
    
    # Statistiques
    if [ -f "export/taxonomy/${output_name}.tsv" ]; then
        local total=$(($(wc -l < "export/taxonomy/${output_name}.tsv") - 2))
        local species=$(grep -c ";s__" "export/taxonomy/${output_name}.tsv" 2>/dev/null || echo 0)
        
        echo "  ✓ ASVs assignés: $total"
        echo "  ✓ Niveau espèce: $species"
        echo "  ✓ Fichier: export/taxonomy/${output_name}.tsv"
        echo ""
        echo "  Aperçu:"
        head -5 "export/taxonomy/${output_name}.tsv" | tail -3
    fi
    
    echo ""
}

assign_taxonomy "12S-MiFish" "03-dada2/rep_seqs_12S-MiFish.qza" "mifish_marine_classifier.qza" "taxonomy_12SMifish"
assign_taxonomy "12S-Mimammal" "03-dada2/rep_seqs_12S-Mimammal.qza" "mammal_marine_12s_classifier.qza" "taxonomy_12SMimammal"
assign_taxonomy "12S-Teleo" "03-dada2/rep_seqs_12S-Teleo.qza" "teleo_marine_12s_classifier.qza" "taxonomy_12STeleo"
assign_taxonomy "COI" "03-dada2/rep_seqs_COI.qza" "coi_marine_classifier.qza" "taxonomy_CO1"
assign_taxonomy "16S-Vert" "03-dada2/rep_seqs_16S-Vert.qza" "vert_marine_16s_classifier.qza" "taxonomy_16S"

echo ""
echo "======================================================================="
echo "✓ PIPELINE TERMINÉ"
echo "======================================================================="
echo ""
echo "Vérifiez les résultats dans:"
echo "  - 03-dada2/stats_*.qzv (ouvrir sur https://view.qiime2.org)"
echo "  - export/taxonomy/*.tsv (fichiers de taxonomie finaux)"
echo ""
