#!/usr/bin/env bash

# BASE COI MARINE - VERSION MINIMALE QUI FONCTIONNE
# Utilise seqs brutes + tax filtrée directement

DATABASE=/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity/98_database_files
WORKING_DIR=/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity/05_QIIME2
QIIME_ENV="qiime2-amplicon-2025.7"

cd $DATABASE

echo "======================================================================="
echo "BASE COI MARINE - Version minimale fonctionnelle"
echo "======================================================================="
echo ""

mkdir -p marine_coi_minimal

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

if [ ! -f "marine_coi_minimal/seqs.qza" ]; then
    echo "Téléchargement..."
    
    conda run -n $QIIME_ENV qiime rescript get-ncbi-data \
        --p-query "$MARINE_QUERY" \
        --p-n-jobs 4 \
        --p-rank-propagation \
        --o-sequences "marine_coi_minimal/seqs.qza" \
        --o-taxonomy "marine_coi_minimal/tax_raw.qza"
    
    echo "✓ Téléchargé"
else
    echo "✓ Déjà téléchargé"
fi

echo ""

#################################################################################
# ÉTAPE 2: NETTOYAGE TAXONOMIE SEULEMENT
#################################################################################

echo "=== ÉTAPE 2: Nettoyage taxonomie ==="
echo ""

if [ ! -f "marine_coi_minimal/tax_marine.qza" ]; then
    # Export
    conda run -n $QIIME_ENV qiime tools export \
        --input-path "marine_coi_minimal/tax_raw.qza" \
        --output-path "marine_coi_minimal/temp/"
    
    echo "Exclusion groupes terrestres..."
    
    grep -v -E "(Insecta|Lepidoptera|Coleoptera|Diptera|Pulmonata|Stylommatophora|Unionidae|Corbiculidae|Chilopoda|Helix|Limax|Arion)" \
        "marine_coi_minimal/temp/taxonomy.tsv" > "marine_coi_minimal/temp/tax_clean.tsv"
    
    before=$(wc -l < "marine_coi_minimal/temp/taxonomy.tsv")
    after=$(wc -l < "marine_coi_minimal/temp/tax_clean.tsv")
    
    echo "  Avant: $before"
    echo "  Après: $after"
    echo "  Retirés: $((before - after))"
    
    # Réimport
    conda run -n $QIIME_ENV qiime tools import \
        --type 'FeatureData[Taxonomy]' \
        --input-path "marine_coi_minimal/temp/tax_clean.tsv" \
        --output-path "marine_coi_minimal/tax_marine.qza"
    
    echo "✓ Taxonomie nettoyée"
else
    echo "✓ Déjà nettoyé"
fi

echo ""

#################################################################################
# ÉTAPE 3: ENTRAÎNEMENT DIRECT (sans filtrage séquences)
#################################################################################

echo "=== ÉTAPE 3: Entraînement classificateur ==="
echo ""
echo "ASTUCE: On utilise les séquences brutes + taxonomie filtrée"
echo "sklearn ignorera automatiquement les séquences sans taxonomie"
echo ""

if [ ! -f "coi_marine_classifier_minimal.qza" ]; then
    echo "Entraînement (1-2h)..."
    
    # DIRECT: séquences brutes + taxonomie filtrée
    # sklearn est assez intelligent pour gérer le mismatch
    conda run -n $QIIME_ENV qiime feature-classifier fit-classifier-naive-bayes \
        --i-reference-reads "marine_coi_minimal/seqs.qza" \
        --i-reference-taxonomy "marine_coi_minimal/tax_marine.qza" \
        --o-classifier "coi_marine_classifier_minimal.qza" \
        --verbose 2>&1 | tee classifier_training.log
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "✓✓✓ CLASSIFICATEUR CRÉÉ ✓✓✓"
        
        # Stats
        conda run -n $QIIME_ENV qiime tools export \
            --input-path "marine_coi_minimal/tax_marine.qza" \
            --output-path "marine_coi_minimal/stats/"
        
        total=$(wc -l < "marine_coi_minimal/stats/taxonomy.tsv")
        anthozoa=$(grep -c "Anthozoa" "marine_coi_minimal/stats/taxonomy.tsv" || echo 0)
        
        echo ""
        echo "📊 BASE:"
        echo "   Séquences taxonomie: $total"
        echo "   Anthozoa: $anthozoa"
    else
        echo "❌ Échec"
        echo "Log: classifier_training.log"
        exit 1
    fi
else
    echo "✓ Classificateur existe"
fi

echo ""

#################################################################################
# ÉTAPE 4: ASSIGNATION
#################################################################################

echo "=== ÉTAPE 4: Assignation OTUs ==="
echo ""

cd $WORKING_DIR

# Backup
if [ -f "export/taxonomy/taxonomy_CO1.tsv" ]; then
    cp "export/taxonomy/taxonomy_CO1.tsv" "export/taxonomy/taxonomy_CO1_OLD.tsv"
    echo "✓ Backup ancien COI → taxonomy_CO1_OLD.tsv"
fi

# Assignation
if [ ! -f "04-taxonomy/taxonomy_CO1_marine_minimal.qza" ]; then
    echo "Assignation (30-60 min)..."
    
    conda run -n $QIIME_ENV qiime feature-classifier classify-sklearn \
        --i-classifier "$DATABASE/coi_marine_classifier_minimal.qza" \
        --i-reads "03-clustering/rep_seqs_97.qza" \
        --o-classification "04-taxonomy/taxonomy_CO1_marine_minimal.qza" \
        --p-confidence 0.7 \
        --p-n-jobs 4 \
        --verbose
    
    if [ $? -eq 0 ]; then
        echo "✓ Assignation réussie"
        
        # Export
        conda run -n $QIIME_ENV qiime tools export \
            --input-path "04-taxonomy/taxonomy_CO1_marine_minimal.qza" \
            --output-path "export/taxonomy/temp/"
        
        mv "export/taxonomy/temp/taxonomy.tsv" "export/taxonomy/taxonomy_CO1_MARINE.tsv"
        rm -rf "export/taxonomy/temp/"
        
        # Visualisations
        conda run -n $QIIME_ENV qiime metadata tabulate \
            --m-input-file "04-taxonomy/taxonomy_CO1_marine_minimal.qza" \
            --o-visualization "04-taxonomy/taxonomy_CO1_MARINE.qzv"
        
        conda run -n $QIIME_ENV qiime taxa barplot \
            --i-table "03-clustering/table_97.qza" \
            --i-taxonomy "04-taxonomy/taxonomy_CO1_marine_minimal.qza" \
            --o-visualization "04-taxonomy/barplot_CO1_MARINE.qzv"
        
        echo "✓ Visualisations créées"
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

if [ -f "export/taxonomy/taxonomy_CO1_MARINE.tsv" ]; then
    total=$(($(wc -l < "export/taxonomy/taxonomy_CO1_MARINE.tsv") - 2))
    
    # Groupes marins
    anthozoa=$(grep -ci "Anthozoa" "export/taxonomy/taxonomy_CO1_MARINE.tsv" 2>/dev/null || echo 0)
    scleractinia=$(grep -ci "Scleractinia" "export/taxonomy/taxonomy_CO1_MARINE.tsv" 2>/dev/null || echo 0)
    gastropoda=$(grep -ci "Gastropoda" "export/taxonomy/taxonomy_CO1_MARINE.tsv" 2>/dev/null || echo 0)
    echinoidea=$(grep -ci "Echinoidea" "export/taxonomy/taxonomy_CO1_MARINE.tsv" 2>/dev/null || echo 0)
    holothuroidea=$(grep -ci "Holothuroidea" "export/taxonomy/taxonomy_CO1_MARINE.tsv" 2>/dev/null || echo 0)
    asteroidea=$(grep -ci "Asteroidea" "export/taxonomy/taxonomy_CO1_MARINE.tsv" 2>/dev/null || echo 0)
    crustacea=$(grep -ci "Crustacea" "export/taxonomy/taxonomy_CO1_MARINE.tsv" 2>/dev/null || echo 0)
    
    # Vérifier terrestres résiduels
    insecta=$(grep -ci "Insecta" "export/taxonomy/taxonomy_CO1_MARINE.tsv" 2>/dev/null || echo 0)
    lepidoptera=$(grep -ci "Lepidoptera" "export/taxonomy/taxonomy_CO1_MARINE.tsv" 2>/dev/null || echo 0)
    
    echo "📊 RÉSULTATS:"
    echo "   Total OTUs assignés: $total"
    echo ""
    echo "Groupes récifaux:"
    echo "  🪸 Anthozoa: $anthozoa (dont $scleractinia coraux durs)"
    echo "  🐚 Gastropoda: $gastropoda"
    echo "  🦔 Echinoidea: $echinoidea"
    echo "  🥒 Holothuroidea: $holothuroidea"
    echo "  ⭐ Asteroidea: $asteroidea"
    echo "  🦞 Crustacea: $crustacea"
    echo ""
    
    if [ $insecta -gt 0 ] || [ $lepidoptera -gt 0 ]; then
        echo "⚠️  Terrestres résiduels:"
        echo "  🦋 Insecta: $insecta"
        echo "  🦋 Lepidoptera: $lepidoptera"
        echo ""
    else
        echo "✅ AUCUN groupe terrestre détecté!"
        echo ""
    fi
    
    echo "🏆 Top 60 espèces marines:"
    grep -E ";s__[A-Za-z]" "export/taxonomy/taxonomy_CO1_MARINE.tsv" 2>/dev/null | \
        awk -F'\t' '{print $2}' | \
        sed 's/.*; s__//' | \
        sort | uniq -c | sort -nr | head -60 | \
        awk '{printf "  %4d × %s\n", $1, $2}'
    
    echo ""
    echo "💾 Fichiers:"
    echo "  - export/taxonomy/taxonomy_CO1_MARINE.tsv (NOUVEAU - marine seulement)"
    echo "  - export/taxonomy/taxonomy_CO1_OLD.tsv (ancien avec terrestres)"
fi

echo ""
echo "======================================================================="
echo "✓✓✓ TERMINÉ ✓✓✓"
echo "======================================================================="
echo ""
echo "Fichiers créés:"
echo "  ✅ coi_marine_classifier_minimal.qza"
echo "  ✅ taxonomy_CO1_MARINE.tsv"
echo "  ✅ taxonomy_CO1_MARINE.qzv"
echo "  ✅ barplot_CO1_MARINE.qzv"
echo ""
echo "🌊 Comparez les deux versions:"
echo "  - taxonomy_CO1_OLD.tsv (avec terrestres)"
echo "  - taxonomy_CO1_MARINE.tsv (sans terrestres)"
echo ""
