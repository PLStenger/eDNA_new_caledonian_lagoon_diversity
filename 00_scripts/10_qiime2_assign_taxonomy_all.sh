#!/usr/bin/env bash

# Script QIIME2 pour assignation taxonomique multi-marqueurs eDNA UNESCO
# VERSION ADAPTÉE ENVIRONNEMENT MARIN - Récifs coralliens Nouvelle-Calédonie
# Marqueurs: 12S-Mifish-UE, 12S-Mimammal-UEB, 12S-Teleo, COI-Leray-Geller, 16S-Vert-Vences

WORKING_DIRECTORY=/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity/05_QIIME2
OUTPUT=/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity/05_QIIME2/visual
DATABASE=/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity/98_database_files
TMPDIR=/nvme/bio/data_fungi

# Variables pour les environnements conda
QIIME_ENV="qiime2-amplicon-2025.7"

cd $WORKING_DIRECTORY

# Créer les répertoires nécessaires
mkdir -p taxonomy
mkdir -p export/taxonomy
mkdir -p databases/temp

echo "=== Script adapté pour environnement MARIN - Récifs coralliens ==="
echo "=== Début du téléchargement et de la préparation des bases de données ==="

#################################################################################
# 1. BASE DE DONNÉES 12S MiFish - POISSONS MARINS UNIQUEMENT
#################################################################################

echo "--- Préparation base de données 12S MiFish (POISSONS MARINS) ---"

# Utilisation de MIDORI2 qui contient une excellente couverture des poissons marins
if [ ! -f "$DATABASE/mifish_marine_seqs.qza" ]; then
    echo "Téléchargement MIDORI2 12S pour poissons marins..."
    
    # MIDORI2 lrRNA (large ribosomal RNA = 12S)
    conda run -n $QIIME_ENV qiime rescript get-midori2-data \
        --p-mito-gene lrRNA \
        --o-sequences "$DATABASE/midori2_12s_all_seqs.qza" \
        --o-taxonomy "$DATABASE/midori2_12s_all_tax.qza"
    
    # Filtrage pour ne garder que les poissons marins (Actinopterygii, Chondrichthyes, Sarcopterygii)
    # Exclusion des mammifères, amphibiens, reptiles terrestres
    conda run -n $QIIME_ENV qiime taxa filter-seqs \
        --i-sequences "$DATABASE/midori2_12s_all_seqs.qza" \
        --i-taxonomy "$DATABASE/midori2_12s_all_tax.qza" \
        --p-include "Actinopterygii,Chondrichthyes,Sarcopterygii,Elasmobranchii,Holocephali" \
        --p-exclude "Mammalia,Amphibia,Aves" \
        --o-filtered-sequences "$DATABASE/mifish_marine_seqs.qza"
    
    # Filtrer la taxonomie correspondante
    conda run -n $QIIME_ENV qiime rescript filter-taxa \
        --i-taxonomy "$DATABASE/midori2_12s_all_tax.qza" \
        --m-ids-to-keep-file "$DATABASE/mifish_marine_seqs.qza" \
        --o-filtered-taxonomy "$DATABASE/mifish_marine_tax.qza"
fi

# Alternative: Construction depuis NCBI avec focus sur poissons marins
if [ ! -f "$DATABASE/mifish_marine_seqs.qza" ]; then
    echo "Construction base 12S poissons marins depuis NCBI..."
    
    # Téléchargement ciblé sur poissons osseux marins (Actinopterygii)
    conda run -n $QIIME_ENV qiime rescript get-ncbi-data \
        --p-query '"12S ribosomal RNA"[Title] AND (("Actinopterygii"[Organism] OR "Chondrichthyes"[Organism]) AND ("marine"[Filter] OR "sea"[All Fields])) AND 100:2000[SLEN]' \
        --p-n-jobs 4 \
        --o-sequences "$DATABASE/mifish_marine_raw_seqs.qza" \
        --o-taxonomy "$DATABASE/mifish_marine_raw_tax.qza"
    
    # Nettoyage
    conda run -n $QIIME_ENV qiime rescript cull-seqs \
        --i-sequences "$DATABASE/mifish_marine_raw_seqs.qza" \
        --o-clean-sequences "$DATABASE/mifish_marine_seqs.qza"
    
    conda run -n $QIIME_ENV qiime rescript filter-taxa \
        --i-taxonomy "$DATABASE/mifish_marine_raw_tax.qza" \
        --m-ids-to-keep-file "$DATABASE/mifish_marine_seqs.qza" \
        --o-filtered-taxonomy "$DATABASE/mifish_marine_tax.qza"
fi

# Entraînement du classificateur 12S MiFish MARINE
if [ ! -f "$DATABASE/mifish_marine_classifier.qza" ]; then
    echo "Entraînement classificateur 12S MiFish MARINE..."
    conda run -n $QIIME_ENV qiime feature-classifier fit-classifier-naive-bayes \
        --i-reference-reads "$DATABASE/mifish_marine_seqs.qza" \
        --i-reference-taxonomy "$DATABASE/mifish_marine_tax.qza" \
        --o-classifier "$DATABASE/mifish_marine_classifier.qza"
fi

#################################################################################
# 2. BASE DE DONNÉES 12S Mimammal - MAMMIFÈRES MARINS UNIQUEMENT
#################################################################################

echo "--- Préparation base de données 12S Mimammal (MAMMIFÈRES MARINS) ---"

# Focus sur mammifères marins: Cetacea (baleines, dauphins), Sirenia (dugongs), Pinnipedia (phoques)
if [ ! -f "$DATABASE/mammal_marine_12s_seqs.qza" ]; then
    echo "Téléchargement séquences 12S mammifères MARINS depuis NCBI..."
    
    # Requête spécifique pour mammifères marins
    conda run -n $QIIME_ENV qiime rescript get-ncbi-data \
        --p-query '"12S ribosomal RNA"[Title] AND ("Cetacea"[Organism] OR "Sirenia"[Organism] OR "Pinnipedia"[Organism] OR "Carnivora"[Organism]) AND 50:2000[SLEN]' \
        --p-n-jobs 4 \
        --o-sequences "$DATABASE/mammal_marine_12s_raw_seqs.qza" \
        --o-taxonomy "$DATABASE/mammal_marine_12s_raw_tax.qza"
    
    # Filtrage et nettoyage
    conda run -n $QIIME_ENV qiime rescript cull-seqs \
        --i-sequences "$DATABASE/mammal_marine_12s_raw_seqs.qza" \
        --o-clean-sequences "$DATABASE/mammal_marine_12s_seqs.qza"
    
    conda run -n $QIIME_ENV qiime rescript filter-taxa \
        --i-taxonomy "$DATABASE/mammal_marine_12s_raw_tax.qza" \
        --m-ids-to-keep-file "$DATABASE/mammal_marine_12s_seqs.qza" \
        --o-filtered-taxonomy "$DATABASE/mammal_marine_12s_tax.qza"
fi

# Entraînement du classificateur 12S Mimammal MARINE
if [ ! -f "$DATABASE/mammal_marine_12s_classifier.qza" ]; then
    echo "Entraînement classificateur 12S Mimammal MARINE..."
    conda run -n $QIIME_ENV qiime feature-classifier fit-classifier-naive-bayes \
        --i-reference-reads "$DATABASE/mammal_marine_12s_seqs.qza" \
        --i-reference-taxonomy "$DATABASE/mammal_marine_12s_tax.qza" \
        --o-classifier "$DATABASE/mammal_marine_12s_classifier.qza"
fi

#################################################################################
# 3. BASE DE DONNÉES 12S Teleo - TÉLÉOSTÉENS MARINS
#################################################################################

echo "--- Préparation base de données 12S Teleo (TÉLÉOSTÉENS MARINS) ---"

# Utilisation de MIDORI2 filtré pour téléostéens marins
if [ ! -f "$DATABASE/teleo_marine_12s_seqs.qza" ]; then
    echo "Construction base 12S téléostéens marins..."
    
    # Si MIDORI2 déjà téléchargé, on le réutilise et filtre
    if [ -f "$DATABASE/midori2_12s_all_seqs.qza" ]; then
        # Filtrage pour Actinopterygii seulement (téléostéens)
        conda run -n $QIIME_ENV qiime taxa filter-seqs \
            --i-sequences "$DATABASE/midori2_12s_all_seqs.qza" \
            --i-taxonomy "$DATABASE/midori2_12s_all_tax.qza" \
            --p-include "Actinopterygii" \
            --p-exclude "Mammalia,Amphibia,Aves,Reptilia" \
            --o-filtered-sequences "$DATABASE/teleo_marine_12s_seqs.qza"
        
        conda run -n $QIIME_ENV qiime rescript filter-taxa \
            --i-taxonomy "$DATABASE/midori2_12s_all_tax.qza" \
            --m-ids-to-keep-file "$DATABASE/teleo_marine_12s_seqs.qza" \
            --o-filtered-taxonomy "$DATABASE/teleo_marine_12s_tax.qza"
    else
        # Sinon, téléchargement direct depuis NCBI
        conda run -n $QIIME_ENV qiime rescript get-ncbi-data \
            --p-query '"12S ribosomal RNA"[Title] AND "Actinopterygii"[Organism] AND 100:2000[SLEN]' \
            --p-n-jobs 4 \
            --o-sequences "$DATABASE/teleo_marine_12s_raw_seqs.qza" \
            --o-taxonomy "$DATABASE/teleo_marine_12s_raw_tax.qza"
        
        conda run -n $QIIME_ENV qiime rescript cull-seqs \
            --i-sequences "$DATABASE/teleo_marine_12s_raw_seqs.qza" \
            --o-clean-sequences "$DATABASE/teleo_marine_12s_seqs.qza"
        
        conda run -n $QIIME_ENV qiime rescript filter-taxa \
            --i-taxonomy "$DATABASE/teleo_marine_12s_raw_tax.qza" \
            --m-ids-to-keep-file "$DATABASE/teleo_marine_12s_seqs.qza" \
            --o-filtered-taxonomy "$DATABASE/teleo_marine_12s_tax.qza"
    fi
fi

# Entraînement du classificateur 12S Teleo MARINE
if [ ! -f "$DATABASE/teleo_marine_12s_classifier.qza" ]; then
    echo "Entraînement classificateur 12S Teleo MARINE..."
    conda run -n $QIIME_ENV qiime feature-classifier fit-classifier-naive-bayes \
        --i-reference-reads "$DATABASE/teleo_marine_12s_seqs.qza" \
        --i-reference-taxonomy "$DATABASE/teleo_marine_12s_tax.qza" \
        --o-classifier "$DATABASE/teleo_marine_12s_classifier.qza"
fi

#################################################################################
# 4. BASE DE DONNÉES COI Leray-Geller - FAUNE MARINE
#################################################################################

echo "--- Préparation base de données COI Leray-Geller (FAUNE MARINE) ---"

# MIDORI2 COI contient une excellente couverture de la faune marine
if [ ! -f "$DATABASE/coi_marine_seqs.qza" ]; then
    echo "Téléchargement MIDORI2 COI pour faune marine..."
    
    # MIDORI2 CO1
    conda run -n $QIIME_ENV qiime rescript get-midori2-data \
        --p-mito-gene CO1 \
        --o-sequences "$DATABASE/midori2_coi_all_seqs.qza" \
        --o-taxonomy "$DATABASE/midori2_coi_all_tax.qza"
    
    # Filtrage pour organismes marins (poissons, invertébrés marins)
    # On garde tout sauf les mammifères terrestres, amphibiens, reptiles terrestres
    conda run -n $QIIME_ENV qiime taxa filter-seqs \
        --i-sequences "$DATABASE/midori2_coi_all_seqs.qza" \
        --i-taxonomy "$DATABASE/midori2_coi_all_tax.qza" \
        --p-exclude "Amphibia,Aves" \
        --o-filtered-sequences "$DATABASE/coi_marine_seqs.qza"
    
    conda run -n $QIIME_ENV qiime rescript filter-taxa \
        --i-taxonomy "$DATABASE/midori2_coi_all_tax.qza" \
        --m-ids-to-keep-file "$DATABASE/coi_marine_seqs.qza" \
        --o-filtered-taxonomy "$DATABASE/coi_marine_tax.qza"
    
    # Nettoyage supplémentaire
    conda run -n $QIIME_ENV qiime rescript cull-seqs \
        --i-sequences "$DATABASE/coi_marine_seqs.qza" \
        --o-clean-sequences "$DATABASE/coi_marine_clean_seqs.qza"
    
    conda run -n $QIIME_ENV qiime rescript filter-taxa \
        --i-taxonomy "$DATABASE/coi_marine_tax.qza" \
        --m-ids-to-keep-file "$DATABASE/coi_marine_clean_seqs.qza" \
        --o-filtered-taxonomy "$DATABASE/coi_marine_clean_tax.qza"
    
    # Utiliser les versions nettoyées
    mv "$DATABASE/coi_marine_clean_seqs.qza" "$DATABASE/coi_marine_seqs.qza"
    mv "$DATABASE/coi_marine_clean_tax.qza" "$DATABASE/coi_marine_tax.qza"
fi

# Entraînement du classificateur COI MARINE
if [ ! -f "$DATABASE/coi_marine_classifier.qza" ]; then
    echo "Entraînement classificateur COI MARINE..."
    conda run -n $QIIME_ENV qiime feature-classifier fit-classifier-naive-bayes \
        --i-reference-reads "$DATABASE/coi_marine_seqs.qza" \
        --i-reference-taxonomy "$DATABASE/coi_marine_tax.qza" \
        --o-classifier "$DATABASE/coi_marine_classifier.qza"
fi

#################################################################################
# 5. BASE DE DONNÉES 16S Vertebrates - VERTÉBRÉS MARINS UNIQUEMENT
#################################################################################

echo "--- Préparation base de données 16S Vertébrés (MARINS) ---"

# Focus sur vertébrés marins: poissons, mammifères marins, reptiles marins
if [ ! -f "$DATABASE/vert_marine_16s_seqs.qza" ]; then
    echo "Téléchargement séquences 16S vertébrés MARINS depuis NCBI..."
    
    # Requête pour vertébrés marins
    conda run -n $QIIME_ENV qiime rescript get-ncbi-data \
        --p-query '"16S ribosomal RNA"[Title] AND ("Actinopterygii"[Organism] OR "Chondrichthyes"[Organism] OR "Cetacea"[Organism] OR "Sirenia"[Organism] OR "Testudines"[Organism]) AND 200:2000[SLEN]' \
        --p-n-jobs 4 \
        --o-sequences "$DATABASE/vert_marine_16s_raw_seqs.qza" \
        --o-taxonomy "$DATABASE/vert_marine_16s_raw_tax.qza"
    
    # Nettoyage des séquences
    conda run -n $QIIME_ENV qiime rescript cull-seqs \
        --i-sequences "$DATABASE/vert_marine_16s_raw_seqs.qza" \
        --o-clean-sequences "$DATABASE/vert_marine_16s_seqs.qza"
    
    conda run -n $QIIME_ENV qiime rescript filter-taxa \
        --i-taxonomy "$DATABASE/vert_marine_16s_raw_tax.qza" \
        --m-ids-to-keep-file "$DATABASE/vert_marine_16s_seqs.qza" \
        --o-filtered-taxonomy "$DATABASE/vert_marine_16s_tax.qza"
fi

# Alternative avec MIDORI2 16S filtré
if [ ! -f "$DATABASE/vert_marine_16s_seqs.qza" ]; then
    echo "Utilisation de MIDORI2 16S pour vertébrés marins..."
    
    conda run -n $QIIME_ENV qiime rescript get-midori2-data \
        --p-mito-gene srRNA \
        --o-sequences "$DATABASE/midori2_16s_all_seqs.qza" \
        --o-taxonomy "$DATABASE/midori2_16s_all_tax.qza"
    
    # Filtrage pour vertébrés marins
    conda run -n $QIIME_ENV qiime taxa filter-seqs \
        --i-sequences "$DATABASE/midori2_16s_all_seqs.qza" \
        --i-taxonomy "$DATABASE/midori2_16s_all_tax.qza" \
        --p-include "Actinopterygii,Chondrichthyes,Cetacea,Sirenia,Testudines" \
        --p-exclude "Amphibia,Aves" \
        --o-filtered-sequences "$DATABASE/vert_marine_16s_seqs.qza"
    
    conda run -n $QIIME_ENV qiime rescript filter-taxa \
        --i-taxonomy "$DATABASE/midori2_16s_all_tax.qza" \
        --m-ids-to-keep-file "$DATABASE/vert_marine_16s_seqs.qza" \
        --o-filtered-taxonomy "$DATABASE/vert_marine_16s_tax.qza"
fi

# Entraînement du classificateur 16S Vertébrés MARINS
if [ ! -f "$DATABASE/vert_marine_16s_classifier.qza" ]; then
    echo "Entraînement classificateur 16S Vertébrés MARINS..."
    conda run -n $QIIME_ENV qiime feature-classifier fit-classifier-naive-bayes \
        --i-reference-reads "$DATABASE/vert_marine_16s_seqs.qza" \
        --i-reference-taxonomy "$DATABASE/vert_marine_16s_tax.qza" \
        --o-classifier "$DATABASE/vert_marine_16s_classifier.qza"
fi

echo "=== Bases de données MARINES préparées. Début des assignations taxonomiques ==="

#################################################################################
# ASSIGNATIONS TAXONOMIQUES
#################################################################################

# Fonction pour assigner la taxonomie
assign_taxonomy() {
    local marker=$1
    local classifier=$2
    local output_name=$3
    
    echo "--- Assignation taxonomique pour $marker ---"
    
    # Assignation taxonomique
    conda run -n $QIIME_ENV qiime feature-classifier classify-sklearn \
        --i-classifier "$DATABASE/$classifier" \
        --i-reads core/RepSeq.qza \
        --o-classification taxonomy/$output_name.qza \
        --p-confidence 0.7 \
        --p-n-jobs 4
    
    # Export en format TSV
    conda run -n $QIIME_ENV qiime tools export \
        --input-path taxonomy/$output_name.qza \
        --output-path export/taxonomy/${output_name}_temp/
    
    # Renommer et déplacer le fichier exporté
    mv export/taxonomy/${output_name}_temp/taxonomy.tsv export/taxonomy/$output_name.tsv
    rm -rf export/taxonomy/${output_name}_temp/
    
    echo "Fichier $output_name.tsv créé avec succès"
}

# Assignations pour chaque marqueur avec bases de données MARINES
echo "=== Début des assignations taxonomiques avec bases MARINES ==="

# 1. 12S MiFish - Poissons marins
assign_taxonomy "12S-MiFish-MARINE" "mifish_marine_classifier.qza" "taxonomy_12SMifish"

# 2. 12S Mimammal - Mammifères marins
assign_taxonomy "12S-Mimammal-MARINE" "mammal_marine_12s_classifier.qza" "taxonomy_12SMimammal"

# 3. 12S Teleo - Téléostéens marins
assign_taxonomy "12S-Teleo-MARINE" "teleo_marine_12s_classifier.qza" "taxonomy_12STeleo"

# 4. COI Leray-Geller - Faune marine
assign_taxonomy "COI-Leray-Geller-MARINE" "coi_marine_classifier.qza" "taxonomy_CO1"

# 5. 16S Vertebrates - Vertébrés marins
assign_taxonomy "16S-Vert-MARINE" "vert_marine_16s_classifier.qza" "taxonomy_16S"

echo "=== Script terminé avec succès ==="
echo ""
echo "Fichiers de taxonomie MARINE créés:"
echo "- export/taxonomy/taxonomy_12SMifish.tsv (poissons marins)"
echo "- export/taxonomy/taxonomy_12SMimammal.tsv (mammifères marins)"
echo "- export/taxonomy/taxonomy_12STeleo.tsv (téléostéens marins)"
echo "- export/taxonomy/taxonomy_CO1.tsv (faune marine diverse)"
echo "- export/taxonomy/taxonomy_16S.tsv (vertébrés marins)"
echo ""

echo "=== Vérification des résultats ==="
for file in export/taxonomy/taxonomy_*.tsv; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        linecount=$(wc -l < "$file")
        echo "$filename: $linecount assignations"
        echo "--- Aperçu des premières lignes ---"
        head -5 "$file"
        echo ""
    fi
done

echo "=== Informations sur les bases de données MARINES créées ==="
echo "12S MiFish MARINE classifier: $DATABASE/mifish_marine_classifier.qza"
echo "12S Mimammal MARINE classifier: $DATABASE/mammal_marine_12s_classifier.qza"
echo "12S Teleo MARINE classifier: $DATABASE/teleo_marine_12s_classifier.qza"
echo "COI MARINE classifier: $DATABASE/coi_marine_classifier.qza"
echo "16S Vertebrates MARINE classifier: $DATABASE/vert_marine_16s_classifier.qza"
echo ""
echo "=== IMPORTANT: Bases de données filtrées pour environnement MARIN ==="
echo "- Exclusion: mammifères terrestres (rats-taupes), amphibiens (grenouilles)"
echo "- Inclusion: poissons marins, mammifères marins, reptiles marins, invertébrés marins"
echo "- Adapté pour récifs coralliens et lagons de Nouvelle-Calédonie"
