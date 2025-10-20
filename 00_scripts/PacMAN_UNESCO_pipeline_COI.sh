#!/usr/bin/env bash

# BASE COI MARINE - VERSION ULTRA-SIMPLIFIÉE
# Skip dereplication (non critique) pour éviter les erreurs

DATABASE=/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity/98_database_files
WORKING_DIR=/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity/05_QIIME2
QIIME_ENV="qiime2-amplicon-2025.7"

cd $DATABASE

echo "======================================================================="
echo "BASE COI MARINE - Version simplifiée qui fonctionne"
echo "======================================================================="
echo ""

mkdir -p marine_coi_simple

#################################################################################
# ÉTAPE 1: TÉLÉCHARGEMENT
#################################################################################

echo "=== ÉTAPE 1: Téléchargement COI marines ==="
echo ""

MARINE_QUERY='("COI"[Gene] OR "COX1"[Gene]) AND (
    "Anthozoa"[Organism] OR 
    "Gastropoda"[Organism] OR 
    "Echinoidea"[Organism] OR 
    "Holothuroidea"[Organism] OR 
    "Asteroidea"[Organism] OR 
    "Crustacea"[Organism]
) AND 400:800[SLEN] 
NOT "environmental" 
NOT "terrestrial" 
NOT "freshwater"'

if [ ! -f "marine_coi_simple/seqs_raw.qza" ]; then
    echo "Téléchargement NCBI..."
    
    conda run -n $QIIME_ENV qiime rescript get-ncbi-data \
        --p-query "$MARINE_QUERY" \
        --p-n-jobs 4 \
        --p-rank-propagation \
        --o-sequences "marine_coi_simple/seqs_raw.qza" \
        --o-taxonomy "marine_coi_simple/tax_raw.qza"
    
    echo "✓ Téléchargé"
else
    echo "✓ Déjà téléchargé"
fi

echo ""

#################################################################################
# ÉTAPE 2: NETTOYAGE TAXONOMIE (exclusion groupes terrestres)
#################################################################################

echo "=== ÉTAPE 2: Exclusion groupes terrestres ==="
echo ""

if [ ! -f "marine_coi_simple/tax_clean.qza" ]; then
    # Export
    conda run -n $QIIME_ENV qiime tools export \
        --input-path "marine_coi_simple/tax_raw.qza" \
        --output-path "marine_coi_simple/temp/"
    
    echo "Filtrage: exclusion Insecta, Pulmonata, Unionidae..."
    
    grep -v -E "(Insecta|Lepidoptera|Coleoptera|Diptera|Pulmonata|Stylommatophora|Unionidae|Corbiculidae|Chilopoda|Helix|Limax|Arion)" \
        "marine_coi_simple/temp/taxonomy.tsv" > "marine_coi_simple/temp/taxonomy_clean.tsv"
    
    before=$(wc -l < "marine_coi_simple/temp/taxonomy.tsv")
    after=$(wc -l < "marine_coi_simple/temp/taxonomy_clean.tsv")
    
    echo "  Avant: $before"
    echo "  Après: $after"
    echo "  Retirés: $((before - after))"
    
    # Réimport
    conda run -n $QIIME_ENV qiime tools import \
        --type 'FeatureData[Taxonomy]' \
        --input-path "marine_coi_simple/temp/taxonomy_clean.tsv" \
        --output-path "marine_coi_simple/tax_clean.qza"
    
    echo "✓ Taxonomie marine nettoyée"
else
    echo "✓ Déjà nettoyé"
fi

echo ""

#################################################################################
# ÉTAPE 3: FILTRAGE SÉQUENCES PAR TAXONOMIE
#################################################################################

echo "=== ÉTAPE 3: Filtrage séquences ==="
echo ""

if [ ! -f "marine_coi_simple/seqs_clean.qza" ]; then
    conda run -n $QIIME_ENV qiime taxa filter-seqs \
        --i-sequences "marine_coi_simple/seqs_raw.qza" \
        --i-taxonomy "marine_coi_simple/tax_clean.qza" \
        --p-mode contains \
        --p-include "k__" \
        --o-filtered-sequences "marine_coi_simple/seqs_clean.qza"
    
    echo "✓ Séquences filtrées"
else
    echo "✓ Déjà filtré"
fi

echo ""

#################################################################################
# ÉTAPE 4: ENTRAÎNEMENT DIRECT (sans dereplication)
#################################################################################

echo "=== ÉTAPE 4: Entraînement classificateur ==="
echo ""

if [ ! -f "coi_marine_classifier_simple.qza" ]; then
    echo "Entraînement en cours (1-2h)..."
    
    conda run -n $QIIME_ENV qiime feature-classifier fit-classifier-naive-bayes \
        --i-reference-reads "marine_coi_simple/seqs_clean.qza" \
        --i-reference-taxonomy "marine_coi_simple/tax_clean.qza" \
        --o-classifier "coi_marine_classifier_simple.qza" \
        --verbose
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "✓✓✓ CLASSIFICATEUR CRÉÉ ✓✓✓"
        
        # Stats
        conda run -n $QIIME_ENV qiime tools export \
            --input-path "marine_coi_simple/tax_clean.qza" \
            --output-path "marine_coi_simple/stats/"
        
        total=$(wc -l < "marine_coi_simple/stats/taxonomy.tsv")
        anthozoa=$(grep -c "Anthozoa" "marine_coi_simple/stats/taxonomy.tsv" || echo 0)
        gastropoda=$(grep -c "Gastropoda" "marine_coi_simple/stats/taxonomy.tsv" || echo 0)
        
        echo ""
        echo "📊 BASE COI MARINE:"
        echo "   Séquences: $total"
        echo "   Anthozoa: $anthozoa"
        echo "   Gastropoda: $gastropoda"
    else
        echo "❌ Échec"
        exit 1
    fi
else
    echo "✓ Classificateur existe"
fi

echo ""

#################################################################################
# ÉTAPE 5: ASSIGNATION
#################################################################################

echo "=== ÉTAPE 5: Assignation de vos OTUs ==="
echo ""

cd $WORKING_DIR

# Backup
if [ -f "04-taxonomy/taxonomy_CO1.qza" ]; then
    mv "04-taxonomy/taxonomy_CO1.qza" "04-taxonomy/taxonomy_CO1_backup.qza"
    mv "export/taxonomy/taxonomy_CO1.tsv" "export/taxonomy/taxonomy_CO1_backup.tsv"
    echo "✓ Backup ancien COI"
fi

# Assignation
if [ ! -f "04-taxonomy/taxonomy_CO1_marine_simple.qza" ]; then
    echo "Assignation (30-60 min)..."
    
    conda run -n $QIIME_ENV qiime feature-classifier classify-sklearn \
        --i-classifier "$DATABASE/coi_marine_classifier_simple.qza" \
        --i-reads "03-clustering/rep_seqs_97.qza" \
        --o-classification "04-taxonomy/taxonomy_CO1_marine_simple.qza" \
        --p-confidence 0.7 \
        --p-n-jobs 4 \
        --verbose
    
    if [ $? -eq 0 ]; then
        echo "✓ Assignation réussie"
        
        # Export
        conda run -n $QIIME_ENV qiime tools export \
            --input-path "04-taxonomy/taxonomy_CO1_marine_simple.qza" \
            --output-path "export/taxonomy/temp/"
        
        mv "export/taxonomy/temp/taxonomy.tsv" "export/taxonomy/taxonomy_CO1_marine.tsv"
        rm -rf "export/taxonomy/temp/"
        
        # Visualisations
        conda run -n $QIIME_ENV qiime metadata tabulate \
            --m-input-file "04-taxonomy/taxonomy_CO1_marine_simple.qza" \
            --o-visualization "04-taxonomy/taxonomy_CO1_marine.qzv"
        
        conda run -n $QIIME_ENV qiime taxa barplot \
            --i-table "03-clustering/table_97.qza" \
            --i-taxonomy "04-taxonomy/taxonomy_CO1_marine_simple.qza" \
            --o-visualization "04-taxonomy/barplot_CO1_marine.qzv"
    else
        echo "❌ Assignation échouée"
        exit 1
    fi
else
    echo "✓ Déjà assigné"
fi

echo ""

#################################################################################
# RÉSULTATS
#################################################################################

echo "======================================================================="
echo "RÉSULTATS COI MARINE"
echo "======================================================================="
echo ""

if [ -f "export/taxonomy/taxonomy_CO1_marine.tsv" ]; then
    total=$(($(wc -l < "export/taxonomy/taxonomy_CO1_marine.tsv") - 2))
    
    anthozoa=$(grep -ci "Anthozoa" "export/taxonomy/taxonomy_CO1_marine.tsv" || echo 0)
    gastropoda=$(grep -ci "Gastropoda" "export/taxonomy/taxonomy_CO1_marine.tsv" || echo 0)
    echinoidea=$(grep -ci "Echinoidea" "export/taxonomy/taxonomy_CO1_marine.tsv" || echo 0)
    holothuroidea=$(grep -ci "Holothuroidea" "export/taxonomy/taxonomy_CO1_marine.tsv" || echo 0)
    asteroidea=$(grep -ci "Asteroidea" "export/taxonomy/taxonomy_CO1_marine.tsv" || echo 0)
    crustacea=$(grep -ci "Crustacea" "export/taxonomy/taxonomy_CO1_marine.tsv" || echo 0)
    
    echo "📊 OTUs assignés: $total"
    echo ""
    echo "Groupes récifaux:"
    echo "  🪸 Anthozoa (coraux): $anthozoa"
    echo "  🐚 Gastropoda: $gastropoda"
    echo "  🦔 Echinoidea: $echinoidea"
    echo "  🥒 Holothuroidea: $holothuroidea"
    echo "  ⭐ Asteroidea: $asteroidea"
    echo "  🦞 Crustacea: $crustacea"
    echo ""
    
    echo "🏆 Top 50 espèces marines:"
    grep -E ";s__[A-Za-z]" "export/taxonomy/taxonomy_CO1_marine.tsv" | \
        awk -F'\t' '{print $2}' | \
        sed 's/.*; s__//' | \
        sort | uniq -c | sort -nr | head -50 | \
        awk '{printf "  %4d × %s\n", $1, $2}'
fi

echo ""
echo "======================================================================="
echo "✓✓✓ TERMINÉ ✓✓✓"
echo "======================================================================="
echo ""
echo "Fichiers:"
echo "  ✅ coi_marine_classifier_simple.qza (classificateur)"
echo "  ✅ taxonomy_CO1_marine.tsv (assignations)"
echo "  ✅ barplot_CO1_marine.qzv (visualisation)"
echo ""
echo "🌊 Plus d'espèces terrestres!"
echo "🪸 Uniquement faune marine des récifs"
echo ""
