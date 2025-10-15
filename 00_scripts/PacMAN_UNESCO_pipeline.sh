#!/usr/bin/env bash

# Script UNESCO eDNA Expeditions - NEW CALEDONIA LAGOON
# Single-end FASTQ avec 5 marqueurs multiplexés
# Séparation par marqueur AVANT QIIME2/DADA2

WORKING_DIRECTORY=/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity/05_QIIME2
DATABASE=/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity/98_database_files
RAW_DATA=/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity/01_raw_data
QIIME_ENV="qiime2-amplicon-2025.7"

cd $WORKING_DIRECTORY

echo "======================================================================="
echo "UNESCO eDNA EXPEDITIONS - NEW CALEDONIA LAGOON DIVERSITY"
echo "Séparation des 5 marqueurs depuis FASTQ single-end multiplexés"
echo "======================================================================="
echo ""
echo "Échantillons: Poe, Kouare, GrandLagonNord, Pouebo, Entrecasteaux"
echo "Control: SRR29659756"
echo "Marqueurs: 12S-MiFish, 12S-Mimammal, 12S-Teleo, COI, 16S-Vert"
echo ""

mkdir -p 01-cutadapt
mkdir -p 01-cutadapt/logs
mkdir -p 02-qiime2/by_marker
mkdir -p 03-dada2
mkdir -p 04-taxonomy
mkdir -p export/taxonomy

#################################################################################
# PRIMERS UNESCO eDNA Expeditions (5 marqueurs)
#################################################################################

# 12S MiFish-UE (poissons)
MIFISH_F="GTCGGTAAAACTCGTGCCAGC"
MIFISH_R="CATAGTGGGGTATCTAATCCCAGTTTG"

# 12S Mimammal-UEB (mammifères marins)
MIMAMMAL_F="CCAAACTGGGATTAGATACCCCACTAT"
MIMAMMAL_R="AGAATGAAGGGTAGATGTAAGCTT"

# 12S Teleo (téléostéens)
TELEO_F="ACACCGCCCGTCACTCT"
TELEO_R="CTTCCGGTACACTTACCATG"

# COI Leray-Geller (faune diverse)
COI_F="GGWACWGGWTGAACWGTWTAYCCYCC"
COI_R="TANACYTCNGGRTGNCCRAARAAYCA"

# 16S Vert-Vences (vertébrés)
VERT16S_F="AGACGAGAAGACCCTRTG"
VERT16S_R="GATCCAACATCGAGGTCGTAA"

echo "✓ Primers définis pour les 5 marqueurs"
echo ""

#################################################################################
# MÉTADONNÉES ÉCHANTILLONS
#################################################################################

# Créer un fichier de mapping sample-id -> SRR
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

echo "✓ Fichier de mapping créé: sample_mapping.tsv"
echo ""

#################################################################################
# ÉTAPE 1: SÉPARATION PAR MARQUEUR AVEC CUTADAPT (SINGLE-END)
#################################################################################

echo "=== ÉTAPE 1: Séparation des lectures par marqueur ==="
echo ""
echo "Note: Vos fichiers sont SINGLE-END avec marqueurs multiplexés"
echo "Cutadapt va créer un fichier par marqueur pour chaque échantillon"
echo ""

# Fonction pour séparer un échantillon par marqueur
separate_sample_by_markers() {
    local sample_name=$1
    local srr_id=$2
    local fastq_file="${RAW_DATA}/${srr_id}.fastq"
    
    if [ ! -f "$fastq_file" ]; then
        echo "⚠️  ERREUR: Fichier manquant: $fastq_file"
        return 1
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Traitement: $sample_name ($srr_id)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Créer les dossiers de sortie par marqueur
    mkdir -p 01-cutadapt/12S-MiFish
    mkdir -p 01-cutadapt/12S-Mimammal
    mkdir -p 01-cutadapt/12S-Teleo
    mkdir -p 01-cutadapt/COI
    mkdir -p 01-cutadapt/16S-Vert
    
    # Séparer chaque marqueur avec cutadapt
    # Pour single-end, on utilise -g (5' adapter) et -a (3' adapter)
    
    # 12S MiFish
    cutadapt \
        -g "$MIFISH_F" \
        -a "$MIFISH_R" \
        --discard-untrimmed \
        --minimum-length 50 \
        --cores 2 \
        -o "01-cutadapt/12S-MiFish/${sample_name}_12S-MiFish.fastq.gz" \
        "$fastq_file" \
        > "01-cutadapt/logs/${sample_name}_12S-MiFish.log" 2>&1
    
    reads_mifish=$(grep "Reads written" "01-cutadapt/logs/${sample_name}_12S-MiFish.log" | awk '{print $5}' | sed 's/,//g')
    echo "  12S-MiFish: $reads_mifish reads"
    
    # 12S Mimammal
    cutadapt \
        -g "$MIMAMMAL_F" \
        -a "$MIMAMMAL_R" \
        --discard-untrimmed \
        --minimum-length 50 \
        --cores 2 \
        -o "01-cutadapt/12S-Mimammal/${sample_name}_12S-Mimammal.fastq.gz" \
        "$fastq_file" \
        > "01-cutadapt/logs/${sample_name}_12S-Mimammal.log" 2>&1
    
    reads_mimammal=$(grep "Reads written" "01-cutadapt/logs/${sample_name}_12S-Mimammal.log" | awk '{print $5}' | sed 's/,//g')
    echo "  12S-Mimammal: $reads_mimammal reads"
    
    # 12S Teleo
    cutadapt \
        -g "$TELEO_F" \
        -a "$TELEO_R" \
        --discard-untrimmed \
        --minimum-length 50 \
        --cores 2 \
        -o "01-cutadapt/12S-Teleo/${sample_name}_12S-Teleo.fastq.gz" \
        "$fastq_file" \
        > "01-cutadapt/logs/${sample_name}_12S-Teleo.log" 2>&1
    
    reads_teleo=$(grep "Reads written" "01-cutadapt/logs/${sample_name}_12S-Teleo.log" | awk '{print $5}' | sed 's/,//g')
    echo "  12S-Teleo: $reads_teleo reads"
    
    # COI
    cutadapt \
        -g "$COI_F" \
        -a "$COI_R" \
        --discard-untrimmed \
        --minimum-length 100 \
        --cores 2 \
        -o "01-cutadapt/COI/${sample_name}_COI.fastq.gz" \
        "$fastq_file" \
        > "01-cutadapt/logs/${sample_name}_COI.log" 2>&1
    
    reads_coi=$(grep "Reads written" "01-cutadapt/logs/${sample_name}_COI.log" | awk '{print $5}' | sed 's/,//g')
    echo "  COI: $reads_coi reads"
    
    # 16S Vert
    cutadapt \
        -g "$VERT16S_F" \
        -a "$VERT16S_R" \
        --discard-untrimmed \
        --minimum-length 100 \
        --cores 2 \
        -o "01-cutadapt/16S-Vert/${sample_name}_16S-Vert.fastq.gz" \
        "$fastq_file" \
        > "01-cutadapt/logs/${sample_name}_16S-Vert.log" 2>&1
    
    reads_16s=$(grep "Reads written" "01-cutadapt/logs/${sample_name}_16S-Vert.log" | awk '{print $5}' | sed 's/,//g')
    echo "  16S-Vert: $reads_16s reads"
    
    echo ""
}

# Traiter tous les échantillons
while IFS=$'\t' read -r sample_name srr_id; do
    if [ "$sample_name" != "sample-id" ]; then
        separate_sample_by_markers "$sample_name" "$srr_id"
    fi
done < sample_mapping.tsv

echo "✓ Séparation par marqueur terminée pour tous les échantillons"
echo ""

#################################################################################
# ÉTAPE 2: IMPORT QIIME2 PAR MARQUEUR (SINGLE-END)
#################################################################################

echo "=== ÉTAPE 2: Import QIIME2 par marqueur ==="
echo ""

import_marker_single_end() {
    local marker_name=$1
    local marker_dir=$2
    
    echo "--- Import QIIME2: $marker_name ---"
    
    # Créer un manifest pour ce marqueur
    manifest_file="02-qiime2/by_marker/manifest_${marker_name}.csv"
    
    echo "sample-id,absolute-filepath" > "$manifest_file"
    
    for fastq_file in ${marker_dir}/*.fastq.gz; do
        if [ -f "$fastq_file" ]; then
            # Extraire le nom de l'échantillon
            base_name=$(basename "$fastq_file" "_${marker_name}.fastq.gz")
            
            # Chemin absolu requis par QIIME2
            abs_path=$(realpath "$fastq_file")
            
            echo "${base_name},${abs_path}" >> "$manifest_file"
        fi
    done
    
    # Compter les échantillons
    sample_count=$(($(wc -l < "$manifest_file") - 1))
    echo "  ✓ Manifest créé: $sample_count échantillons"
    
    # Import dans QIIME2 (SINGLE-END)
    if [ ! -f "02-qiime2/by_marker/demux_${marker_name}.qza" ]; then
        conda run -n $QIIME_ENV qiime tools import \
            --type 'SampleData[SequencesWithQuality]' \
            --input-path "$manifest_file" \
            --output-path "02-qiime2/by_marker/demux_${marker_name}.qza" \
            --input-format SingleEndFastqManifestPhred33V2
        
        echo "  ✓ Import QIIME2 terminé: demux_${marker_name}.qza"
    else
        echo "  ✓ Import existe déjà: demux_${marker_name}.qza"
    fi
    
    echo ""
}

import_marker_single_end "12S-MiFish" "01-cutadapt/12S-MiFish"
import_marker_single_end "12S-Mimammal" "01-cutadapt/12S-Mimammal"
import_marker_single_end "12S-Teleo" "01-cutadapt/12S-Teleo"
import_marker_single_end "COI" "01-cutadapt/COI"
import_marker_single_end "16S-Vert" "01-cutadapt/16S-Vert"

#################################################################################
# ÉTAPE 3: DENOISING DADA2 PAR MARQUEUR (SINGLE-END)
#################################################################################

echo "=== ÉTAPE 3: DADA2 denoising par marqueur (single-end) ==="
echo ""

run_dada2_single_end() {
    local marker_name=$1
    local demux_file=$2
    local trim_left=$3
    local trunc_len=$4
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "DADA2: $marker_name"
    echo "Paramètres: trim-left=$trim_left, trunc-len=$trunc_len"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [ ! -f "03-dada2/table_${marker_name}.qza" ]; then
        conda run -n $QIIME_ENV qiime dada2 denoise-single \
            --i-demultiplexed-seqs "$demux_file" \
            --p-trim-left $trim_left \
            --p-trunc-len $trunc_len \
            --p-n-threads 4 \
            --o-table "03-dada2/table_${marker_name}.qza" \
            --o-representative-sequences "03-dada2/rep_seqs_${marker_name}.qza" \
            --o-denoising-stats "03-dada2/stats_${marker_name}.qza"
        
        echo "  ✓ DADA2 terminé pour $marker_name"
        
        # Exporter les stats
        conda run -n $QIIME_ENV qiime metadata tabulate \
            --m-input-file "03-dada2/stats_${marker_name}.qza" \
            --o-visualization "03-dada2/stats_${marker_name}.qzv"
    else
        echo "  ✓ DADA2 existe déjà pour $marker_name"
    fi
    
    echo ""
}

# Paramètres DADA2 optimisés par marqueur (single-end)
# À ajuster selon la qualité de vos lectures
run_dada2_single_end "12S-MiFish" "02-qiime2/by_marker/demux_12S-MiFish.qza" 0 220
run_dada2_single_end "12S-Mimammal" "02-qiime2/by_marker/demux_12S-Mimammal.qza" 0 220
run_dada2_single_end "12S-Teleo" "02-qiime2/by_marker/demux_12S-Teleo.qza" 0 220
run_dada2_single_end "COI" "02-qiime2/by_marker/demux_COI.qza" 0 250
run_dada2_single_end "16S-Vert" "02-qiime2/by_marker/demux_16S-Vert.qza" 0 240

#################################################################################
# ÉTAPE 4: ASSIGNATION TAXONOMIQUE PAR MARQUEUR
#################################################################################

echo "=== ÉTAPE 4: Assignation taxonomique spécifique par marqueur ==="
echo ""

assign_taxonomy() {
    local marker_name=$1
    local rep_seqs_file=$2
    local classifier=$3
    local output_name=$4
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Assignation taxonomique: $marker_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [ ! -f "$DATABASE/$classifier" ]; then
        echo "⚠️  ERREUR: Classificateur manquant: $DATABASE/$classifier"
        echo "   Vous devez d'abord créer les bases de données marines"
        echo "   Lancez d'abord: qiime2_complete_v2.sh"
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
        local genus=$(grep -c ";g__" "export/taxonomy/${output_name}.tsv" 2>/dev/null || echo 0)
        
        echo "  ✓ ASVs assignés: $total"
        echo "  ✓ Niveau espèce: $species"
        echo "  ✓ Niveau genre: $genus"
        echo "  ✓ Fichier: export/taxonomy/${output_name}.tsv"
        
        echo ""
        echo "  Aperçu des résultats:"
        head -5 "export/taxonomy/${output_name}.tsv" | tail -3
    fi
    
    echo ""
}

assign_taxonomy "12S-MiFish" "03-dada2/rep_seqs_12S-MiFish.qza" "mifish_marine_classifier.qza" "taxonomy_12SMifish"
assign_taxonomy "12S-Mimammal" "03-dada2/rep_seqs_12S-Mimammal.qza" "mammal_marine_12s_classifier.qza" "taxonomy_12SMimammal"
assign_taxonomy "12S-Teleo" "03-dada2/rep_seqs_12S-Teleo.qza" "teleo_marine_12s_classifier.qza" "taxonomy_12STeleo"
assign_taxonomy "COI" "03-dada2/rep_seqs_COI.qza" "coi_marine_classifier.qza" "taxonomy_CO1"
assign_taxonomy "16S-Vert" "03-dada2/rep_seqs_16S-Vert.qza" "vert_marine_16s_classifier.qza" "taxonomy_16S"

#################################################################################
# RÉSUMÉ FINAL
#################################################################################

echo ""
echo "======================================================================="
echo "✓ PIPELINE UNESCO eDNA EXPEDITIONS - NEW CALEDONIA TERMINÉ"
echo "======================================================================="
echo ""
echo "Sites échantillonnés:"
echo "  - Poe (Récif barrière Sud-Ouest)"
echo "  - Kouaré (Récif intermédiaire Nord)"
echo "  - Grand Lagon Nord"
echo "  - Pouébo (Nord-Est)"
echo "  - Entrecasteaux (Récif Sud)"
echo ""
echo "Fichiers créés:"
echo "  - 01-cutadapt/: Lectures séparées par marqueur (20 échantillons × 5 marqueurs)"
echo "  - 02-qiime2/by_marker/: Fichiers QIIME2 par marqueur"
echo "  - 03-dada2/: Tables ASV et séquences représentatives par marqueur"
echo "  - 04-taxonomy/: Taxonomies assignées par marqueur"
echo "  - export/taxonomy/*.tsv: Fichiers TSV finaux"
echo ""
echo "Nombre total d'échantillons: 20 (19 + 1 control)"
echo ""
echo "AVANTAGES de cette approche:"
echo "  ✓ Séparation propre dès les lectures brutes single-end"
echo "  ✓ Pas de confusion entre marqueurs"
echo "  ✓ DADA2 optimisé pour chaque amplicon"
echo "  ✓ Assignation taxonomique cohérente et spécifique"
echo "  ✓ Méthode UNESCO pour récifs coralliens Nouvelle-Calédonie"
echo ""
echo "Prochaines étapes suggérées:"
echo "  1. Vérifier les stats DADA2: 03-dada2/stats_*.qzv"
echo "  2. Analyser les taxonomies: export/taxonomy/*.tsv"
echo "  3. Comparer les sites (diversité alpha/beta)"
echo "  4. Identifier les espèces endémiques de Nouvelle-Calédonie"
echo ""
