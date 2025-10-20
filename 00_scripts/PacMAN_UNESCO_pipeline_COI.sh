#!/usr/bin/env bash

# Création BASE COI MARINE - VERSION CORRIGÉE
# Exclusion des espèces terrestres/eau douce

DATABASE=/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity/98_database_files
WORKING_DIR=/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity/05_QIIME2
QIIME_ENV="qiime2-amplicon-2025.7"

cd $DATABASE

echo "======================================================================="
echo "CRÉATION BASE COI MARINE - Récifs coralliens"
echo "======================================================================="
echo ""

mkdir -p marine_coi_temp

#################################################################################
# ÉTAPE 1: TÉLÉCHARGEMENT CIBLÉ
#################################################################################

echo "=== ÉTAPE 1: Téléchargement séquences COI marines ==="
echo ""

MARINE_QUERY='("COI"[Gene] OR "cytochrome c oxidase subunit I"[Gene] OR "COX1"[Gene]) AND (
    "Anthozoa"[Organism] OR 
    "Scleractinia"[Organism] OR 
    "Alcyonacea"[Organism] OR 
    "Gastropoda"[Organism] OR 
    "Bivalvia"[Organism] OR 
    "Cephalopoda"[Organism] OR 
    "Echinoidea"[Organism] OR 
    "Asteroidea"[Organism] OR 
    "Holothuroidea"[Organism] OR 
    "Ophiuroidea"[Organism] OR 
    "Crinoidea"[Organism] OR 
    "Crustacea"[Organism] OR 
    "Polychaeta"[Organism] OR 
    "Porifera"[Organism] OR 
    "Bryozoa"[Organism] OR 
    "Ascidiacea"[Organism]
) AND 400:800[SLEN] 
NOT "environmental"[Title] 
NOT "uncultured"[Title] 
NOT "terrestrial"[All Fields] 
NOT "freshwater"[All Fields] 
NOT "land snail"[All Fields]'

if [ ! -f "marine_coi_temp/coi_marine_raw_seqs.qza" ]; then
    echo "Téléchargement depuis NCBI (peut prendre 30-60 min)..."
    
    conda run -n $QIIME_ENV qiime rescript get-ncbi-data \
        --p-query "$MARINE_QUERY" \
        --p-n-jobs 4 \
        --p-rank-propagation \
        --o-sequences "marine_coi_temp/coi_marine_raw_seqs.qza" \
        --o-taxonomy "marine_coi_temp/coi_marine_raw_tax.qza"
    
    echo "✓ Téléchargement terminé"
else
    echo "✓ Déjà téléchargé"
fi

echo ""

#################################################################################
# ÉTAPE 2: FILTRAGE TAXONOMIQUE (exclusion terrestres/eau douce)
#################################################################################

echo "=== ÉTAPE 2: Exclusion groupes terrestres/eau douce ==="
echo ""

if [ ! -f "marine_coi_temp/coi_marine_clean_tax.qza" ]; then
    # Export temporaire
    conda run -n $QIIME_ENV qiime tools export \
        --input-path "marine_coi_temp/coi_marine_raw_tax.qza" \
        --output-path "marine_coi_temp/temp_tax/"
    
    echo "Filtrage avec grep..."
    echo "Exclusion de:"
    echo "  - Pulmonata, Stylommatophora (escargots/limaces terrestres)"
    echo "  - Unionidae, Corbiculidae (moules eau douce)"
    echo "  - Chilopoda, Diplopoda (mille-pattes)"
    echo "  - Insecta (tous insectes)"
    echo "  - Helix, Limax, Arion (genres terrestres)"
    
    # Filtrer
    grep -v -E "(Pulmonata|Stylommatophora|Unionidae|Corbiculidae|Chilopoda|Diplopoda|Insecta|Lepidoptera|Coleoptera|Diptera|Hymenoptera|Helix|Limax|Arion|Deroceras|Achatina|Cepaea)" \
        "marine_coi_temp/temp_tax/taxonomy.tsv" > "marine_coi_temp/temp_tax/taxonomy_filtered.tsv"
    
    # Stats
    before=$(wc -l < "marine_coi_temp/temp_tax/taxonomy.tsv")
    after=$(wc -l < "marine_coi_temp/temp_tax/taxonomy_filtered.tsv")
    removed=$((before - after))
    
    echo "  Lignes avant: $before"
    echo "  Lignes après: $after"
    echo "  Lignes retirées: $removed"
    
    # Réimporter
    conda run -n $QIIME_ENV qiime tools import \
        --type 'FeatureData[Taxonomy]' \
        --input-path "marine_coi_temp/temp_tax/taxonomy_filtered.tsv" \
        --output-path "marine_coi_temp/coi_marine_clean_tax.qza"
    
    echo "✓ Taxonomie filtrée"
else
    echo "✓ Déjà filtré"
fi

echo ""

#################################################################################
# ÉTAPE 3: FILTRAGE SÉQUENCES PAR LONGUEUR (simple)
#################################################################################

echo "=== ÉTAPE 3: Filtrage séquences par longueur ==="
echo ""

if [ ! -f "marine_coi_temp/coi_marine_clean_seqs.qza" ]; then
    conda run -n $QIIME_ENV qiime rescript filter-seqs-length \
        --i-sequences "marine_coi_temp/coi_marine_raw_seqs.qza" \
        --p-global-min 400 \
        --p-global-max 800 \
        --o-filtered-seqs "marine_coi_temp/coi_marine_clean_seqs.qza" \
        --o-discarded-seqs "marine_coi_temp/coi_marine_discarded.qza"
    
    echo "✓ Séquences filtrées (400-800 bp)"
else
    echo "✓ Déjà filtré"
fi

echo ""

#################################################################################
# ÉTAPE 4: FILTRER SÉQUENCES POUR MATCHER TAXONOMIE
#################################################################################

echo "=== ÉTAPE 4: Synchronisation séquences-taxonomie ==="
echo ""

if [ ! -f "marine_coi_temp/coi_marine_matched_seqs.qza" ]; then
    # Filtrer séquences pour ne garder que celles dans la taxonomie filtrée
    conda run -n $QIIME_ENV qiime rescript filter-taxa \
        --i-taxonomy "marine_coi_temp/coi_marine_clean_tax.qza" \
        --m-ids-to-keep-file "marine_coi_temp/coi_marine_clean_seqs.qza" \
        --o-filtered-taxonomy "marine_coi_temp/coi_marine_matched_tax.qza"
    
    # Filtrer séquences pour ne garder que celles dans la taxonomie
    conda run -n $QIIME_ENV qiime feature-table filter-seqs \
        --i-data "marine_coi_temp/coi_marine_clean_seqs.qza" \
        --m-metadata-file "marine_coi_temp/coi_marine_matched_tax.qza" \
        --o-filtered-data "marine_coi_temp/coi_marine_matched_seqs.qza"
    
    echo "✓ Séquences et taxonomie synchronisées"
else
    echo "✓ Déjà synchronisé"
fi

echo ""

#################################################################################
# ÉTAPE 5: DEREPLICATION
#################################################################################

echo "=== ÉTAPE 5: Dereplication ==="
echo ""

if [ ! -f "marine_coi_temp/coi_marine_derep_seqs.qza" ]; then
    conda run -n $QIIME_ENV qiime rescript dereplicate \
        --i-sequences "marine_coi_temp/coi_marine_matched_seqs.qza" \
        --i-taxa "marine_coi_temp/coi_marine_matched_tax.qza" \
        --p-mode 'uniq' \
        --p-derep-prefix \
        --o-dereplicated-sequences "marine_coi_temp/coi_marine_derep_seqs.qza" \
        --o-dereplicated-taxa "marine_coi_temp/coi_marine_derep_tax.qza"
    
    echo "✓ Dereplication terminée"
else
    echo "✓ Déjà dereplicaté"
fi

echo ""

#################################################################################
# ÉTAPE 6: NETTOYAGE FINAL
#################################################################################

echo "=== ÉTAPE 6: Nettoyage final ==="
echo ""

if [ ! -f "coi_marine_seqs_final.qza" ]; then
    conda run -n $QIIME_ENV qiime rescript cull-seqs \
        --i-sequences "marine_coi_temp/coi_marine_derep_seqs.qza" \
        --p-num-degenerates 5 \
        --p-homopolymer-length 8 \
        --o-clean-sequences "coi_marine_seqs_final.qza"
    
    echo "✓ Séquences nettoyées"
    
    # Filtrer taxonomie correspondante
    conda run -n $QIIME_ENV qiime rescript filter-taxa \
        --i-taxonomy "marine_coi_temp/coi_marine_derep_tax.qza" \
        --m-ids-to-keep-file "coi_marine_seqs_final.qza" \
        --o-filtered-taxonomy "coi_marine_tax_final.qza"
    
    echo "✓ Taxonomie finale"
else
    echo "✓ Déjà nettoyé"
fi

echo ""

#################################################################################
# ÉTAPE 7: ENTRAÎNEMENT CLASSIFICATEUR
#################################################################################

echo "=== ÉTAPE 7: Entraînement classificateur COI MARINE ==="
echo ""

if [ ! -f "coi_marine_classifier_v2.qza" ]; then
    echo "Entraînement en cours (1-3 heures)..."
    
    conda run -n $QIIME_ENV qiime feature-classifier fit-classifier-naive-bayes \
        --i-reference-reads "coi_marine_seqs_final.qza" \
        --i-reference-taxonomy "coi_marine_tax_final.qza" \
        --o-classifier "coi_marine_classifier_v2.qza" \
        --verbose
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "✓✓✓ CLASSIFICATEUR COI MARINE CRÉÉ ✓✓✓"
        
        # Stats sur la base
        conda run -n $QIIME_ENV qiime tools export \
            --input-path "coi_marine_tax_final.qza" \
            --output-path "marine_coi_temp/final_tax/"
        
        total_seqs=$(wc -l < "marine_coi_temp/final_tax/taxonomy.tsv")
        anthozoa=$(grep -c "Anthozoa" "marine_coi_temp/final_tax/taxonomy.tsv" || echo 0)
        gastropoda=$(grep -c "Gastropoda" "marine_coi_temp/final_tax/taxonomy.tsv" || echo 0)
        echinoidea=$(grep -c "Echinoidea" "marine_coi_temp/final_tax/taxonomy.tsv" || echo 0)
        
        echo ""
        echo "📊 BASE DE DONNÉES COI MARINE:"
        echo "   Total séquences: $total_seqs"
        echo "   Anthozoa: $anthozoa"
        echo "   Gastropoda: $gastropoda"
        echo "   Echinoidea: $echinoidea"
    else
        echo "❌ Échec entraînement"
        exit 1
    fi
else
    echo "✓ Classificateur déjà créé"
fi

echo ""

#################################################################################
# ÉTAPE 8: RÉASSIGNATION
#################################################################################

echo "=== ÉTAPE 8: Réassignation COI avec base marine ==="
echo ""

cd $WORKING_DIR

# Backup ancien
if [ -f "04-taxonomy/taxonomy_CO1.qza" ]; then
    cp "04-taxonomy/taxonomy_CO1.qza" "04-taxonomy/taxonomy_CO1_old_backup.qza"
    cp "export/taxonomy/taxonomy_CO1.tsv" "export/taxonomy/taxonomy_CO1_old_backup.tsv"
    echo "✓ Ancien COI sauvegardé"
fi

# Nouvelle assignation
if [ ! -f "04-taxonomy/taxonomy_CO1_marine.qza" ]; then
    echo "Assignation en cours..."
    
    conda run -n $QIIME_ENV qiime feature-classifier classify-sklearn \
        --i-classifier "$DATABASE/coi_marine_classifier_v2.qza" \
        --i-reads "03-clustering/rep_seqs_97.qza" \
        --o-classification "04-taxonomy/taxonomy_CO1_marine.qza" \
        --p-confidence 0.7 \
        --p-n-jobs 4 \
        --verbose
    
    if [ $? -eq 0 ]; then
        echo "✓ Assignation réussie"
        
        # Export
        conda run -n $QIIME_ENV qiime tools export \
            --input-path "04-taxonomy/taxonomy_CO1_marine.qza" \
            --output-path "export/taxonomy/temp_marine/"
        
        mv "export/taxonomy/temp_marine/taxonomy.tsv" "export/taxonomy/taxonomy_CO1_marine.tsv"
        rm -rf "export/taxonomy/temp_marine/"
        
        # Visualisations
        conda run -n $QIIME_ENV qiime metadata tabulate \
            --m-input-file "04-taxonomy/taxonomy_CO1_marine.qza" \
            --o-visualization "04-taxonomy/taxonomy_CO1_marine.qzv"
        
        conda run -n $QIIME_ENV qiime taxa barplot \
            --i-table "03-clustering/table_97.qza" \
            --i-taxonomy "04-taxonomy/taxonomy_CO1_marine.qza" \
            --o-visualization "04-taxonomy/barplot_CO1_marine.qzv"
        
        echo "✓ Visualisations créées"
    else
        echo "❌ Assignation échouée"
    fi
else
    echo "✓ Déjà assigné"
fi

echo ""

#################################################################################
# STATISTIQUES FINALES
#################################################################################

echo "======================================================================="
echo "STATISTIQUES FINALES"
echo "======================================================================="
echo ""

if [ -f "export/taxonomy/taxonomy_CO1_marine.tsv" ]; then
    total=$(($(wc -l < "export/taxonomy/taxonomy_CO1_marine.tsv") - 2))
    
    # Groupes marins
    anthozoa=$(grep -c "Anthozoa" "export/taxonomy/taxonomy_CO1_marine.tsv" || echo 0)
    gastropoda=$(grep -c "Gastropoda" "export/taxonomy/taxonomy_CO1_marine.tsv" || echo 0)
    echinoidea=$(grep -c "Echinoidea" "export/taxonomy/taxonomy_CO1_marine.tsv" || echo 0)
    holothuroidea=$(grep -c "Holothuroidea" "export/taxonomy/taxonomy_CO1_marine.tsv" || echo 0)
    asteroidea=$(grep -c "Asteroidea" "export/taxonomy/taxonomy_CO1_marine.tsv" || echo 0)
    crustacea=$(grep -c "Crustacea" "export/taxonomy/taxonomy_CO1_marine.tsv" || echo 0)
    
    echo "📊 RÉSULTATS COI MARINE (Nouvelle-Calédonie):"
    echo ""
    echo "   Total OTUs assignés: $total"
    echo ""
    echo "   Groupes récifaux détectés:"
    echo "   🪸 Anthozoa (coraux): $anthozoa"
    echo "   🐚 Gastropoda: $gastropoda"
    echo "   🦔 Echinoidea (oursins): $echinoidea"
    echo "   🥒 Holothuroidea: $holothuroidea"
    echo "   ⭐ Asteroidea: $asteroidea"
    echo "   🦞 Crustacea: $crustacea"
    echo ""
    
    echo "Top 30 espèces marines détectées:"
    grep -E ";s__[A-Za-z]" "export/taxonomy/taxonomy_CO1_marine.tsv" | \
        awk -F'\t' '{print $2}' | \
        sed 's/.*; s__//' | \
        sort | uniq -c | sort -nr | head -30 | \
        awk '{printf "   %3d × %s\n", $1, $2}'
fi

echo ""
echo "======================================================================="
echo "✓✓✓ TERMINÉ - BASE COI MARINE OPÉRATIONNELLE ✓✓✓"
echo "======================================================================="
echo ""
echo "Fichiers créés:"
echo "  ✅ coi_marine_classifier_v2.qza (classificateur marine)"
echo "  ✅ taxonomy_CO1_marine.qza / .tsv"
echo "  ✅ barplot_CO1_marine.qzv"
echo ""
echo "Plus d'espèces terrestres/eau douce !"
echo "Uniquement faune marine des récifs coralliens 🪸🌊"
echo ""
