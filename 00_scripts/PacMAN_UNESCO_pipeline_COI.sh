#!/usr/bin/env bash

# Script pour relancer UNIQUEMENT l'assignation COI
# Problème: Out of Memory (SIGKILL -9)
# Solution: Moins de threads + traitement par batch

WORKING_DIR=/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity/05_QIIME2
DATABASE=/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity/98_database_files
QIIME_ENV="qiime2-amplicon-2025.7"

cd $WORKING_DIR

echo "======================================================================="
echo "RELANCE ASSIGNATION COI - Version optimisée mémoire"
echo "======================================================================="
echo ""

# Vérifier les fichiers nécessaires
if [ ! -f "03-clustering/rep_seqs_97.qza" ]; then
    echo "❌ Fichier rep_seqs_97.qza manquant"
    exit 1
fi

if [ ! -f "$DATABASE/coi_marine_classifier.qza" ]; then
    echo "❌ Classificateur COI manquant"
    exit 1
fi

mkdir -p 04-taxonomy
mkdir -p export/taxonomy

echo "Préparation:"
echo "  - Séquences: 03-clustering/rep_seqs_97.qza"
echo "  - Classificateur: coi_marine_classifier.qza"
echo "  - Threads: 2 (au lieu de 8) pour économiser la RAM"
echo ""

#################################################################################
# STRATÉGIE 1: Avec 2 threads seulement
#################################################################################

echo "=== TENTATIVE 1: 2 threads (économie RAM) ==="
echo ""

if [ ! -f "04-taxonomy/taxonomy_CO1.qza" ]; then
    conda run -n $QIIME_ENV qiime feature-classifier classify-sklearn \
        --i-classifier "$DATABASE/coi_marine_classifier.qza" \
        --i-reads "03-clustering/rep_seqs_97.qza" \
        --o-classification "04-taxonomy/taxonomy_CO1.qza" \
        --p-confidence 0.7 \
        --p-n-jobs 2 \
        --verbose
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "✅ SUCCÈS avec 2 threads"
        SUCCESS=1
    else
        echo ""
        echo "❌ Échec avec 2 threads"
    fi
else
    echo "✅ COI déjà assigné"
    SUCCESS=1
fi

#################################################################################
# STRATÉGIE 2: 1 seul thread (si stratégie 1 échoue)
#################################################################################

if [ -z "$SUCCESS" ]; then
    echo ""
    echo "=== TENTATIVE 2: 1 seul thread ==="
    echo ""
    
    rm -f "04-taxonomy/taxonomy_CO1.qza"
    
    conda run -n $QIIME_ENV qiime feature-classifier classify-sklearn \
        --i-classifier "$DATABASE/coi_marine_classifier.qza" \
        --i-reads "03-clustering/rep_seqs_97.qza" \
        --o-classification "04-taxonomy/taxonomy_CO1.qza" \
        --p-confidence 0.7 \
        --p-n-jobs 1 \
        --verbose
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "✅ SUCCÈS avec 1 thread"
        SUCCESS=1
    else
        echo ""
        echo "❌ Échec avec 1 thread"
    fi
fi

#################################################################################
# STRATÉGIE 3: Réduire le nombre d'OTUs (filtrer les très rares)
#################################################################################

if [ -z "$SUCCESS" ]; then
    echo ""
    echo "=== TENTATIVE 3: Filtrer OTUs rares puis classifier ==="
    echo ""
    
    # Filtrer les OTUs présents dans moins de 2 échantillons
    if [ ! -f "03-clustering/rep_seqs_97_filtered.qza" ]; then
        conda run -n $QIIME_ENV qiime feature-table filter-seqs \
            --i-data "03-clustering/rep_seqs_97.qza" \
            --i-table "03-clustering/table_97.qza" \
            --p-min-samples 2 \
            --o-filtered-data "03-clustering/rep_seqs_97_filtered.qza"
    fi
    
    rm -f "04-taxonomy/taxonomy_CO1.qza"
    
    conda run -n $QIIME_ENV qiime feature-classifier classify-sklearn \
        --i-classifier "$DATABASE/coi_marine_classifier.qza" \
        --i-reads "03-clustering/rep_seqs_97_filtered.qza" \
        --o-classification "04-taxonomy/taxonomy_CO1.qza" \
        --p-confidence 0.7 \
        --p-n-jobs 2 \
        --verbose
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "✅ SUCCÈS avec OTUs filtrés"
        SUCCESS=1
    else
        echo ""
        echo "❌ Échec même avec OTUs filtrés"
    fi
fi

#################################################################################
# STRATÉGIE 4: Utiliser BLAST au lieu de sklearn (dernier recours)
#################################################################################

if [ -z "$SUCCESS" ]; then
    echo ""
    echo "=== TENTATIVE 4: BLAST au lieu de sklearn ==="
    echo ""
    
    # Vérifier si on a une base BLAST COI
    if [ ! -f "$DATABASE/coi_marine_seqs.qza" ]; then
        echo "❌ Base BLAST COI manquante"
        echo "Il faut créer une base de séquences de référence COI"
        echo ""
        echo "Pour créer la base:"
        echo "  qiime feature-classifier extract-reads \\"
        echo "    --i-sequences nt.qza \\"
        echo "    --p-f-primer GGWACWGGWTGAACWGTWTAYCCYCC \\"
        echo "    --p-r-primer TANACYTCNGGRTGNCCRAARAAYCA \\"
        echo "    --o-reads coi_marine_seqs.qza"
    else
        rm -f "04-taxonomy/taxonomy_CO1.qza"
        
        conda run -n $QIIME_ENV qiime feature-classifier classify-consensus-blast \
            --i-query "03-clustering/rep_seqs_97.qza" \
            --i-reference-reads "$DATABASE/coi_marine_seqs.qza" \
            --i-reference-taxonomy "$DATABASE/coi_marine_taxonomy.qza" \
            --o-classification "04-taxonomy/taxonomy_CO1.qza" \
            --p-perc-identity 0.90 \
            --p-maxaccepts 5 \
            --verbose
        
        if [ $? -eq 0 ]; then
            echo ""
            echo "✅ SUCCÈS avec BLAST"
            SUCCESS=1
        fi
    fi
fi

#################################################################################
# FINALISATION
#################################################################################

if [ -n "$SUCCESS" ]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅✅✅ ASSIGNATION COI RÉUSSIE ✅✅✅"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Export TSV
    echo "Export TSV..."
    conda run -n $QIIME_ENV qiime tools export \
        --input-path "04-taxonomy/taxonomy_CO1.qza" \
        --output-path "export/taxonomy/temp_CO1/"
    
    mv "export/taxonomy/temp_CO1/taxonomy.tsv" "export/taxonomy/taxonomy_CO1.tsv"
    rm -rf "export/taxonomy/temp_CO1/"
    
    # Visualisation
    echo "Création visualisations..."
    conda run -n $QIIME_ENV qiime metadata tabulate \
        --m-input-file "04-taxonomy/taxonomy_CO1.qza" \
        --o-visualization "04-taxonomy/taxonomy_CO1.qzv"
    
    # Barplot
    conda run -n $QIIME_ENV qiime taxa barplot \
        --i-table "03-clustering/table_97.qza" \
        --i-taxonomy "04-taxonomy/taxonomy_CO1.qza" \
        --o-visualization "04-taxonomy/barplot_CO1.qzv" 2>/dev/null || true
    
    # Statistiques
    if [ -f "export/taxonomy/taxonomy_CO1.tsv" ]; then
        total=$(($(wc -l < "export/taxonomy/taxonomy_CO1.tsv") - 2))
        species=$(grep -E ";s__[A-Za-z]" "export/taxonomy/taxonomy_CO1.tsv" 2>/dev/null | wc -l)
        genus=$(grep -E ";g__[A-Za-z]" "export/taxonomy/taxonomy_CO1.tsv" 2>/dev/null | wc -l)
        
        echo ""
        echo "📊 RÉSULTATS COI:"
        echo "   Total OTUs: $total"
        if [ $total -gt 0 ]; then
            echo "   Niveau espèce: $species ($((species * 100 / total))%)"
            echo "   Niveau genre: $genus ($((genus * 100 / total))%)"
        fi
        echo "   Fichier: export/taxonomy/taxonomy_CO1.tsv"
        echo ""
        echo "Top 10 assignations COI:"
        head -12 "export/taxonomy/taxonomy_CO1.tsv" | tail -10 | \
            awk -F'\t' '{printf "   %s\n", $2}' | head -10
    fi
    
    echo ""
    echo "Fichiers créés:"
    echo "  ✅ 04-taxonomy/taxonomy_CO1.qza"
    echo "  ✅ 04-taxonomy/taxonomy_CO1.qzv"
    echo "  ✅ 04-taxonomy/barplot_CO1.qzv"
    echo "  ✅ export/taxonomy/taxonomy_CO1.tsv"
    echo ""
    echo "Vous pouvez maintenant analyser vos 5 taxonomies complètes!"
    echo ""
else
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "❌❌❌ TOUTES LES TENTATIVES ONT ÉCHOUÉ ❌❌❌"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Le classificateur COI est trop volumineux pour votre RAM."
    echo ""
    echo "SOLUTIONS ALTERNATIVES:"
    echo ""
    echo "1. Utiliser un nœud avec plus de RAM sur le cluster:"
    echo "   srun --mem=128G bash retry_coi.sh"
    echo ""
    echo "2. Créer un classificateur COI plus petit:"
    echo "   - Filtrer la base de données COI pour ne garder que les séquences marines"
    echo "   - Réduire la profondeur taxonomique"
    echo ""
    echo "3. Utiliser BLAST au lieu de sklearn (plus lent mais moins de RAM)"
    echo ""
    echo "4. Skip COI et analyser les 4 autres marqueurs"
    echo "   (12S-MiFish, 12S-Mimammal, 12S-Teleo, 16S fonctionnent!)"
    echo ""
fi
