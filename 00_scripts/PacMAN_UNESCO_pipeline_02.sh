#!/usr/bin/env bash

# SOLUTION FINALE - Retour aux bases
# Clustering 97% SANS denoising + Assignation taxonomique multiple

WORKING_DIR=/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity/05_QIIME2
DATABASE=/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity/98_database_files
QIIME_ENV="qiime2-amplicon-2025.7"

cd $WORKING_DIR

echo "======================================================================="
echo "SOLUTION FINALE - Clustering 97% + Taxonomie multiple"
echo "======================================================================="
echo ""

if [ ! -f "02-qiime2/demux_all.qza" ]; then
    echo "❌ Fichier demux_all.qza manquant"
    echo "Relancez pipeline_complet_sra.sh ou utilisez vos données existantes"
    exit 1
fi

mkdir -p 03-clustering
mkdir -p 04-taxonomy
mkdir -p export/taxonomy
mkdir -p export/tables

#################################################################################
# ÉTAPE 1: MERGER LES PAIRES (paired-end join)
#################################################################################

echo "=== ÉTAPE 1: Fusion des paires R1/R2 ==="
echo ""

if [ ! -f "03-clustering/demux_joined.qza" ]; then
    echo "Fusion avec qiime vsearch merge-pairs..."
    
    conda run -n $QIIME_ENV qiime vsearch merge-pairs \
        --i-demultiplexed-seqs "02-qiime2/demux_all.qza" \
        --o-merged-sequences "03-clustering/demux_joined.qza" \
        --p-minmergelen 100 \
        --p-maxdiffs 10 \
        --verbose
    
    if [ $? -eq 0 ]; then
        echo "✓ Fusion réussie"
        
        # Stats
        conda run -n $QIIME_ENV qiime demux summarize \
            --i-data "03-clustering/demux_joined.qza" \
            --o-visualization "03-clustering/demux_joined.qzv"
        
        echo "✓ Visualisation: 03-clustering/demux_joined.qzv"
    else
        echo "❌ Fusion échouée"
        exit 1
    fi
else
    echo "✓ Fusion déjà effectuée"
fi

echo ""

#################################################################################
# ÉTAPE 2: FILTRAGE QUALITÉ BASIQUE
#################################################################################

echo "=== ÉTAPE 2: Filtrage qualité basique ==="
echo ""

if [ ! -f "03-clustering/demux_filtered.qza" ]; then
    echo "Filtrage avec quality-filter (très permissif)..."
    
    conda run -n $QIIME_ENV qiime quality-filter q-score \
        --i-demux "03-clustering/demux_joined.qza" \
        --p-min-quality 4 \
        --p-quality-window 10 \
        --p-min-length-fraction 0.5 \
        --p-max-ambiguous 5 \
        --o-filtered-sequences "03-clustering/demux_filtered.qza" \
        --o-filter-stats "03-clustering/filter_stats.qza"
    
    if [ $? -eq 0 ]; then
        echo "✓ Filtrage réussi"
        
        # Stats
        conda run -n $QIIME_ENV qiime metadata tabulate \
            --m-input-file "03-clustering/filter_stats.qza" \
            --o-visualization "03-clustering/filter_stats.qzv"
    else
        echo "❌ Filtrage échoué"
        exit 1
    fi
else
    echo "✓ Filtrage déjà effectué"
fi

echo ""

#################################################################################
# ÉTAPE 3: DEREPLICATE
#################################################################################

echo "=== ÉTAPE 3: Dereplication ==="
echo ""

if [ ! -f "03-clustering/table_derep.qza" ]; then
    echo "Dereplication avec vsearch..."
    
    conda run -n $QIIME_ENV qiime vsearch dereplicate-sequences \
        --i-sequences "03-clustering/demux_filtered.qza" \
        --o-dereplicated-table "03-clustering/table_derep.qza" \
        --o-dereplicated-sequences "03-clustering/rep_seqs_derep.qza"
    
    if [ $? -eq 0 ]; then
        echo "✓ Dereplication réussie"
        
        # Stats
        conda run -n $QIIME_ENV qiime feature-table summarize \
            --i-table "03-clustering/table_derep.qza" \
            --o-visualization "03-clustering/table_derep.qzv"
        
        conda run -n $QIIME_ENV qiime feature-table tabulate-seqs \
            --i-data "03-clustering/rep_seqs_derep.qza" \
            --o-visualization "03-clustering/rep_seqs_derep.qzv"
    else
        echo "❌ Dereplication échouée"
        exit 1
    fi
else
    echo "✓ Dereplication déjà effectuée"
fi

echo ""

#################################################################################
# ÉTAPE 4: CLUSTERING 97%
#################################################################################

echo "=== ÉTAPE 4: Clustering 97% (OTU) ==="
echo ""

if [ ! -f "03-clustering/table_97.qza" ]; then
    echo "Clustering de novo à 97% avec vsearch..."
    
    conda run -n $QIIME_ENV qiime vsearch cluster-features-de-novo \
        --i-sequences "03-clustering/rep_seqs_derep.qza" \
        --i-table "03-clustering/table_derep.qza" \
        --p-perc-identity 0.97 \
        --p-threads 8 \
        --o-clustered-table "03-clustering/table_97.qza" \
        --o-clustered-sequences "03-clustering/rep_seqs_97.qza"
    
    if [ $? -eq 0 ]; then
        echo "✓ Clustering réussi"
        
        # Stats
        conda run -n $QIIME_ENV qiime feature-table summarize \
            --i-table "03-clustering/table_97.qza" \
            --o-visualization "03-clustering/table_97.qzv"
        
        conda run -n $QIIME_ENV qiime feature-table tabulate-seqs \
            --i-data "03-clustering/rep_seqs_97.qza" \
            --o-visualization "03-clustering/rep_seqs_97.qzv"
        
        echo "✓ Visualisations créées"
    else
        echo "❌ Clustering échoué"
        exit 1
    fi
else
    echo "✓ Clustering déjà effectué"
fi

echo ""

#################################################################################
# ÉTAPE 5: ASSIGNATIONS TAXONOMIQUES MULTIPLES
#################################################################################

echo "======================================================================="
echo "ÉTAPE 5: Assignations taxonomiques (5 classificateurs)"
echo "======================================================================="
echo ""

REP_SEQS="03-clustering/rep_seqs_97.qza"

assign_taxonomy() {
    local name=$1
    local classifier=$2
    local description=$3
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Assignation: $name"
    echo "Marqueur: $description"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [ ! -f "$DATABASE/$classifier" ]; then
        echo "  ⚠️  Classificateur manquant: $classifier"
        echo "  Créez les bases avec: bash create_marine_databases.sh"
        echo ""
        return 1
    fi
    
    # Assignation
    if [ ! -f "04-taxonomy/taxonomy_${name}.qza" ]; then
        echo "  Lancement classify-sklearn..."
        
        conda run -n $QIIME_ENV qiime feature-classifier classify-sklearn \
            --i-classifier "$DATABASE/$classifier" \
            --i-reads "$REP_SEQS" \
            --o-classification "04-taxonomy/taxonomy_${name}.qza" \
            --p-confidence 0.7 \
            --p-n-jobs 8 \
            --verbose
        
        if [ $? -ne 0 ]; then
            echo "  ❌ Assignation échouée"
            return 1
        fi
    fi
    
    # Export TSV
    conda run -n $QIIME_ENV qiime tools export \
        --input-path "04-taxonomy/taxonomy_${name}.qza" \
        --output-path "export/taxonomy/temp_${name}/"
    
    mv "export/taxonomy/temp_${name}/taxonomy.tsv" "export/taxonomy/taxonomy_${name}.tsv"
    rm -rf "export/taxonomy/temp_${name}/"
    
    # Visualisation
    conda run -n $QIIME_ENV qiime metadata tabulate \
        --m-input-file "04-taxonomy/taxonomy_${name}.qza" \
        --o-visualization "04-taxonomy/taxonomy_${name}.qzv"
    
    # Barplot
    conda run -n $QIIME_ENV qiime taxa barplot \
        --i-table "03-clustering/table_97.qza" \
        --i-taxonomy "04-taxonomy/taxonomy_${name}.qza" \
        --o-visualization "04-taxonomy/barplot_${name}.qzv" 2>/dev/null || true
    
    # Statistiques
    if [ -f "export/taxonomy/taxonomy_${name}.tsv" ]; then
        local total=$(($(wc -l < "export/taxonomy/taxonomy_${name}.tsv") - 2))
        local species=$(grep -c ";s__[^;[:space:]]*" "export/taxonomy/taxonomy_${name}.tsv" 2>/dev/null || echo 0)
        local genus=$(grep -c ";g__[^;[:space:]]*" "export/taxonomy/taxonomy_${name}.tsv" 2>/dev/null || echo 0)
        
        echo ""
        echo "  📊 RÉSULTATS:"
        echo "     Total OTUs: $total"
        echo "     Niveau espèce: $species ($((species * 100 / total))%)"
        echo "     Niveau genre: $genus ($((genus * 100 / total))%)"
        echo ""
        echo "  📁 Fichiers:"
        echo "     - export/taxonomy/taxonomy_${name}.tsv"
        echo "     - 04-taxonomy/taxonomy_${name}.qzv"
        echo ""
        echo "  Aperçu (top 5 assignations):"
        head -7 "export/taxonomy/taxonomy_${name}.tsv" | tail -5 | \
            awk -F'\t' '{printf "     %s: %s\n", $1, $2}' | head -5
    fi
    
    echo ""
}

# Lancer les 5 assignations
assign_taxonomy "12SMifish" "mifish_marine_classifier.qza" "12S MiFish (Poissons)"
assign_taxonomy "12SMimammal" "mammal_marine_12s_classifier.qza" "12S Mimammal (Mammifères marins)"
assign_taxonomy "12STeleo" "teleo_marine_12s_classifier.qza" "12S Teleo (Téléostéens)"
assign_taxonomy "CO1" "coi_marine_classifier.qza" "COI Leray-Geller (Faune diverse)"
assign_taxonomy "16S" "vert_marine_16s_classifier.qza" "16S Vert-Vences (Vertébrés)"

#################################################################################
# RÉSUMÉ ET EXPORTS
#################################################################################

echo ""
echo "======================================================================="
echo "✓✓✓ PIPELINE TERMINÉ AVEC SUCCÈS ✓✓✓"
echo "======================================================================="
echo ""
echo "FICHIERS CRÉÉS:"
echo ""
echo "1. TABLE OTU (97%):"
echo "   → 03-clustering/table_97.qza"
echo "   → 03-clustering/table_97.qzv (stats)"
echo ""
echo "2. SÉQUENCES REPRÉSENTATIVES:"
echo "   → 03-clustering/rep_seqs_97.qza"
echo "   → 03-clustering/rep_seqs_97.qzv"
echo ""
echo "3. TAXONOMIES (5 classificateurs):"
ls -1 export/taxonomy/taxonomy_*.tsv 2>/dev/null | while read f; do
    count=$(($(wc -l < "$f") - 2))
    basename_f=$(basename "$f" .tsv)
    echo "   → $f ($count OTUs)"
done
echo ""
echo "4. VISUALISATIONS:"
echo "   → Ouvrir les .qzv sur https://view.qiime2.org"
find 03-clustering 04-taxonomy -name "*.qzv" -type f 2>/dev/null | head -15 | while read f; do
    echo "   → $f"
done
echo ""
echo "══════════════════════════════════════════════════════════════════════"
echo "ANALYSES SUIVANTES"
echo "══════════════════════════════════════════════════════════════════════"
echo ""
echo "1. COMPARER LES 5 ASSIGNATIONS:"
echo "   cd export/taxonomy"
echo "   # Pour chaque OTU, identifier quel classificateur donne la meilleure assignation"
echo ""
echo "2. FILTRER PAR MARQUEUR:"
echo "   # Selon la taxonomie obtenue, identifier quels OTUs correspondent à quels marqueurs"
echo "   # Ex: OTUs assignés comme Actinopterygii → 12S MiFish/Teleo"
echo "   #     OTUs assignés comme Mammalia → 12S Mimammal"
echo "   #     OTUs assignés comme autres Metazoa → COI"
echo ""
echo "3. ANALYSES ÉCOLOGIQUES:"
echo "   # Diversité alpha par site"
echo "   # Diversité beta (PCoA, NMDS)"
echo "   # Espèces indicatrices par site"
echo ""
echo "4. EXPORT POUR R/PHYLOSEQ:"
echo "   qiime tools export --input-path 03-clustering/table_97.qza \\"
echo "     --output-path export/tables/"
echo "   biom convert -i export/tables/feature-table.biom \\"
echo "     -o export/tables/otu_table.tsv --to-tsv"
echo ""
echo "Bonne analyse! 🐠🪸🇳🇨"
echo ""
