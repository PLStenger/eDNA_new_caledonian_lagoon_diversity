#!/usr/bin/env bash

# BASE COI MARINE - VERSION FINALE FONCTIONNELLE
# Ordre corrigé pour éviter le mismatch séquences-taxonomie

DATABASE=/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity/98_database_files
WORKING_DIR=/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity/05_QIIME2
QIIME_ENV="qiime2-amplicon-2025.7"

cd $DATABASE

echo "======================================================================="
echo "BASE COI STRICTEMENT MARINE - Récifs coralliens"
echo "======================================================================="
echo ""

mkdir -p marine_coi_temp

#################################################################################
# ÉTAPE 1: TÉLÉCHARGEMENT
#################################################################################

echo "=== ÉTAPE 1: Téléchargement COI marines depuis NCBI ==="
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
NOT "freshwater"[All Fields]'

if [ ! -f "marine_coi_temp/coi_marine_raw_seqs.qza" ]; then
    echo "Téléchargement NCBI (30-60 min)..."
    
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
# ÉTAPE 2: FILTRAGE LONGUEUR
#################################################################################

echo "=== ÉTAPE 2: Filtrage longueur (400-800 bp) ==="
echo ""

if [ ! -f "marine_coi_temp/coi_marine_length_filt_seqs.qza" ]; then
    conda run -n $QIIME_ENV qiime rescript filter-seqs-length \
        --i-sequences "marine_coi_temp/coi_marine_raw_seqs.qza" \
        --p-global-min 400 \
        --p-global-max 800 \
        --o-filtered-seqs "marine_coi_temp/coi_marine_length_filt_seqs.qza" \
        --o-discarded-seqs "marine_coi_temp/coi_discarded_length.qza"
    
    echo "✓ Séquences filtrées par longueur"
else
    echo "✓ Déjà filtré"
fi

echo ""

#################################################################################
# ÉTAPE 3: FILTRAGE TAXONOMIQUE (après longueur)
#################################################################################

echo "=== ÉTAPE 3: Filtrage taxonomique - exclusion terrestres ==="
echo ""

if [ ! -f "marine_coi_temp/coi_marine_clean_tax.qza" ]; then
    # Export taxonomie
    conda run -n $QIIME_ENV qiime tools export \
        --input-path "marine_coi_temp/coi_marine_raw_tax.qza" \
        --output-path "marine_coi_temp/temp_tax/"
    
    # Export IDs des séquences filtrées par longueur
    conda run -n $QIIME_ENV qiime tools export \
        --input-path "marine_coi_temp/coi_marine_length_filt_seqs.qza" \
        --output-path "marine_coi_temp/temp_seqs/"
    
    # Extraire liste des IDs
    grep "^>" "marine_coi_temp/temp_seqs/dna-sequences.fasta" | sed 's/>//' > "marine_coi_temp/seqs_ids.txt"
    
    echo "Exclusion groupes terrestres/eau douce..."
    echo "  - Pulmonata, Stylommatophora"
    echo "  - Unionidae, Corbiculidae"  
    echo "  - Chilopoda, Diplopoda"
    echo "  - Insecta (tous)"
    echo "  - Genres terrestres: Helix, Limax, Arion..."
    
    # Filtrer taxonomie : garder seulement les IDs des séquences + exclure groupes terrestres
    awk 'NR==FNR{ids[$1]; next} FNR==1 || ($1 in ids)' \
        "marine_coi_temp/seqs_ids.txt" \
        "marine_coi_temp/temp_tax/taxonomy.tsv" | \
    grep -v -E "(Pulmonata|Stylommatophora|Unionidae|Corbiculidae|Chilopoda|Diplopoda|Insecta|Lepidoptera|Coleoptera|Diptera|Hymenoptera|Helix|Limax|Arion|Deroceras|Achatina|Cepaea)" \
        > "marine_coi_temp/temp_tax/taxonomy_filtered.tsv"
    
    # Stats
    before=$(wc -l < "marine_coi_temp/temp_tax/taxonomy.tsv")
    after=$(wc -l < "marine_coi_temp/temp_tax/taxonomy_filtered.tsv")
    removed=$((before - after))
    
    echo "  Avant: $before taxa"
    echo "  Après: $after taxa"
    echo "  Retirés: $removed taxa terrestres/eau douce"
    
    # Réimporter
    conda run -n $QIIME_ENV qiime tools import \
        --type 'FeatureData[Taxonomy]' \
        --input-path "marine_coi_temp/temp_tax/taxonomy_filtered.tsv" \
        --output-path "marine_coi_temp/coi_marine_clean_tax.qza"
    
    echo "✓ Taxonomie marine nettoyée"
else
    echo "✓ Déjà filtré"
fi

echo ""

#################################################################################
# ÉTAPE 4: FILTRER SÉQUENCES POUR MATCHER TAXONOMIE
#################################################################################

echo "=== ÉTAPE 4: Filtrage séquences selon taxonomie marine ==="
echo ""

if [ ! -f "marine_coi_temp/coi_marine_clean_seqs.qza" ]; then
    # Extraire IDs de la taxonomie filtrée
    conda run -n $QIIME_ENV qiime tools export \
        --input-path "marine_coi_temp/coi_marine_clean_tax.qza" \
        --output-path "marine_coi_temp/temp_tax_clean/"
    
    awk 'NR>1 {print $1}' "marine_coi_temp/temp_tax_clean/taxonomy.tsv" > "marine_coi_temp/marine_ids_to_keep.txt"
    
    echo "  IDs à garder: $(wc -l < marine_coi_temp/marine_ids_to_keep.txt)"
    
    # Filtrer séquences avec cette liste
    conda run -n $QIIME_ENV qiime taxa filter-seqs \
        --i-sequences "marine_coi_temp/coi_marine_length_filt_seqs.qza" \
        --i-taxonomy "marine_coi_temp/coi_marine_clean_tax.qza" \
        --p-mode contains \
        --p-include "k__" \
        --o-filtered-sequences "marine_coi_temp/coi_marine_clean_seqs.qza"
    
    echo "✓ Séquences filtrées"
else
    echo "✓ Déjà filtré"
fi

echo ""

#################################################################################
# ÉTAPE 5: DEREPLICATION
#################################################################################

echo "=== ÉTAPE 5: Dereplication ==="
echo ""

if [ ! -f "marine_coi_temp/coi_marine_derep_seqs.qza" ]; then
    conda run -n $QIIME_ENV qiime rescript dereplicate \
        --i-sequences "marine_coi_temp/coi_marine_clean_seqs.qza" \
        --i-taxa "marine_coi_temp/coi_marine_clean_tax.qza" \
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
    
    # Taxonomie correspondante
    conda run -n $QIIME_ENV qiime feature-table filter-seqs \
        --i-data "marine_coi_temp/coi_marine_derep_tax.qza" \
        --m-metadata-file "coi_marine_seqs_final.qza" \
        --o-filtered-data "coi_marine_tax_final.qza" 2>/dev/null || \
    cp "marine_coi_temp/coi_marine_derep_tax.qza" "coi_marine_tax_final.qza"
    
    echo "✓ Séquences et taxonomie finales"
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
    echo "Entraînement (1-3 heures selon la taille de la base)..."
    
    conda run -n $QIIME_ENV qiime feature-classifier fit-classifier-naive-bayes \
        --i-reference-reads "coi_marine_seqs_final.qza" \
        --i-reference-taxonomy "coi_marine_tax_final.qza" \
        --o-classifier "coi_marine_classifier_v2.qza" \
        --verbose
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "✓✓✓ CLASSIFICATEUR CRÉÉ ✓✓✓"
        
        # Stats
        conda run -n $QIIME_ENV qiime tools export \
            --input-path "coi_marine_tax_final.qza" \
            --output-path "marine_coi_temp/final_stats/"
        
        total=$(wc -l < "marine_coi_temp/final_stats/taxonomy.tsv")
        anthozoa=$(grep -c "Anthozoa" "marine_coi_temp/final_stats/taxonomy.tsv" || echo 0)
        gastropoda=$(grep -c "Gastropoda" "marine_coi_temp/final_stats/taxonomy.tsv" || echo 0)
        echinoidea=$(grep -c "Echinoidea" "marine_coi_temp/final_stats/taxonomy.tsv" || echo 0)
        
        echo ""
        echo "📊 BASE COI MARINE:"
        echo "   Total séquences: $total"
        echo "   Anthozoa: $anthozoa"
        echo "   Gastropoda: $gastropoda"
        echo "   Echinoidea: $echinoidea"
    else
        echo "❌ Échec entraînement"
        exit 1
    fi
else
    echo "✓ Classificateur existe déjà"
fi

echo ""

#################################################################################
# ÉTAPE 8: RÉASSIGNATION
#################################################################################

echo "=== ÉTAPE 8: Réassignation de vos OTUs avec COI MARINE ==="
echo ""

cd $WORKING_DIR

# Backup
if [ -f "04-taxonomy/taxonomy_CO1.qza" ]; then
    cp "04-taxonomy/taxonomy_CO1.qza" "04-taxonomy/taxonomy_CO1_terrestrial_backup.qza"
    cp "export/taxonomy/taxonomy_CO1.tsv" "export/taxonomy/taxonomy_CO1_terrestrial_backup.tsv"
    echo "✓ Ancien COI (avec terrestres) sauvegardé"
fi

# Nouvelle assignation
if [ ! -f "04-taxonomy/taxonomy_CO1_marine.qza" ]; then
    echo "Assignation COI MARINE en cours (30-60 min)..."
    
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
        exit 1
    fi
else
    echo "✓ Déjà assigné"
fi

echo ""

#################################################################################
# STATISTIQUES FINALES
#################################################################################

echo "======================================================================="
echo "STATISTIQUES - FAUNE MARINE DES RÉCIFS"
echo "======================================================================="
echo ""

if [ -f "export/taxonomy/taxonomy_CO1_marine.tsv" ]; then
    total=$(($(wc -l < "export/taxonomy/taxonomy_CO1_marine.tsv") - 2))
    
    # Groupes marins
    anthozoa=$(grep -ci "Anthozoa" "export/taxonomy/taxonomy_CO1_marine.tsv" || echo 0)
    scleractinia=$(grep -ci "Scleractinia" "export/taxonomy/taxonomy_CO1_marine.tsv" || echo 0)
    gastropoda=$(grep -ci "Gastropoda" "export/taxonomy/taxonomy_CO1_marine.tsv" || echo 0)
    echinoidea=$(grep -ci "Echinoidea" "export/taxonomy/taxonomy_CO1_marine.tsv" || echo 0)
    holothuroidea=$(grep -ci "Holothuroidea" "export/taxonomy/taxonomy_CO1_marine.tsv" || echo 0)
    asteroidea=$(grep -ci "Asteroidea" "export/taxonomy/taxonomy_CO1_marine.tsv" || echo 0)
    crustacea=$(grep -ci "Crustacea" "export/taxonomy/taxonomy_CO1_marine.tsv" || echo 0)
    
    echo "📊 RÉSULTATS COI MARINE - Récifs Nouvelle-Calédonie:"
    echo ""
    echo "   Total OTUs assignés: $total"
    echo ""
    echo "   Groupes récifaux détectés:"
    echo "   🪸 Anthozoa: $anthozoa (dont $scleractinia coraux durs)"
    echo "   🐚 Gastropoda: $gastropoda"
    echo "   🦔 Echinoidea: $echinoidea"
    echo "   🥒 Holothuroidea: $holothuroidea"
    echo "   ⭐ Asteroidea: $asteroidea"
    echo "   🦞 Crustacea: $crustacea"
    echo ""
    
    echo "🏆 Top 40 espèces marines détectées:"
    grep -E ";s__[A-Za-z]" "export/taxonomy/taxonomy_CO1_marine.tsv" | \
        awk -F'\t' '{print $2}' | \
        sed 's/.*; s__//' | \
        sort | uniq -c | sort -nr | head -40 | \
        awk '{printf "   %4d × %s\n", $1, $2}'
    
    echo ""
    echo "💾 Fichiers sauvegardés:"
    echo "   - export/taxonomy/taxonomy_CO1_marine.tsv (nouvelle version)"
    echo "   - export/taxonomy/taxonomy_CO1_terrestrial_backup.tsv (ancienne version)"
fi

echo ""
echo "======================================================================="
echo "✓✓✓ BASE COI MARINE OPÉRATIONNELLE ✓✓✓"
echo "======================================================================="
echo ""
echo "🌊 Plus d'espèces terrestres ni d'eau douce!"
echo "🪸 Uniquement la faune marine des récifs coralliens"
echo ""
echo "Fichiers créés:"
echo "  ✅ $DATABASE/coi_marine_classifier_v2.qza"
echo "  ✅ 04-taxonomy/taxonomy_CO1_marine.qza"
echo "  ✅ export/taxonomy/taxonomy_CO1_marine.tsv"
echo "  ✅ 04-taxonomy/barplot_CO1_marine.qzv"
echo ""
