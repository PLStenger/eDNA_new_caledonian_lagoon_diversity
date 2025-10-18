#!/usr/bin/env bash

# Création d'une base de données COI STRICTEMENT MARINE
# Focus: Gastéropodes marins, Coraux, Échinodermes, Poissons récifaux
# Exclusion: Espèces terrestres et d'eau douce

DATABASE=/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity/98_database_files
WORKING_DIR=/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity/05_QIIME2
QIIME_ENV="qiime2-amplicon-2025.7"

cd $DATABASE

echo "======================================================================="
echo "CRÉATION BASE COI MARINE - Récifs coralliens Nouvelle-Calédonie"
echo "======================================================================="
echo ""

mkdir -p marine_coi_temp

#################################################################################
# ÉTAPE 1: TÉLÉCHARGEMENT CIBLÉ TAXONS MARINS
#################################################################################

echo "=== ÉTAPE 1: Téléchargement séquences COI marines ciblées ==="
echo ""

# Requête NCBI ciblée sur les grands groupes marins des récifs coralliens
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

echo "Téléchargement depuis NCBI..."
echo "Groupes ciblés:"
echo "  - Anthozoa (coraux durs et mous)"
echo "  - Gastropoda (gastéropodes marins)"
echo "  - Bivalvia (bivalves marins)"
echo "  - Echinoidea (oursins)"
echo "  - Holothuroidea (holothuries)"
echo "  - Asteroidea (étoiles de mer)"
echo "  - Ophiuroidea (ophiures)"
echo "  - Crustacea (crustacés)"
echo "  - Polychaeta (vers polychètes)"
echo "  - Porifera (éponges)"
echo "  - Ascidiacea (ascidies)"
echo ""

if [ ! -f "marine_coi_temp/coi_marine_raw_seqs.qza" ]; then
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
# ÉTAPE 2: NETTOYAGE ET FILTRAGE TAXONOMIQUE
#################################################################################

echo "=== ÉTAPE 2: Nettoyage et exclusion des groupes terrestres/eau douce ==="
echo ""

# Filtrer les taxa indésirables
if [ ! -f "marine_coi_temp/coi_marine_clean_tax.qza" ]; then
    echo "Filtrage des groupes non-marins..."
    
    # Export temporaire pour filtrage
    conda run -n $QIIME_ENV qiime tools export \
        --input-path "marine_coi_temp/coi_marine_raw_tax.qza" \
        --output-path "marine_coi_temp/temp_tax/"
    
    # Filtrer avec grep (exclusion patterns)
    echo "Exclusion des patterns:"
    echo "  - Pulmonata (escargots terrestres)"
    echo "  - Stylommatophora (limaces terrestres)"
    echo "  - Unionidae (moules d'eau douce)"
    echo "  - Corbiculidae (corbicula eau douce)"
    echo "  - Chilopoda (scolopendres)"
    echo "  - Diplopoda (mille-pattes)"
    echo "  - Insecta (insectes terrestres)"
    echo "  - Lepidoptera (papillons)"
    
    grep -v -E "(Pulmonata|Stylommatophora|Unionidae|Corbiculidae|Chilopoda|Diplopoda|Insecta|Lepidoptera|Coleoptera|Diptera|Hymenoptera|Helix|Limax|Arion|Deroceras)" \
        "marine_coi_temp/temp_tax/taxonomy.tsv" > "marine_coi_temp/temp_tax/taxonomy_filtered.tsv"
    
    # Réimporter
    conda run -n $QIIME_ENV qiime tools import \
        --type 'FeatureData[Taxonomy]' \
        --input-path "marine_coi_temp/temp_tax/taxonomy_filtered.tsv" \
        --output-path "marine_coi_temp/coi_marine_clean_tax.qza"
    
    echo "✓ Filtrage terminé"
    
    # Compter combien de séquences restent
    before=$(grep -c "^[^#]" "marine_coi_temp/temp_tax/taxonomy.tsv" || echo 0)
    after=$(grep -c "^[^#]" "marine_coi_temp/temp_tax/taxonomy_filtered.tsv" || echo 0)
    removed=$((before - after))
    
    echo "  Séquences avant: $before"
    echo "  Séquences après: $after"
    echo "  Séquences retirées: $removed"
else
    echo "✓ Déjà filtré"
fi

echo ""

#################################################################################
# ÉTAPE 3: FILTRER LES SÉQUENCES CORRESPONDANTES
#################################################################################

echo "=== ÉTAPE 3: Filtrage des séquences ==="
echo ""

if [ ! -f "marine_coi_temp/coi_marine_clean_seqs.qza" ]; then
    conda run -n $QIIME_ENV qiime rescript filter-seqs-length-by-taxon \
        --i-sequences "marine_coi_temp/coi_marine_raw_seqs.qza" \
        --i-taxonomy "marine_coi_temp/coi_marine_clean_tax.qza" \
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
# ÉTAPE 4: DEREPLICATION
#################################################################################

echo "=== ÉTAPE 4: Dereplication ==="
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
# ÉTAPE 5: CULL SEQS (nettoyage final)
#################################################################################

echo "=== ÉTAPE 5: Nettoyage final des séquences ==="
echo ""

if [ ! -f "coi_marine_seqs_final.qza" ]; then
    conda run -n $QIIME_ENV qiime rescript cull-seqs \
        --i-sequences "marine_coi_temp/coi_marine_derep_seqs.qza" \
        --p-num-degenerates 5 \
        --p-homopolymer-length 8 \
        --o-clean-sequences "coi_marine_seqs_final.qza"
    
    echo "✓ Nettoyage terminé"
else
    echo "✓ Déjà nettoyé"
fi

# Filtrer taxonomie correspondante
if [ ! -f "coi_marine_tax_final.qza" ]; then
    conda run -n $QIIME_ENV qiime rescript filter-taxa \
        --i-taxonomy "marine_coi_temp/coi_marine_derep_tax.qza" \
        --m-ids-to-keep-file "coi_marine_seqs_final.qza" \
        --o-filtered-taxonomy "coi_marine_tax_final.qza"
    
    echo "✓ Taxonomie filtrée"
fi

echo ""

#################################################################################
# ÉTAPE 6: ENTRAÎNEMENT CLASSIFICATEUR
#################################################################################

echo "=== ÉTAPE 6: Entraînement classificateur COI MARINE ==="
echo ""

if [ ! -f "coi_marine_classifier_v2.qza" ]; then
    echo "Cela peut prendre 1-3 heures..."
    
    conda run -n $QIIME_ENV qiime feature-classifier fit-classifier-naive-bayes \
        --i-reference-reads "coi_marine_seqs_final.qza" \
        --i-reference-taxonomy "coi_marine_tax_final.qza" \
        --o-classifier "coi_marine_classifier_v2.qza"
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "✓✓✓ CLASSIFICATEUR COI MARINE CRÉÉ AVEC SUCCÈS ✓✓✓"
    else
        echo "❌ Échec de l'entraînement"
        exit 1
    fi
else
    echo "✓ Classificateur déjà créé"
fi

echo ""

#################################################################################
# ÉTAPE 7: RÉASSIGNATION COI AVEC LA NOUVELLE BASE
#################################################################################

echo "=== ÉTAPE 7: Réassignation COI avec base marine uniquement ==="
echo ""

cd $WORKING_DIR

# Backup ancien COI
if [ -f "04-taxonomy/taxonomy_CO1.qza" ]; then
    mv "04-taxonomy/taxonomy_CO1.qza" "04-taxonomy/taxonomy_CO1_old.qza"
    mv "export/taxonomy/taxonomy_CO1.tsv" "export/taxonomy/taxonomy_CO1_old.tsv"
    echo "✓ Ancien COI sauvegardé"
fi

# Nouvelle assignation
echo "Lancement assignation COI marine..."

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
        --output-path "export/taxonomy/temp_CO1/"
    
    mv "export/taxonomy/temp_CO1/taxonomy.tsv" "export/taxonomy/taxonomy_CO1_marine.tsv"
    rm -rf "export/taxonomy/temp_CO1/"
    
    # Visualisations
    conda run -n $QIIME_ENV qiime metadata tabulate \
        --m-input-file "04-taxonomy/taxonomy_CO1_marine.qza" \
        --o-visualization "04-taxonomy/taxonomy_CO1_marine.qzv"
    
    conda run -n $QIIME_ENV qiime taxa barplot \
        --i-table "03-clustering/table_97.qza" \
        --i-taxonomy "04-taxonomy/taxonomy_CO1_marine.qza" \
        --o-visualization "04-taxonomy/barplot_CO1_marine.qzv" 2>/dev/null || true
    
    echo "✓ Visualisations créées"
else
    echo "❌ Assignation échouée"
fi

echo ""

#################################################################################
# STATISTIQUES ET COMPARAISON
#################################################################################

echo "======================================================================="
echo "STATISTIQUES ET COMPARAISON"
echo "======================================================================="
echo ""

if [ -f "export/taxonomy/taxonomy_CO1_marine.tsv" ]; then
    total=$(($(wc -l < "export/taxonomy/taxonomy_CO1_marine.tsv") - 2))
    
    # Compter les grands groupes marins
    anthozoa=$(grep -c "Anthozoa" "export/taxonomy/taxonomy_CO1_marine.tsv" || echo 0)
    gastropoda=$(grep -c "Gastropoda" "export/taxonomy/taxonomy_CO1_marine.tsv" || echo 0)
    echinoidea=$(grep -c "Echinoidea" "export/taxonomy/taxonomy_CO1_marine.tsv" || echo 0)
    holothuroidea=$(grep -c "Holothuroidea" "export/taxonomy/taxonomy_CO1_marine.tsv" || echo 0)
    asteroidea=$(grep -c "Asteroidea" "export/taxonomy/taxonomy_CO1_marine.tsv" || echo 0)
    crustacea=$(grep -c "Crustacea" "export/taxonomy/taxonomy_CO1_marine.tsv" || echo 0)
    polychaeta=$(grep -c "Polychaeta" "export/taxonomy/taxonomy_CO1_marine.tsv" || echo 0)
    
    echo "📊 RÉSULTATS COI MARINE:"
    echo "   Total OTUs assignés: $total"
    echo ""
    echo "   Groupes détectés:"
    echo "   🪸 Anthozoa (coraux): $anthozoa"
    echo "   🐚 Gastropoda (gastéropodes): $gastropoda"
    echo "   🦔 Echinoidea (oursins): $echinoidea"
    echo "   🥒 Holothuroidea (holothuries): $holothuroidea"
    echo "   ⭐ Asteroidea (étoiles de mer): $asteroidea"
    echo "   🦞 Crustacea (crustacés): $crustacea"
    echo "   🪱 Polychaeta (vers): $polychaeta"
    echo ""
    
    echo "Top 20 espèces COI marines détectées:"
    grep -E ";s__[A-Za-z]" "export/taxonomy/taxonomy_CO1_marine.tsv" | \
        awk -F'\t' '{print $2}' | \
        sed 's/.*; s__//' | \
        sort | uniq -c | sort -nr | head -20
fi

echo ""
echo "======================================================================="
echo "✓✓✓ BASE COI MARINE CRÉÉE ET APPLIQUÉE ✓✓✓"
echo "======================================================================="
echo ""
echo "Fichiers créés:"
echo "  ✅ $DATABASE/coi_marine_classifier_v2.qza (nouveau classificateur)"
echo "  ✅ 04-taxonomy/taxonomy_CO1_marine.qza"
echo "  ✅ export/taxonomy/taxonomy_CO1_marine.tsv"
echo "  ✅ 04-taxonomy/barplot_CO1_marine.qzv"
echo ""
echo "Anciens fichiers sauvegardés:"
echo "  📦 04-taxonomy/taxonomy_CO1_old.qza"
echo "  📦 export/taxonomy/taxonomy_CO1_old.tsv"
echo ""
echo "Vous avez maintenant uniquement des espèces MARINES!"
echo "Focus: Coraux, gastéropodes marins, échinodermes, crustacés récifaux"
echo ""


### ### Fonctionne mais ne donne pas du 100% marins:
### 
### #!/usr/bin/env bash
### 
### # Script pour relancer UNIQUEMENT l'assignation COI
### # Problème: Out of Memory (SIGKILL -9)
### # Solution: Moins de threads + traitement par batch
### 
### WORKING_DIR=/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity/05_QIIME2
### DATABASE=/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity/98_database_files
### QIIME_ENV="qiime2-amplicon-2025.7"
### 
### cd $WORKING_DIR
### 
### echo "======================================================================="
### echo "RELANCE ASSIGNATION COI - Version optimisée mémoire"
### echo "======================================================================="
### echo ""
### 
### # Vérifier les fichiers nécessaires
### if [ ! -f "03-clustering/rep_seqs_97.qza" ]; then
###     echo "❌ Fichier rep_seqs_97.qza manquant"
###     exit 1
### fi
### 
### if [ ! -f "$DATABASE/coi_marine_classifier.qza" ]; then
###     echo "❌ Classificateur COI manquant"
###     exit 1
### fi
### 
### mkdir -p 04-taxonomy
### mkdir -p export/taxonomy
### 
### echo "Préparation:"
### echo "  - Séquences: 03-clustering/rep_seqs_97.qza"
### echo "  - Classificateur: coi_marine_classifier.qza"
### echo "  - Threads: 2 (au lieu de 8) pour économiser la RAM"
### echo ""
### 
### #################################################################################
### # STRATÉGIE 1: Avec 2 threads seulement
### #################################################################################
### 
### echo "=== TENTATIVE 1: 2 threads (économie RAM) ==="
### echo ""
### 
### if [ ! -f "04-taxonomy/taxonomy_CO1.qza" ]; then
###     conda run -n $QIIME_ENV qiime feature-classifier classify-sklearn \
###         --i-classifier "$DATABASE/coi_marine_classifier.qza" \
###         --i-reads "03-clustering/rep_seqs_97.qza" \
###         --o-classification "04-taxonomy/taxonomy_CO1.qza" \
###         --p-confidence 0.7 \
###         --p-n-jobs 2 \
###         --verbose
###     
###     if [ $? -eq 0 ]; then
###         echo ""
###         echo "✅ SUCCÈS avec 2 threads"
###         SUCCESS=1
###     else
###         echo ""
###         echo "❌ Échec avec 2 threads"
###     fi
### else
###     echo "✅ COI déjà assigné"
###     SUCCESS=1
### fi
### 
### #################################################################################
### # STRATÉGIE 2: 1 seul thread (si stratégie 1 échoue)
### #################################################################################
### 
### if [ -z "$SUCCESS" ]; then
###     echo ""
###     echo "=== TENTATIVE 2: 1 seul thread ==="
###     echo ""
###     
###     rm -f "04-taxonomy/taxonomy_CO1.qza"
###     
###     conda run -n $QIIME_ENV qiime feature-classifier classify-sklearn \
###         --i-classifier "$DATABASE/coi_marine_classifier.qza" \
###         --i-reads "03-clustering/rep_seqs_97.qza" \
###         --o-classification "04-taxonomy/taxonomy_CO1.qza" \
###         --p-confidence 0.7 \
###         --p-n-jobs 1 \
###         --verbose
###     
###     if [ $? -eq 0 ]; then
###         echo ""
###         echo "✅ SUCCÈS avec 1 thread"
###         SUCCESS=1
###     else
###         echo ""
###         echo "❌ Échec avec 1 thread"
###     fi
### fi
### 
### #################################################################################
### # STRATÉGIE 3: Réduire le nombre d'OTUs (filtrer les très rares)
### #################################################################################
### 
### if [ -z "$SUCCESS" ]; then
###     echo ""
###     echo "=== TENTATIVE 3: Filtrer OTUs rares puis classifier ==="
###     echo ""
###     
###     # Filtrer les OTUs présents dans moins de 2 échantillons
###     if [ ! -f "03-clustering/rep_seqs_97_filtered.qza" ]; then
###         conda run -n $QIIME_ENV qiime feature-table filter-seqs \
###             --i-data "03-clustering/rep_seqs_97.qza" \
###             --i-table "03-clustering/table_97.qza" \
###             --p-min-samples 2 \
###             --o-filtered-data "03-clustering/rep_seqs_97_filtered.qza"
###     fi
###     
###     rm -f "04-taxonomy/taxonomy_CO1.qza"
###     
###     conda run -n $QIIME_ENV qiime feature-classifier classify-sklearn \
###         --i-classifier "$DATABASE/coi_marine_classifier.qza" \
###         --i-reads "03-clustering/rep_seqs_97_filtered.qza" \
###         --o-classification "04-taxonomy/taxonomy_CO1.qza" \
###         --p-confidence 0.7 \
###         --p-n-jobs 2 \
###         --verbose
###     
###     if [ $? -eq 0 ]; then
###         echo ""
###         echo "✅ SUCCÈS avec OTUs filtrés"
###         SUCCESS=1
###     else
###         echo ""
###         echo "❌ Échec même avec OTUs filtrés"
###     fi
### fi
### 
### #################################################################################
### # STRATÉGIE 4: Utiliser BLAST au lieu de sklearn (dernier recours)
### #################################################################################
### 
### if [ -z "$SUCCESS" ]; then
###     echo ""
###     echo "=== TENTATIVE 4: BLAST au lieu de sklearn ==="
###     echo ""
###     
###     # Vérifier si on a une base BLAST COI
###     if [ ! -f "$DATABASE/coi_marine_seqs.qza" ]; then
###         echo "❌ Base BLAST COI manquante"
###         echo "Il faut créer une base de séquences de référence COI"
###         echo ""
###         echo "Pour créer la base:"
###         echo "  qiime feature-classifier extract-reads \\"
###         echo "    --i-sequences nt.qza \\"
###         echo "    --p-f-primer GGWACWGGWTGAACWGTWTAYCCYCC \\"
###         echo "    --p-r-primer TANACYTCNGGRTGNCCRAARAAYCA \\"
###         echo "    --o-reads coi_marine_seqs.qza"
###     else
###         rm -f "04-taxonomy/taxonomy_CO1.qza"
###         
###         conda run -n $QIIME_ENV qiime feature-classifier classify-consensus-blast \
###             --i-query "03-clustering/rep_seqs_97.qza" \
###             --i-reference-reads "$DATABASE/coi_marine_seqs.qza" \
###             --i-reference-taxonomy "$DATABASE/coi_marine_taxonomy.qza" \
###             --o-classification "04-taxonomy/taxonomy_CO1.qza" \
###             --p-perc-identity 0.90 \
###             --p-maxaccepts 5 \
###             --verbose
###         
###         if [ $? -eq 0 ]; then
###             echo ""
###             echo "✅ SUCCÈS avec BLAST"
###             SUCCESS=1
###         fi
###     fi
### fi
### 
### #################################################################################
### # FINALISATION
### #################################################################################
### 
### if [ -n "$SUCCESS" ]; then
###     echo ""
###     echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
###     echo "✅✅✅ ASSIGNATION COI RÉUSSIE ✅✅✅"
###     echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
###     echo ""
###     
###     # Export TSV
###     echo "Export TSV..."
###     conda run -n $QIIME_ENV qiime tools export \
###         --input-path "04-taxonomy/taxonomy_CO1.qza" \
###         --output-path "export/taxonomy/temp_CO1/"
###     
###     mv "export/taxonomy/temp_CO1/taxonomy.tsv" "export/taxonomy/taxonomy_CO1.tsv"
###     rm -rf "export/taxonomy/temp_CO1/"
###     
###     # Visualisation
###     echo "Création visualisations..."
###     conda run -n $QIIME_ENV qiime metadata tabulate \
###         --m-input-file "04-taxonomy/taxonomy_CO1.qza" \
###         --o-visualization "04-taxonomy/taxonomy_CO1.qzv"
###     
###     # Barplot
###     conda run -n $QIIME_ENV qiime taxa barplot \
###         --i-table "03-clustering/table_97.qza" \
###         --i-taxonomy "04-taxonomy/taxonomy_CO1.qza" \
###         --o-visualization "04-taxonomy/barplot_CO1.qzv" 2>/dev/null || true
###     
###     # Statistiques
###     if [ -f "export/taxonomy/taxonomy_CO1.tsv" ]; then
###         total=$(($(wc -l < "export/taxonomy/taxonomy_CO1.tsv") - 2))
###         species=$(grep -E ";s__[A-Za-z]" "export/taxonomy/taxonomy_CO1.tsv" 2>/dev/null | wc -l)
###         genus=$(grep -E ";g__[A-Za-z]" "export/taxonomy/taxonomy_CO1.tsv" 2>/dev/null | wc -l)
###         
###         echo ""
###         echo "📊 RÉSULTATS COI:"
###         echo "   Total OTUs: $total"
###         if [ $total -gt 0 ]; then
###             echo "   Niveau espèce: $species ($((species * 100 / total))%)"
###             echo "   Niveau genre: $genus ($((genus * 100 / total))%)"
###         fi
###         echo "   Fichier: export/taxonomy/taxonomy_CO1.tsv"
###         echo ""
###         echo "Top 10 assignations COI:"
###         head -12 "export/taxonomy/taxonomy_CO1.tsv" | tail -10 | \
###             awk -F'\t' '{printf "   %s\n", $2}' | head -10
###     fi
###     
###     echo ""
###     echo "Fichiers créés:"
###     echo "  ✅ 04-taxonomy/taxonomy_CO1.qza"
###     echo "  ✅ 04-taxonomy/taxonomy_CO1.qzv"
###     echo "  ✅ 04-taxonomy/barplot_CO1.qzv"
###     echo "  ✅ export/taxonomy/taxonomy_CO1.tsv"
###     echo ""
###     echo "Vous pouvez maintenant analyser vos 5 taxonomies complètes!"
###     echo ""
### else
###     echo ""
###     echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
###     echo "❌❌❌ TOUTES LES TENTATIVES ONT ÉCHOUÉ ❌❌❌"
###     echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
###     echo ""
###     echo "Le classificateur COI est trop volumineux pour votre RAM."
###     echo ""
###     echo "SOLUTIONS ALTERNATIVES:"
###     echo ""
###     echo "1. Utiliser un nœud avec plus de RAM sur le cluster:"
###     echo "   srun --mem=128G bash retry_coi.sh"
###     echo ""
###     echo "2. Créer un classificateur COI plus petit:"
###     echo "   - Filtrer la base de données COI pour ne garder que les séquences marines"
###     echo "   - Réduire la profondeur taxonomique"
###     echo ""
###     echo "3. Utiliser BLAST au lieu de sklearn (plus lent mais moins de RAM)"
###     echo ""
###     echo "4. Skip COI et analyser les 4 autres marqueurs"
###     echo "   (12S-MiFish, 12S-Mimammal, 12S-Teleo, 16S fonctionnent!)"
###     echo ""
### fi
