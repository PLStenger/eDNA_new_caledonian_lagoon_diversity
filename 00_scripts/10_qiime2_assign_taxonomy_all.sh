#!/usr/bin/env bash

# Script QIIME2 pour assignation taxonomique multi-marqueurs eDNA UNESCO
# Marqueurs: 12S-Mifish-UE, 12S-Mimammal-UEB, 12S-Teleo, COI-Leray-Geller, 16S-Vert-Vences
# Auteur: Script généré pour analyse eDNA New Caledonian lagoon diversity

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

echo "=== Début du téléchargement et de la préparation des bases de données ==="

#################################################################################
# 1. BASE DE DONNÉES 12S MiFish (poissons marins et d'eau douce)
#################################################################################

echo "--- Préparation base de données 12S MiFish ---"

# Téléchargement Mare-MAGE database (spécialisée pour les poissons 12S)
if [ ! -f "$DATABASE/mare_mage_12s_sequences.fasta" ]; then
    echo "Téléchargement Mare-MAGE 12S database..."
    wget -O "$DATABASE/mare_mage_12s_sequences.fasta" "https://mare-mage.weebly.com/uploads/1/3/1/4/131413778/12sdb-all.fasta"
    wget -O "$DATABASE/mare_mage_12s_taxonomy.txt" "https://mare-mage.weebly.com/uploads/1/3/1/4/131413778/12sdb-all_tax.txt"
fi

# Alternative: Utilisation de MIDORI2 pour 12S si Mare-MAGE non disponible
if [ ! -f "$DATABASE/mare_mage_12s_sequences.fasta" ]; then
    echo "Téléchargement MIDORI2 12S database..."
    wget -O "$DATABASE/midori2_12s.fasta.gz" "http://www.reference-midori.info/download/Databases/GenBank254/QIIME2_sp/MIDORI2_UNIQ_SP_NUC_GB254_12S_QIIME.fasta.gz"
    wget -O "$DATABASE/midori2_12s_taxonomy.txt.gz" "http://www.reference-midori.info/download/Databases/GenBank254/QIIME2_sp/MIDORI2_UNIQ_SP_NUC_GB254_12S_QIIME_taxonomy.txt.gz"
    gunzip "$DATABASE/midori2_12s.fasta.gz"
    gunzip "$DATABASE/midori2_12s_taxonomy.txt.gz"
fi

# Import des séquences 12S MiFish dans QIIME2
if [ ! -f "$DATABASE/mifish_12s_seqs.qza" ]; then
    conda run -n $QIIME_ENV qiime tools import \
        --type 'FeatureData[Sequence]' \
        --input-path "$DATABASE/mare_mage_12s_sequences.fasta" \
        --output-path "$DATABASE/mifish_12s_seqs.qza"
    
    conda run -n $QIIME_ENV qiime tools import \
        --type 'FeatureData[Taxonomy]' \
        --input-format HeaderlessTSVTaxonomyFormat \
        --input-path "$DATABASE/mare_mage_12s_taxonomy.txt" \
        --output-path "$DATABASE/mifish_12s_tax.qza"
fi

# Entraînement du classificateur 12S MiFish
if [ ! -f "$DATABASE/mifish_12s_classifier.qza" ]; then
    echo "Entraînement classificateur 12S MiFish..."
    conda run -n $QIIME_ENV qiime feature-classifier fit-classifier-naive-bayes \
        --i-reference-reads "$DATABASE/mifish_12s_seqs.qza" \
        --i-reference-taxonomy "$DATABASE/mifish_12s_tax.qza" \
        --o-classifier "$DATABASE/mifish_12s_classifier.qza"
fi

#################################################################################
# 2. BASE DE DONNÉES 12S Mimammal (mammifères)
#################################################################################

echo "--- Préparation base de données 12S Mimammal ---"

# Utilisation de RESCRIPt pour télécharger les séquences 12S de mammifères depuis NCBI
if [ ! -f "$DATABASE/mammal_12s_seqs.qza" ]; then
    echo "Téléchargement séquences 12S mammifères depuis NCBI..."
    conda run -n $QIIME_ENV qiime rescript get-ncbi-data \
        --p-query '"12S"[Gene] AND "Mammalia"[Organism] AND 50:2000[SLEN]' \
        --p-n-jobs 4 \
        --o-sequences "$DATABASE/mammal_12s_raw_seqs.qza" \
        --o-taxonomy "$DATABASE/mammal_12s_raw_tax.qza"
    
    # Filtrage et nettoyage
    conda run -n $QIIME_ENV qiime rescript cull-seqs \
        --i-sequences "$DATABASE/mammal_12s_raw_seqs.qza" \
        --o-clean-sequences "$DATABASE/mammal_12s_seqs.qza"
    
    conda run -n $QIIME_ENV qiime rescript filter-taxa \
        --i-taxonomy "$DATABASE/mammal_12s_raw_tax.qza" \
        --m-ids-to-keep-file "$DATABASE/mammal_12s_seqs.qza" \
        --o-filtered-taxonomy "$DATABASE/mammal_12s_tax.qza"
fi

# Entraînement du classificateur 12S Mimammal
if [ ! -f "$DATABASE/mammal_12s_classifier.qza" ]; then
    echo "Entraînement classificateur 12S Mimammal..."
    conda run -n $QIIME_ENV qiime feature-classifier fit-classifier-naive-bayes \
        --i-reference-reads "$DATABASE/mammal_12s_seqs.qza" \
        --i-reference-taxonomy "$DATABASE/mammal_12s_tax.qza" \
        --o-classifier "$DATABASE/mammal_12s_classifier.qza"
fi

#################################################################################
# 3. BASE DE DONNÉES 12S Teleo (téléostéens)
#################################################################################

echo "--- Préparation base de données 12S Teleo ---"

# Utilisation de Mare-MAGE spécifiquement pour les téléostéens
if [ ! -f "$DATABASE/teleo_12s_seqs.qza" ]; then
    # Filtrage des séquences Mare-MAGE pour les téléostéens
    conda run -n $QIIME_ENV qiime rescript get-ncbi-data \
        --p-query '"12S"[Gene] AND "Teleostei"[Organism] AND 50:2000[SLEN]' \
        --p-n-jobs 4 \
        --o-sequences "$DATABASE/teleo_12s_raw_seqs.qza" \
        --o-taxonomy "$DATABASE/teleo_12s_raw_tax.qza"
    
    # Nettoyage des séquences
    conda run -n $QIIME_ENV qiime rescript cull-seqs \
        --i-sequences "$DATABASE/teleo_12s_raw_seqs.qza" \
        --o-clean-sequences "$DATABASE/teleo_12s_seqs.qza"
    
    conda run -n $QIIME_ENV qiime rescript filter-taxa \
        --i-taxonomy "$DATABASE/teleo_12s_raw_tax.qza" \
        --m-ids-to-keep-file "$DATABASE/teleo_12s_seqs.qza" \
        --o-filtered-taxonomy "$DATABASE/teleo_12s_tax.qza"
fi

# Entraînement du classificateur 12S Teleo
if [ ! -f "$DATABASE/teleo_12s_classifier.qza" ]; then
    echo "Entraînement classificateur 12S Teleo..."
    conda run -n $QIIME_ENV qiime feature-classifier fit-classifier-naive-bayes \
        --i-reference-reads "$DATABASE/teleo_12s_seqs.qza" \
        --i-reference-taxonomy "$DATABASE/teleo_12s_tax.qza" \
        --o-classifier "$DATABASE/teleo_12s_classifier.qza"
fi

#################################################################################
# 4. BASE DE DONNÉES COI Leray-Geller
#################################################################################

echo "--- Préparation base de données COI Leray-Geller ---"

# Téléchargement Mare-MAGE COI database
if [ ! -f "$DATABASE/mare_mage_coi_sequences.fasta" ]; then
    echo "Téléchargement Mare-MAGE COI database..."
    wget -O "$DATABASE/mare_mage_coi_sequences.fasta" "https://mare-mage.weebly.com/uploads/1/3/1/4/131413778/coidb-all.fasta"
    wget -O "$DATABASE/mare_mage_coi_taxonomy.txt" "https://mare-mage.weebly.com/uploads/1/3/1/4/131413778/coidb-all_tax.txt"
fi

# Alternative: MIDORI2 COI database
if [ ! -f "$DATABASE/mare_mage_coi_sequences.fasta" ]; then
    echo "Téléchargement MIDORI2 COI database..."
    wget -O "$DATABASE/midori2_coi.fasta.gz" "http://www.reference-midori.info/download/Databases/GenBank254/QIIME2_sp/MIDORI2_UNIQ_SP_NUC_GB254_COI_QIIME.fasta.gz"
    wget -O "$DATABASE/midori2_coi_taxonomy.txt.gz" "http://www.reference-midori.info/download/Databases/GenBank254/QIIME2_sp/MIDORI2_UNIQ_SP_NUC_GB254_COI_QIIME_taxonomy.txt.gz"
    gunzip "$DATABASE/midori2_coi.fasta.gz"
    gunzip "$DATABASE/midori2_coi_taxonomy.txt.gz"
fi

# Import des séquences COI dans QIIME2
if [ ! -f "$DATABASE/coi_seqs.qza" ]; then
    conda run -n $QIIME_ENV qiime tools import \
        --type 'FeatureData[Sequence]' \
        --input-path "$DATABASE/mare_mage_coi_sequences.fasta" \
        --output-path "$DATABASE/coi_seqs.qza"
    
    conda run -n $QIIME_ENV qiime tools import \
        --type 'FeatureData[Taxonomy]' \
        --input-format HeaderlessTSVTaxonomyFormat \
        --input-path "$DATABASE/mare_mage_coi_taxonomy.txt" \
        --output-path "$DATABASE/coi_tax.qza"
fi

# Entraînement du classificateur COI
if [ ! -f "$DATABASE/coi_classifier.qza" ]; then
    echo "Entraînement classificateur COI..."
    conda run -n $QIIME_ENV qiime feature-classifier fit-classifier-naive-bayes \
        --i-reference-reads "$DATABASE/coi_seqs.qza" \
        --i-reference-taxonomy "$DATABASE/coi_tax.qza" \
        --o-classifier "$DATABASE/coi_classifier.qza"
fi

#################################################################################
# 5. BASE DE DONNÉES 16S Vertebrates (Vences)
#################################################################################

echo "--- Préparation base de données 16S Vertébrés ---"

# Téléchargement des séquences 16S de vertébrés depuis NCBI
if [ ! -f "$DATABASE/vert_16s_seqs.qza" ]; then
    echo "Téléchargement séquences 16S vertébrés depuis NCBI..."
    conda run -n $QIIME_ENV qiime rescript get-ncbi-data \
        --p-query '"16S"[Gene] AND "Vertebrata"[Organism] AND 200:2000[SLEN]' \
        --p-n-jobs 4 \
        --o-sequences "$DATABASE/vert_16s_raw_seqs.qza" \
        --o-taxonomy "$DATABASE/vert_16s_raw_tax.qza"
    
    # Nettoyage des séquences
    conda run -n $QIIME_ENV qiime rescript cull-seqs \
        --i-sequences "$DATABASE/vert_16s_raw_seqs.qza" \
        --o-clean-sequences "$DATABASE/vert_16s_seqs.qza"
    
    conda run -n $QIIME_ENV qiime rescript filter-taxa \
        --i-taxonomy "$DATABASE/vert_16s_raw_tax.qza" \
        --m-ids-to-keep-file "$DATABASE/vert_16s_seqs.qza" \
        --o-filtered-taxonomy "$DATABASE/vert_16s_tax.qza"
fi

# Entraînement du classificateur 16S Vertébrés
if [ ! -f "$DATABASE/vert_16s_classifier.qza" ]; then
    echo "Entraînement classificateur 16S Vertébrés..."
    conda run -n $QIIME_ENV qiime feature-classifier fit-classifier-naive-bayes \
        --i-reference-reads "$DATABASE/vert_16s_seqs.qza" \
        --i-reference-taxonomy "$DATABASE/vert_16s_tax.qza" \
        --o-classifier "$DATABASE/vert_16s_classifier.qza"
fi

echo "=== Bases de données préparées. Début des assignations taxonomiques ==="

#################################################################################
# ASSIGNATIONS TAXONOMIQUES
#################################################################################

# Fonction pour extraire les séquences d'un marqueur spécifique
extract_marker_sequences() {
    local marker=$1
    local classifier=$2
    local output_name=$3
    
    echo "--- Assignation taxonomique pour $marker ---"
    
    # Ici, vous devrez adapter cette partie selon la façon dont vos séquences
    # sont organisées dans RepSeq.qza. Cette partie assume que vous avez un moyen
    # de filtrer les séquences par marqueur.
    
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
        --output-path export/taxonomy/
    
    # Renommer le fichier exporté
    mv export/taxonomy/taxonomy.tsv export/taxonomy/$output_name.tsv
    
    echo "Fichier $output_name.tsv créé avec succès"
}

# Note: Pour séparer les séquences par marqueur, vous devrez probablement
# utiliser les métadonnées ou les identifiants de séquences qui indiquent
# quel marqueur a été utilisé. Voici un exemple de comment vous pourriez
# filtrer les séquences:

# Si vos séquences ont des identifiants qui contiennent le nom du marqueur:
filter_sequences_by_marker() {
    local marker_pattern=$1
    local output_file=$2
    
    conda run -n $QIIME_ENV qiime feature-table filter-features \
        --i-table core/RepSeq.qza \
        --p-where "feature_id LIKE '%$marker_pattern%'" \
        --o-filtered-table $output_file
}

# Assignations pour chaque marqueur
echo "=== Début des assignations taxonomiques ==="

# 1. 12S MiFish
extract_marker_sequences "12S-MiFish" "mifish_12s_classifier.qza" "taxonomy_12SMifish"

# 2. 12S Mimammal  
extract_marker_sequences "12S-Mimammal" "mammal_12s_classifier.qza" "taxonomy_12SMimammal"

# 3. 12S Teleo
extract_marker_sequences "12S-Teleo" "teleo_12s_classifier.qza" "taxonomy_12STeleo"

# 4. COI Leray-Geller
extract_marker_sequences "COI-Leray-Geller" "coi_classifier.qza" "taxonomy_CO1"

# 5. 16S Vertebrates
extract_marker_sequences "16S-Vert" "vert_16s_classifier.qza" "taxonomy_16S"

echo "=== Script terminé avec succès ==="
echo "Fichiers de taxonomie créés:"
echo "- taxonomy_12SMifish.tsv"
echo "- taxonomy_12SMimammal.tsv" 
echo "- taxonomy_12STeleo.tsv"
echo "- taxonomy_CO1.tsv"
echo "- taxonomy_16S.tsv"

echo "=== Vérification des résultats ==="
for file in export/taxonomy/taxonomy_*.tsv; do
    if [ -f "$file" ]; then
        echo "$file: $(wc -l < "$file") assignations"
        head -5 "$file"
        echo "---"
    fi
done
