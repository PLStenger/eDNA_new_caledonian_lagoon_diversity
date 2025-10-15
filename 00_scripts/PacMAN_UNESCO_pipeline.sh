#!/usr/bin/env bash

# Script FINAL - Nouvelle-Calédonie
# Format: Paired-end INTERLEAVED (les R1 et R2 sont dans le même fichier)

WORKING_DIRECTORY=/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity/05_QIIME2
RAW_DATA=/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity/01_raw_data
DATABASE=/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity/98_database_files
QIIME_ENV="qiime2-amplicon-2025.7"

cd $WORKING_DIRECTORY

echo "======================================================================="
echo "NOUVELLE-CALÉDONIE - Format PAIRED-END INTERLEAVED"
echo "======================================================================="
echo ""

mkdir -p 00-deinterleave
mkdir -p 01-cutadapt
mkdir -p 02-qiime2/by_marker
mkdir -p 03-dada2
mkdir -p 04-taxonomy
mkdir -p export/taxonomy

#################################################################################
# MÉTADONNÉES
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
# ÉTAPE 1: DEINTERLEAVE (séparer R1 et R2)
#################################################################################

echo "=== ÉTAPE 1: Séparation des paires R1/R2 (deinterleave) ==="
echo ""

deinterleave_fastq() {
    local sample_name=$1
    local srr_id=$2
    
    echo "Deinterleaving: $sample_name ($srr_id)"
    
    local input="${RAW_DATA}/${srr_id}.fastq"
    local output_r1="00-deinterleave/${sample_name}_R1.fastq.gz"
    local output_r2="00-deinterleave/${sample_name}_R2.fastq.gz"
    
    if [ -f "$output_r1" ] && [ -f "$output_r2" ]; then
        echo "  ✓ Déjà fait"
        return 0
    fi
    
    # Utiliser reformat.sh de BBTools si disponible, sinon awk
    if command -v reformat.sh &> /dev/null; then
        reformat.sh in="$input" out1="$output_r1" out2="$output_r2" 2>/dev/null
    else
        # Alternative avec awk
        awk 'NR%8<5{print > "temp_R1.fq"} NR%8>=5{print > "temp_R2.fq"}' "$input"
        gzip -c temp_R1.fq > "$output_r1"
        gzip -c temp_R2.fq > "$output_r2"
        rm temp_R1.fq temp_R2.fq
    fi
    
    echo "  ✓ R1: $output_r1"
    echo "  ✓ R2: $output_r2"
}

# Traiter tous les échantillons
while IFS=$'\t' read -r sample_name srr_id; do
    if [ "$sample_name" != "sample-id" ]; then
        deinterleave_fastq "$sample_name" "$srr_id"
    fi
done < sample_mapping.tsv

echo ""
echo "✓ Deinterleaving terminé"
echo ""

#################################################################################
# ÉTAPE 2: IMPORT DIRECT DANS QIIME2 (SANS CUTADAPT)
#################################################################################

echo "=== ÉTAPE 2: Import QIIME2 (toutes les séquences ensemble) ==="
echo ""
echo "IMPORTANT: On importe TOUT sans séparer par marqueur"
echo "car les primers sont déjà dans les séquences"
echo ""

# Créer le manifest pour TOUTES les séquences
manifest_file="02-qiime2/manifest_all_samples.tsv"

printf "sample-id\tforward-absolute-filepath\treverse-absolute-filepath\n" > "$manifest_file"

while IFS=$'\t' read -r sample_name srr_id; do
    if [ "$sample_name" != "sample-id" ]; then
        r1_path=$(realpath "00-deinterleave/${sample_name}_R1.fastq.gz")
        r2_path=$(realpath "00-deinterleave/${sample_name}_R2.fastq.gz")
        
        if [ -f "$r1_path" ] && [ -f "$r2_path" ]; then
            printf "%s\t%s\t%s\n" "$sample_name" "$r1_path" "$r2_path" >> "$manifest_file"
        fi
    fi
done < sample_mapping.tsv

echo "✓ Manifest créé: $manifest_file"

# Import QIIME2
if [ ! -f "02-qiime2/demux_all.qza" ]; then
    conda run -n $QIIME_ENV qiime tools import \
        --type 'SampleData[PairedEndSequencesWithQuality]' \
        --input-path "$manifest_file" \
        --output-path "02-qiime2/demux_all.qza" \
        --input-format PairedEndFastqManifestPhred33V2
    
    echo "✓ Import réussi: demux_all.qza"
else
    echo "✓ Import existe déjà"
fi

# Visualisation
if [ ! -f "02-qiime2/demux_all_summary.qzv" ]; then
    conda run -n $QIIME_ENV qiime demux summarize \
        --i-data "02-qiime2/demux_all.qza" \
        --o-visualization "02-qiime2/demux_all_summary.qzv"
    
    echo "✓ Visualisation créée: demux_all_summary.qzv"
    echo "  📊 Ouvrir sur: https://view.qiime2.org"
fi

echo ""

#################################################################################
# ÉTAPE 3: DADA2 SUR TOUTES LES SÉQUENCES
#################################################################################

echo "=== ÉTAPE 3: DADA2 sur toutes les séquences (paired-end) ==="
echo ""
echo "On traite TOUTES les séquences ensemble avec DADA2 paired-end"
echo ""

if [ ! -f "03-dada2/table_all.qza" ]; then
    echo "Lancement DADA2..."
    
    conda run -n $QIIME_ENV qiime dada2 denoise-paired \
        --i-demultiplexed-seqs "02-qiime2/demux_all.qza" \
        --p-trim-left-f 0 \
        --p-trim-left-r 0 \
        --p-trunc-len-f 240 \
        --p-trunc-len-r 240 \
        --p-max-ee-f 3 \
        --p-max-ee-r 3 \
        --p-n-threads 6 \
        --o-table "03-dada2/table_all.qza" \
        --o-representative-sequences "03-dada2/rep_seqs_all.qza" \
        --o-denoising-stats "03-dada2/stats_all.qza" \
        --verbose
    
    if [ $? -eq 0 ]; then
        echo "✓ DADA2 réussi"
        
        # Visualisations
        conda run -n $QIIME_ENV qiime metadata tabulate \
            --m-input-file "03-dada2/stats_all.qza" \
            --o-visualization "03-dada2/stats_all.qzv"
        
        conda run -n $QIIME_ENV qiime feature-table tabulate-seqs \
            --i-data "03-dada2/rep_seqs_all.qza" \
            --o-visualization "03-dada2/rep_seqs_all.qzv"
        
        conda run -n $QIIME_ENV qiime feature-table summarize \
            --i-table "03-dada2/table_all.qza" \
            --o-visualization "03-dada2/table_all.qzv"
    else
        echo "❌ DADA2 a échoué"
        exit 1
    fi
else
    echo "✓ DADA2 déjà effectué"
fi

echo ""

#################################################################################
# ÉTAPE 4: ASSIGNATION TAXONOMIQUE MULTI-BASES
#################################################################################

echo "=== ÉTAPE 4: Assignation taxonomique (toutes bases combinées) ==="
echo ""
echo "On va assigner avec TOUTES les bases de données"
echo "et garder la meilleure assignation"
echo ""

assign_with_all_classifiers() {
    local rep_seqs="03-dada2/rep_seqs_all.qza"
    
    # Tableau des classificateurs
    declare -A classifiers=(
        ["12SMifish"]="mifish_marine_classifier.qza"
        ["12SMimammal"]="mammal_marine_12s_classifier.qza"
        ["12STeleo"]="teleo_marine_12s_classifier.qza"
        ["CO1"]="coi_marine_classifier.qza"
        ["16S"]="vert_marine_16s_classifier.qza"
    )
    
    for name in "${!classifiers[@]}"; do
        classifier="${classifiers[$name]}"
        
        echo "--- Assignation avec: $name ---"
        
        if [ ! -f "$DATABASE/$classifier" ]; then
            echo "  ⚠️  Classificateur manquant: $classifier"
            continue
        fi
        
        if [ ! -f "04-taxonomy/taxonomy_${name}.qza" ]; then
            conda run -n $QIIME_ENV qiime feature-classifier classify-sklearn \
                --i-classifier "$DATABASE/$classifier" \
                --i-reads "$rep_seqs" \
                --o-classification "04-taxonomy/taxonomy_${name}.qza" \
                --p-confidence 0.7 \
                --p-n-jobs 4
        fi
        
        # Export TSV
        conda run -n $QIIME_ENV qiime tools export \
            --input-path "04-taxonomy/taxonomy_${name}.qza" \
            --output-path "export/taxonomy/taxonomy_${name}_temp/"
        
        mv "export/taxonomy/taxonomy_${name}_temp/taxonomy.tsv" "export/taxonomy/taxonomy_${name}.tsv"
        rm -rf "export/taxonomy/taxonomy_${name}_temp/"
        
        echo "  ✓ Fichier: export/taxonomy/taxonomy_${name}.tsv"
        
        local total=$(($(wc -l < "export/taxonomy/taxonomy_${name}.tsv") - 2))
        echo "  📊 ASVs assignés: $total"
    done
}

assign_with_all_classifiers

echo ""
echo "======================================================================="
echo "✓ PIPELINE TERMINÉ"
echo "======================================================================="
echo ""
echo "Fichiers créés:"
echo "  - 02-qiime2/demux_all_summary.qzv (statistiques des lectures)"
echo "  - 03-dada2/stats_all.qzv (résultats DADA2)"
echo "  - 03-dada2/table_all.qzv (table des ASVs)"
echo "  - 03-dada2/rep_seqs_all.qzv (séquences représentatives)"
echo "  - export/taxonomy/*.tsv (taxonomies par classificateur)"
echo ""
echo "IMPORTANT:"
echo "  Vous avez maintenant 5 fichiers de taxonomie, un par classificateur."
echo "  Les mêmes ASVs sont assignés par chaque classificateur."
echo "  Vous devrez maintenant:"
echo "    1. Filtrer les ASVs par marqueur (en cherchant les primers dans les séquences)"
echo "    2. Ou utiliser l'assignation la plus spécifique/confiante pour chaque ASV"
echo ""
echo "Pour filtrer par primers ensuite, utilisez:"
echo "  qiime feature-classifier extract-reads avec les primers"
echo ""
