#!/bin/bash

cd /Users/stengerpierre-louis/Desktop/

# Vérifier que les fichiers nécessaires existent
if [[ ! -f ASV.tsv || ! -f taxonomy.tsv ]]; then
  echo "Les fichiers ASV.tsv ou taxonomy.tsv sont manquants."
  exit 1
fi

# Extraire les en-têtes des colonnes de ASV.tsv (sauf la première colonne)
headers=$(head -n 1 ASV.tsv | cut -f 2-)

# Créer un fichier temporaire pour stocker les données fusionnées
temp_file=$(mktemp)

# Lire chaque ligne du fichier taxonomy.tsv et fusionner avec ASV.tsv
while IFS=$'\t' read -r feature_id taxon confidence; do
  # Nettoyer les préfixes de la taxonomie
  cleaned_taxon=$(echo "$taxon" | sed 's/[dpcofg]__//g')

  # Extraire les valeurs correspondantes de ASV.tsv
  values=$(grep -w "$feature_id" ASV.tsv | cut -f 2-)

  # Écrire la ligne fusionnée dans le fichier temporaire
  echo -e "$cleaned_taxon\t$values" >> "$temp_file"
done < <(tail -n +2 taxonomy.tsv)

# Créer le fichier final avec les en-têtes et les données fusionnées
output_file="merged_output.tsv"
echo -e "Kingdom\tPhylum\tClass\tOrder\tFamily\tGenus\tSpecies\t$headers" > "$output_file"
cat "$temp_file" >> "$output_file"

# Nettoyer le fichier temporaire
rm "$temp_file"

echo "Le fichier fusionné a été créé sous le nom $output_file."