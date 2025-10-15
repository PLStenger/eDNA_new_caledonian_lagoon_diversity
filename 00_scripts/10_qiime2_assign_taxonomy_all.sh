#!/usr/bin/env bash

# Script QIIME2 FINAL avec extraction TSV automatique
# VERSION OPTIMISÉE pour taxonomie jusqu'au niveau ESPÈCE
# Environnement marin - Récifs coralliens Nouvelle-Calédonie

WORKING_DIRECTORY=/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity/05_QIIME2
OUTPUT=/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity/05_QIIME2/visual
DATABASE=/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity/98_database_files
TMPDIR=/nvme/bio/data_fungi

QIIME_ENV="qiime2-amplicon-2025.7"

cd $WORKING_DIRECTORY

mkdir -p taxonomy
mkdir -p taxonomy/qzv_extracted
mkdir -p export/taxonomy
mkdir -p databases/temp

echo "=== Script OPTIMISÉ pour résolution taxonomique ESPÈCE ==="
echo "=== Environnement MARIN - Récifs coralliens Nouvelle-Calédonie ==="

#################################################################################
# FONCTION D'EXTRACTION TSV AUTOMATIQUE
#################################################################################

extract_tsv_from_taxonomy() {
    local taxonomy_qza=$1
    local output_basename=$2
    
    echo "Extraction TSV pour $output_basename..."
    
    # Créer visualisation
    conda run -n $QIIME_ENV qiime metadata tabulate \
        --m-input-file "$taxonomy_qza" \
        --o-visualization "taxonomy/${output_basename}.qzv"
    
    # Extraire le QZV
    unzip -q "taxonomy/${output_basename}.qzv" -d "taxonomy/qzv_extracted/${output_basename}/"
    
    # Copier le fichier metadata.tsv vers le bon endroit
    cp "taxonomy/qzv_extracted/${output_basename}/*/data/metadata.tsv" "export/taxonomy/${output_basename}.tsv"
    
    echo "✓ Fichier TSV créé: export/taxonomy/${output_basename}.tsv"
}

#################################################################################
# 1. BASE DE DONNÉES 12S MiFish - POISSONS MARINS avec RÉSOLUTION ESPÈCE
#################################################################################

echo "--- Préparation base de données 12S MiFish (POISSONS MARINS - niveau espèce) ---"

if [ ! -f "$DATABASE/mifish_marine_classifier.qza" ]; then
    echo "Téléchargement séquences 12S poissons marins depuis NCBI..."
    
    # Requête élargie pour obtenir plus de séquences avec taxonomie complète
    conda run -n $QIIME_ENV qiime rescript get-ncbi-data \
        --p-query '"12S ribosomal RNA"[Title] AND ("Actinopterygii"[Organism] OR "Chondrichthyes"[Organism] OR "Elasmobranchii"[Organism]) AND 100:2000[SLEN] NOT "environmental"[Title] NOT "uncultured"[Title]' \
        --p-n-jobs 4 \
        --p-rank-propagation \
        --o-sequences "$DATABASE/mifish_marine_raw_seqs.qza" \
        --o-taxonomy "$DATABASE/mifish_marine_raw_tax.qza"
    
    # Déreplicate avec "uniq" pour préserver toutes les informations taxonomiques
    echo "Déréplication avec préservation taxonomique..."
    conda run -n $QIIME_ENV qiime rescript dereplicate \
        --i-sequences "$DATABASE/mifish_marine_raw_seqs.qza" \
        --i-taxa "$DATABASE/mifish_marine_raw_tax.qza" \
        --p-mode 'uniq' \
        --p-derep-prefix \
        --o-dereplicated-sequences "$DATABASE/mifish_marine_derep_seqs.qza" \
        --o-dereplicated-taxa "$DATABASE/mifish_marine_derep_tax.qza"
    
    # Nettoyage des séquences
    conda run -n $QIIME_ENV qiime rescript cull-seqs \
        --i-sequences "$DATABASE/mifish_marine_derep_seqs.qza" \
        --o-clean-sequences "$DATABASE/mifish_marine_seqs.qza"
    
    # Filtrer taxonomie correspondante
    conda run -n $QIIME_ENV qiime rescript filter-taxa \
        --i-taxonomy "$DATABASE/mifish_marine_derep_tax.qza" \
        --m-ids-to-keep-file "$DATABASE/mifish_marine_seqs.qza" \
        --o-filtered-taxonomy "$DATABASE/mifish_marine_tax.qza"
    
    echo "Entraînement classificateur 12S MiFish MARINE..."
    conda run -n $QIIME_ENV qiime feature-classifier fit-classifier-naive-bayes \
        --i-reference-reads "$DATABASE/mifish_marine_seqs.qza" \
        --i-reference-taxonomy "$DATABASE/mifish_marine_tax.qza" \
        --o-classifier "$DATABASE/mifish_marine_classifier.qza"
fi

#################################################################################
# 2. BASE DE DONNÉES 12S Mimammal - MAMMIFÈRES MARINS avec RÉSOLUTION ESPÈCE
#################################################################################

echo "--- Préparation base de données 12S Mimammal (MAMMIFÈRES MARINS - niveau espèce) ---"

if [ ! -f "$DATABASE/mammal_marine_12s_classifier.qza" ]; then
    echo "Téléchargement séquences 12S mammifères MARINS depuis NCBI..."
    
    conda run -n $QIIME_ENV qiime rescript get-ncbi-data \
        --p-query '"12S ribosomal RNA"[Title] AND ("Cetacea"[Organism] OR "Sirenia"[Organism] OR "Pinnipedia"[Organism] OR "Phocidae"[Organism] OR "Otariidae"[Organism] OR "Odobenidae"[Organism]) AND 50:2000[SLEN] NOT "environmental"[Title]' \
        --p-n-jobs 4 \
        --p-rank-propagation \
        --o-sequences "$DATABASE/mammal_marine_12s_raw_seqs.qza" \
        --o-taxonomy "$DATABASE/mammal_marine_12s_raw_tax.qza"
    
    conda run -n $QIIME_ENV qiime rescript dereplicate \
        --i-sequences "$DATABASE/mammal_marine_12s_raw_seqs.qza" \
        --i-taxa "$DATABASE/mammal_marine_12s_raw_tax.qza" \
        --p-mode 'uniq' \
        --p-derep-prefix \
        --o-dereplicated-sequences "$DATABASE/mammal_marine_12s_derep_seqs.qza" \
        --o-dereplicated-taxa "$DATABASE/mammal_marine_12s_derep_tax.qza"
    
    conda run -n $QIIME_ENV qiime rescript cull-seqs \
        --i-sequences "$DATABASE/mammal_marine_12s_derep_seqs.qza" \
        --o-clean-sequences "$DATABASE/mammal_marine_12s_seqs.qza"
    
    conda run -n $QIIME_ENV qiime rescript filter-taxa \
        --i-taxonomy "$DATABASE/mammal_marine_12s_derep_tax.qza" \
        --m-ids-to-keep-file "$DATABASE/mammal_marine_12s_seqs.qza" \
        --o-filtered-taxonomy "$DATABASE/mammal_marine_12s_tax.qza"
    
    echo "Entraînement classificateur 12S Mimammal MARINE..."
    conda run -n $QIIME_ENV qiime feature-classifier fit-classifier-naive-bayes \
        --i-reference-reads "$DATABASE/mammal_marine_12s_seqs.qza" \
        --i-reference-taxonomy "$DATABASE/mammal_marine_12s_tax.qza" \
        --o-classifier "$DATABASE/mammal_marine_12s_classifier.qza"
fi

#################################################################################
# 3. BASE DE DONNÉES 12S Teleo - TÉLÉOSTÉENS MARINS avec RÉSOLUTION ESPÈCE
#################################################################################

echo "--- Préparation base de données 12S Teleo (TÉLÉOSTÉENS MARINS - niveau espèce) ---"

if [ ! -f "$DATABASE/teleo_marine_12s_classifier.qza" ]; then
    echo "Téléchargement séquences 12S Actinopterygii depuis NCBI..."
    
    conda run -n $QIIME_ENV qiime rescript get-ncbi-data \
        --p-query '"12S ribosomal RNA"[Title] AND "Actinopterygii"[Organism] AND 100:2000[SLEN] NOT "environmental"[Title] NOT "uncultured"[Title]' \
        --p-n-jobs 4 \
        --p-rank-propagation \
        --o-sequences "$DATABASE/teleo_marine_12s_raw_seqs.qza" \
        --o-taxonomy "$DATABASE/teleo_marine_12s_raw_tax.qza"
    
    conda run -n $QIIME_ENV qiime rescript dereplicate \
        --i-sequences "$DATABASE/teleo_marine_12s_raw_seqs.qza" \
        --i-taxa "$DATABASE/teleo_marine_12s_raw_tax.qza" \
        --p-mode 'uniq' \
        --p-derep-prefix \
        --o-dereplicated-sequences "$DATABASE/teleo_marine_12s_derep_seqs.qza" \
        --o-dereplicated-taxa "$DATABASE/teleo_marine_12s_derep_tax.qza"
    
    conda run -n $QIIME_ENV qiime rescript cull-seqs \
        --i-sequences "$DATABASE/teleo_marine_12s_derep_seqs.qza" \
        --o-clean-sequences "$DATABASE/teleo_marine_12s_seqs.qza"
    
    conda run -n $QIIME_ENV qiime rescript filter-taxa \
        --i-taxonomy "$DATABASE/teleo_marine_12s_derep_tax.qza" \
        --m-ids-to-keep-file "$DATABASE/teleo_marine_12s_seqs.qza" \
        --o-filtered-taxonomy "$DATABASE/teleo_marine_12s_tax.qza"
    
    echo "Entraînement classificateur 12S Teleo MARINE..."
    conda run -n $QIIME_ENV qiime feature-classifier fit-classifier-naive-bayes \
        --i-reference-reads "$DATABASE/teleo_marine_12s_seqs.qza" \
        --i-reference-taxonomy "$DATABASE/teleo_marine_12s_tax.qza" \
        --o-classifier "$DATABASE/teleo_marine_12s_classifier.qza"
fi

#################################################################################
# 4. BASE DE DONNÉES COI Leray-Geller - FAUNE MARINE avec RÉSOLUTION ESPÈCE
#################################################################################

echo "--- Préparation base de données COI Leray-Geller (FAUNE MARINE - niveau espèce) ---"

if [ ! -f "$DATABASE/coi_marine_classifier.qza" ]; then
    echo "Téléchargement séquences COI faune marine depuis NCBI..."
    
    conda run -n $QIIME_ENV qiime rescript get-ncbi-data \
        --p-query '"cytochrome c oxidase subunit I"[Title] OR "cytochrome oxidase subunit 1"[Title] AND ("Actinopterygii"[Organism] OR "Chondrichthyes"[Organism] OR "Mollusca"[Organism] OR "Arthropoda"[Organism] OR "Cnidaria"[Organism] OR "Echinodermata"[Organism]) AND 400:900[SLEN] NOT "environmental"[Title] NOT "uncultured"[Title]' \
        --p-n-jobs 4 \
        --p-rank-propagation \
        --o-sequences "$DATABASE/coi_marine_raw_seqs.qza" \
        --o-taxonomy "$DATABASE/coi_marine_raw_tax.qza"
    
    conda run -n $QIIME_ENV qiime rescript dereplicate \
        --i-sequences "$DATABASE/coi_marine_raw_seqs.qza" \
        --i-taxa "$DATABASE/coi_marine_raw_tax.qza" \
        --p-mode 'uniq' \
        --p-derep-prefix \
        --o-dereplicated-sequences "$DATABASE/coi_marine_derep_seqs.qza" \
        --o-dereplicated-taxa "$DATABASE/coi_marine_derep_tax.qza"
    
    conda run -n $QIIME_ENV qiime rescript cull-seqs \
        --i-sequences "$DATABASE/coi_marine_derep_seqs.qza" \
        --o-clean-sequences "$DATABASE/coi_marine_seqs.qza"
    
    conda run -n $QIIME_ENV qiime rescript filter-taxa \
        --i-taxonomy "$DATABASE/coi_marine_derep_tax.qza" \
        --m-ids-to-keep-file "$DATABASE/coi_marine_seqs.qza" \
        --o-filtered-taxonomy "$DATABASE/coi_marine_tax.qza"
    
    echo "Entraînement classificateur COI MARINE..."
    conda run -n $QIIME_ENV qiime feature-classifier fit-classifier-naive-bayes \
        --i-reference-reads "$DATABASE/coi_marine_seqs.qza" \
        --i-reference-taxonomy "$DATABASE/coi_marine_tax.qza" \
        --o-classifier "$DATABASE/coi_marine_classifier.qza"
fi

#################################################################################
# 5. BASE DE DONNÉES 16S Vertebrates - VERTÉBRÉS MARINS avec RÉSOLUTION ESPÈCE
#################################################################################

echo "--- Préparation base de données 16S Vertébrés (MARINS - niveau espèce) ---"

if [ ! -f "$DATABASE/vert_marine_16s_classifier.qza" ]; then
    echo "Téléchargement séquences 16S vertébrés MARINS depuis NCBI..."
    
    conda run -n $QIIME_ENV qiime rescript get-ncbi-data \
        --p-query '"16S ribosomal RNA"[Title] AND ("Actinopterygii"[Organism] OR "Chondrichthyes"[Organism] OR "Cetacea"[Organism] OR "Sirenia"[Organism] OR "Testudines"[Organism] OR "Elasmobranchii"[Organism]) AND 200:2000[SLEN] NOT "environmental"[Title] NOT "uncultured"[Title]' \
        --p-n-jobs 4 \
        --p-rank-propagation \
        --o-sequences "$DATABASE/vert_marine_16s_raw_seqs.qza" \
        --o-taxonomy "$DATABASE/vert_marine_16s_raw_tax.qza"
    
    conda run -n $QIIME_ENV qiime rescript dereplicate \
        --i-sequences "$DATABASE/vert_marine_16s_raw_seqs.qza" \
        --i-taxa "$DATABASE/vert_marine_16s_raw_tax.qza" \
        --p-mode 'uniq' \
        --p-derep-prefix \
        --o-dereplicated-sequences "$DATABASE/vert_marine_16s_derep_seqs.qza" \
        --o-dereplicated-taxa "$DATABASE/vert_marine_16s_derep_tax.qza"
    
    conda run -n $QIIME_ENV qiime rescript cull-seqs \
        --i-sequences "$DATABASE/vert_marine_16s_derep_seqs.qza" \
        --o-clean-sequences "$DATABASE/vert_marine_16s_seqs.qza"
    
    conda run -n $QIIME_ENV qiime rescript filter-taxa \
        --i-taxonomy "$DATABASE/vert_marine_16s_derep_tax.qza" \
        --m-ids-to-keep-file "$DATABASE/vert_marine_16s_seqs.qza" \
        --o-filtered-taxonomy "$DATABASE/vert_marine_16s_tax.qza"
    
    echo "Entraînement classificateur 16S Vertébrés MARINS..."
    conda run -n $QIIME_ENV qiime feature-classifier fit-classifier-naive-bayes \
        --i-reference-reads "$DATABASE/vert_marine_16s_seqs.qza" \
        --i-reference-taxonomy "$DATABASE/vert_marine_16s_tax.qza" \
        --o-classifier "$DATABASE/vert_marine_16s_classifier.qza"
fi

echo "=== Bases de données MARINES préparées avec résolution ESPÈCE ==="

#################################################################################
# ASSIGNATIONS TAXONOMIQUES AVEC EXTRACTION TSV AUTOMATIQUE
#################################################################################

assign_taxonomy_with_tsv() {
    local marker=$1
    local classifier=$2
    local output_name=$3
    
    echo "--- Assignation taxonomique pour $marker ---"
    
    if [ ! -f "taxonomy/${output_name}.qza" ]; then
        conda run -n $QIIME_ENV qiime feature-classifier classify-sklearn \
            --i-classifier "$DATABASE/$classifier" \
            --i-reads core/RepSeq.qza \
            --o-classification "taxonomy/${output_name}.qza" \
            --p-confidence 0.7 \
            --p-n-jobs 4
    fi
    
    # Extraction automatique du TSV
    extract_tsv_from_taxonomy "taxonomy/${output_name}.qza" "$output_name"
}

echo "=== Début des assignations taxonomiques avec extraction TSV automatique ==="

# 1. 12S MiFish - Poissons marins
assign_taxonomy_with_tsv "12S-MiFish-MARINE" "mifish_marine_classifier.qza" "taxonomy_12SMifish"

# 2. 12S Mimammal - Mammifères marins
assign_taxonomy_with_tsv "12S-Mimammal-MARINE" "mammal_marine_12s_classifier.qza" "taxonomy_12SMimammal"

# 3. 12S Teleo - Téléostéens marins
assign_taxonomy_with_tsv "12S-Teleo-MARINE" "teleo_marine_12s_classifier.qza" "taxonomy_12STeleo"

# 4. COI Leray-Geller - Faune marine
assign_taxonomy_with_tsv "COI-Leray-Geller-MARINE" "coi_marine_classifier.qza" "taxonomy_CO1"

# 5. 16S Vertebrates - Vertébrés marins
assign_taxonomy_with_tsv "16S-Vert-MARINE" "vert_marine_16s_classifier.qza" "taxonomy_16S"

echo ""
echo "=== Script terminé avec succès ==="
echo ""
echo "Fichiers de taxonomie TSV créés automatiquement:"
echo "- export/taxonomy/taxonomy_12SMifish.tsv"
echo "- export/taxonomy/taxonomy_12SMimammal.tsv"
echo "- export/taxonomy/taxonomy_12STeleo.tsv"
echo "- export/taxonomy/taxonomy_CO1.tsv"
echo "- export/taxonomy/taxonomy_16S.tsv"
echo ""

echo "=== Vérification et statistiques des résultats ==="
for file in export/taxonomy/taxonomy_*.tsv; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        linecount=$(($(wc -l < "$file") - 1))  # -1 pour enlever le header
        
        # Compter combien ont une taxonomie complète (niveau espèce)
        species_count=$(grep -c ";s__[^;]*$" "$file" || echo 0)
        genus_count=$(grep -c ";g__[^;]*;" "$file" || echo 0)
        
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "📄 $filename"
        echo "   Total ASVs: $linecount"
        echo "   Assignés au niveau espèce: $species_count"
        echo "   Assignés au niveau genre: $genus_count"
        echo "   Aperçu:"
        head -5 "$file" | tail -4
        echo ""
    fi
done

echo ""
echo "=== AMÉLIORATIONS APPORTÉES ==="
echo "✓ Ajout de --p-rank-propagation pour propager les rangs taxonomiques"
echo "✓ Déréplication avec mode 'uniq' pour préserver toutes les infos taxonomiques"
echo "✓ Exclusion des séquences 'environmental' et 'uncultured'"
echo "✓ Extraction TSV automatique pour tous les marqueurs"
echo "✓ Bases optimisées pour récifs coralliens Nouvelle-Calédonie"
