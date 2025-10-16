#!/usr/bin/env bash

# DADA2 Multi-stratégies - Nouvelle-Calédonie
# Essaie plusieurs paramètres jusqu'à ce que ça fonctionne

WORKING_DIR=/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity/05_QIIME2
DATABASE=/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity/98_database_files
QIIME_ENV="qiime2-amplicon-2025.7"

cd $WORKING_DIR

echo "======================================================================="
echo "DADA2 MULTI-STRATÉGIES"
echo "======================================================================="
echo ""

if [ ! -f "02-qiime2/demux_all.qza" ]; then
    echo "❌ Erreur: Lancez d'abord pipeline_complet_sra.sh"
    exit 1
fi

mkdir -p 03-dada2

#################################################################################
# STRATÉGIE 1: Troncature courte (150/150) + max-ee relaxé
#################################################################################

echo "=== STRATÉGIE 1: Troncature courte (150/150, max-ee=5) ==="
echo ""

if [ ! -f "03-dada2/table_s1.qza" ]; then
    conda run -n $QIIME_ENV qiime dada2 denoise-paired \
        --i-demultiplexed-seqs "02-qiime2/demux_all.qza" \
        --p-trim-left-f 0 \
        --p-trim-left-r 0 \
        --p-trunc-len-f 150 \
        --p-trunc-len-r 150 \
        --p-max-ee-f 5.0 \
        --p-max-ee-r 5.0 \
        --p-n-threads 8 \
        --o-table "03-dada2/table_s1.qza" \
        --o-representative-sequences "03-dada2/rep_seqs_s1.qza" \
        --o-denoising-stats "03-dada2/stats_s1.qza" \
        --verbose
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "✓✓✓ SUCCÈS avec stratégie 1 ✓✓✓"
        STRATEGY="s1"
    else
        echo ""
        echo "❌ Stratégie 1 échouée"
    fi
else
    echo "✓ Stratégie 1 déjà effectuée"
    STRATEGY="s1"
fi

#################################################################################
# STRATÉGIE 2: Pas de troncature + très permissif
#################################################################################

if [ -z "$STRATEGY" ]; then
    echo ""
    echo "=== STRATÉGIE 2: Pas de troncature (0/0, max-ee=10) ==="
    echo ""
    
    if [ ! -f "03-dada2/table_s2.qza" ]; then
        conda run -n $QIIME_ENV qiime dada2 denoise-paired \
            --i-demultiplexed-seqs "02-qiime2/demux_all.qza" \
            --p-trim-left-f 0 \
            --p-trim-left-r 0 \
            --p-trunc-len-f 0 \
            --p-trunc-len-r 0 \
            --p-max-ee-f 10.0 \
            --p-max-ee-r 10.0 \
            --p-n-threads 8 \
            --o-table "03-dada2/table_s2.qza" \
            --o-representative-sequences "03-dada2/rep_seqs_s2.qza" \
            --o-denoising-stats "03-dada2/stats_s2.qza" \
            --verbose
        
        if [ $? -eq 0 ]; then
            echo ""
            echo "✓✓✓ SUCCÈS avec stratégie 2 ✓✓✓"
            STRATEGY="s2"
        else
            echo ""
            echo "❌ Stratégie 2 échouée"
        fi
    else
        echo "✓ Stratégie 2 déjà effectuée"
        STRATEGY="s2"
    fi
fi

#################################################################################
# STRATÉGIE 3: DEBLUR (alternative à DADA2)
#################################################################################

if [ -z "$STRATEGY" ]; then
    echo ""
    echo "=== STRATÉGIE 3: DEBLUR (alternative à DADA2) ==="
    echo ""
    echo "DADA2 ne fonctionne pas. Essayons Deblur..."
    echo ""
    
    # Joindre les paires d'abord
    if [ ! -f "02-qiime2/demux_joined.qza" ]; then
        echo "Fusion des paires R1/R2..."
        conda run -n $QIIME_ENV qiime vsearch join-pairs \
            --i-demultiplexed-seqs "02-qiime2/demux_all.qza" \
            --o-joined-sequences "02-qiime2/demux_joined.qza"
    fi
    
    # Quality filter
    if [ ! -f "02-qiime2/demux_filtered.qza" ]; then
        echo "Filtrage qualité..."
        conda run -n $QIIME_ENV qiime quality-filter q-score \
            --i-demux "02-qiime2/demux_joined.qza" \
            --o-filtered-sequences "02-qiime2/demux_filtered.qza" \
            --o-filter-stats "02-qiime2/filter_stats.qza"
    fi
    
    # Deblur
    if [ ! -f "03-dada2/table_s3_deblur.qza" ]; then
        echo "Lancement Deblur..."
        conda run -n $QIIME_ENV qiime deblur denoise-16S \
            --i-demultiplexed-seqs "02-qiime2/demux_filtered.qza" \
            --p-trim-length 200 \
            --p-sample-stats \
            --o-table "03-dada2/table_s3_deblur.qza" \
            --o-representative-sequences "03-dada2/rep_seqs_s3_deblur.qza" \
            --o-stats "03-dada2/stats_s3_deblur.qza"
        
        if [ $? -eq 0 ]; then
            echo ""
            echo "✓✓✓ SUCCÈS avec Deblur ✓✓✓"
            STRATEGY="s3_deblur"
        else
            echo ""
            echo "❌ Deblur échoué"
        fi
    else
        echo "✓ Deblur déjà effectué"
        STRATEGY="s3_deblur"
    fi
fi

#################################################################################
# STRATÉGIE 4: VSEARCH clustering (dernier recours)
#################################################################################

if [ -z "$STRATEGY" ]; then
    echo ""
    echo "=== STRATÉGIE 4: VSEARCH clustering (dernier recours) ==="
    echo ""
    echo "Ni DADA2 ni Deblur ne fonctionnent."
    echo "Utilisons vsearch qui fait un simple clustering 97%..."
    echo ""
    
    # Utiliser les séquences jointes
    if [ ! -f "02-qiime2/demux_joined.qza" ]; then
        conda run -n $QIIME_ENV qiime vsearch join-pairs \
            --i-demultiplexed-seqs "02-qiime2/demux_all.qza" \
            --o-joined-sequences "02-qiime2/demux_joined.qza"
    fi
    
    # Dereplicate
    if [ ! -f "03-dada2/table_s4_vsearch.qza" ]; then
        conda run -n $QIIME_ENV qiime vsearch dereplicate-sequences \
            --i-sequences "02-qiime2/demux_joined.qza" \
            --o-dereplicated-table "03-dada2/table_derep.qza" \
            --o-dereplicated-sequences "03-dada2/rep_seqs_derep.qza"
        
        # Cluster à 97%
        conda run -n $QIIME_ENV qiime vsearch cluster-features-de-novo \
            --i-sequences "03-dada2/rep_seqs_derep.qza" \
            --i-table "03-dada2/table_derep.qza" \
            --p-perc-identity 0.97 \
            --o-clustered-table "03-dada2/table_s4_vsearch.qza" \
            --o-clustered-sequences "03-dada2/rep_seqs_s4_vsearch.qza"
        
        if [ $? -eq 0 ]; then
            echo ""
            echo "✓✓✓ SUCCÈS avec vsearch ✓✓✓"
            STRATEGY="s4_vsearch"
        else
            echo ""
            echo "❌ vsearch échoué"
        fi
    else
        echo "✓ vsearch déjà effectué"
        STRATEGY="s4_vsearch"
    fi
fi

#################################################################################
# VÉRIFICATION ET VISUALISATIONS
#################################################################################

if [ -z "$STRATEGY" ]; then
    echo ""
    echo "======================================================================="
    echo "❌❌❌ TOUTES LES STRATÉGIES ONT ÉCHOUÉ ❌❌❌"
    echo "======================================================================="
    echo ""
    echo "Vos données ont un problème fondamental:"
    echo "  - Qualité Phred extrêmement basse"
    echo "  - Ou presque aucune lecture après filtrage"
    echo ""
    echo "DIAGNOSTIC RECOMMANDÉ:"
    echo "  1. Vérifier les scores de qualité:"
    echo "     head -8 /nvme/bio/.../01_raw_data/SRR29659654.fastq"
    echo ""
    echo "  2. Si tous les scores sont '?' :"
    echo "     → Problème de téléchargement SRA"
    echo "     → Essayez: prefetch SRR29659654 puis fastq-dump"
    echo ""
    echo "  3. Vérifier sur NCBI SRA si les données ont une bonne qualité"
    echo ""
    exit 1
fi

echo ""
echo "======================================================================="
echo "✓✓✓ SUCCÈS AVEC LA STRATÉGIE: $STRATEGY ✓✓✓"
echo "======================================================================="
echo ""

# Créer les visualisations
echo "Création des visualisations..."

TABLE_FILE="03-dada2/table_${STRATEGY}.qza"
REPSEQS_FILE="03-dada2/rep_seqs_${STRATEGY}.qza"
STATS_FILE="03-dada2/stats_${STRATEGY}.qza"

# Table summary
conda run -n $QIIME_ENV qiime feature-table summarize \
    --i-table "$TABLE_FILE" \
    --o-visualization "03-dada2/table_${STRATEGY}.qzv"

# Rep seqs
conda run -n $QIIME_ENV qiime feature-table tabulate-seqs \
    --i-data "$REPSEQS_FILE" \
    --o-visualization "03-dada2/rep_seqs_${STRATEGY}.qzv"

# Stats (si disponible)
if [ -f "$STATS_FILE" ]; then
    conda run -n $QIIME_ENV qiime metadata tabulate \
        --m-input-file "$STATS_FILE" \
        --o-visualization "03-dada2/stats_${STRATEGY}.qzv" 2>/dev/null || true
fi

echo "✓ Visualisations créées"
echo ""

#################################################################################
# ASSIGNATIONS TAXONOMIQUES
#################################################################################

echo "=== Assignations taxonomiques ==="
echo ""

mkdir -p 04-taxonomy
mkdir -p export/taxonomy

assign_taxonomy() {
    local name=$1
    local classifier=$2
    
    echo "--- $name ---"
    
    if [ ! -f "$DATABASE/$classifier" ]; then
        echo "  ⚠️  Classificateur manquant: $classifier"
        return 1
    fi
    
    if [ ! -f "04-taxonomy/taxonomy_${name}_${STRATEGY}.qza" ]; then
        conda run -n $QIIME_ENV qiime feature-classifier classify-sklearn \
            --i-classifier "$DATABASE/$classifier" \
            --i-reads "$REPSEQS_FILE" \
            --o-classification "04-taxonomy/taxonomy_${name}_${STRATEGY}.qza" \
            --p-confidence 0.7 \
            --p-n-jobs 8
    fi
    
    # Export
    conda run -n $QIIME_ENV qiime tools export \
        --input-path "04-taxonomy/taxonomy_${name}_${STRATEGY}.qza" \
        --output-path "export/taxonomy/temp_${name}/"
    
    mv "export/taxonomy/temp_${name}/taxonomy.tsv" "export/taxonomy/taxonomy_${name}_${STRATEGY}.tsv"
    rm -rf "export/taxonomy/temp_${name}/"
    
    local total=$(($(wc -l < "export/taxonomy/taxonomy_${name}_${STRATEGY}.tsv") - 2))
    echo "  ✓ $total ASVs"
    echo ""
}

echo "Utilisation des séquences: $REPSEQS_FILE"
echo ""

assign_taxonomy "12SMifish" "mifish_marine_classifier.qza"
assign_taxonomy "12SMimammal" "mammal_marine_12s_classifier.qza"
assign_taxonomy "12STeleo" "teleo_marine_12s_classifier.qza"
assign_taxonomy "CO1" "coi_marine_classifier.qza"
assign_taxonomy "16S" "vert_marine_16s_classifier.qza"

echo ""
echo "======================================================================="
echo "✓✓✓ PIPELINE TERMINÉ AVEC SUCCÈS ✓✓✓"
echo "======================================================================="
echo ""
echo "Stratégie utilisée: $STRATEGY"
echo ""
echo "Fichiers créés:"
echo "  - 03-dada2/table_${STRATEGY}.qza"
echo "  - 03-dada2/rep_seqs_${STRATEGY}.qza"
echo "  - 03-dada2/*_${STRATEGY}.qzv (visualisations)"
echo "  - export/taxonomy/taxonomy_*_${STRATEGY}.tsv"
echo ""
echo "Ouvrez les .qzv sur https://view.qiime2.org"
echo ""
