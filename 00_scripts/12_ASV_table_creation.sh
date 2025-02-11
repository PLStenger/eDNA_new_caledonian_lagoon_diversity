#!/usr/bin/env bash

WORKING_DIRECTORY=/scratch_vol0/fungi/eDNA_new_caledonian_lagoon_diversity/05_QIIME2
OUTPUT=/scratch_vol0/fungi/eDNA_new_caledonian_lagoon_diversity/05_QIIME2/visual

TMPDIR=/scratch_vol0

#########################################

cd $WORKING_DIRECTORY

eval "$(conda shell.bash hook)"
conda activate qiime2-2021.4

# Make the directory (mkdir) only if not existe already(-p)
mkdir -p subtables
mkdir -p export/subtables

# I'm doing this step in order to deal the no space left in cluster :
export TMPDIR='/scratch_vol0/fungi'
echo $TMPDIR


# Définir les chemins des fichiers d'entrée et de sortie
taxonomy_file="export/taxonomy/16S/taxonomy_reads-per-batch_RarRepSeq/taxonomy.tsv"
asv_file="export/subtables/RarTable-all/ASV.tsv"
output_all_info="export/subtables/16S_all_info.txt"
output_no_asv_id="export/subtables/16S.txt"

# Vérifier si les fichiers d'entrée existent
if [[ ! -f "$taxonomy_file" || ! -f "$asv_file" ]]; then
  echo "Erreur : Fichiers nécessaires introuvables."
  exit 1
fi

# Créer le fichier 16S_all_info.txt
{
  # Ajouter l'en-tête
  echo -e "ASV_ID\tKingdom\tPhylum\tClass\tOrder\tFamily\tGenus\tSpecies\t$(head -n 1 "$asv_file" | cut -f2-)"

  # Combiner les fichiers taxonomy.tsv et ASV.tsv
  awk -F'\t' 'NR==FNR {
    split($2, tax, "; "); 
    taxonomy[$1] = tax[1] "\t" tax[2] "\t" tax[3] "\t" tax[4] "\t" tax[5] "\t" tax[6] "\t" tax[7];
    next
  }
  FNR > 1 {
    if ($1 in taxonomy) {
      print $1 "\t" taxonomy[$1] "\t" $0
    }
  }' "$taxonomy_file" <(tail -n +2 "$asv_file") | cut -f1-9,11-
} > "$output_all_info"

# Vérifier si le fichier a été créé
if [[ -f "$output_all_info" ]]; then
  echo "Fichier $output_all_info créé avec succès."
else
  echo "Erreur : Échec de la création de $output_all_info."
  exit 1
fi

# Créer le fichier 16S.txt sans la colonne ASV_ID
cut -f2- "$output_all_info" > "$output_no_asv_id"

# Vérifier si le fichier a été créé
if [[ -f "$output_no_asv_id" ]]; then
  echo "Fichier $output_no_asv_id créé avec succès."
else
  echo "Erreur : Échec de la création de $output_no_asv_id."
  exit 1
fi
