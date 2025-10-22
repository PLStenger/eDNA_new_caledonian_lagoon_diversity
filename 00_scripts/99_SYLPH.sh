#!/usr/bin/env bash

# CONFIGURATION
PROJECT_DIR=/home/plstenge/eDNA_new_caledonian_lagoon_diversity
RAW_DATA=${PROJECT_DIR}/01_raw_data/raw_sequences_comp
SYLPH_DIR=${PROJECT_DIR}/05_sylph
DB_DIR=${SYLPH_DIR}/gtdb
FASTADB=/home/plstenge/eDNA_new_caledonian_lagoon_diversity/05_sylph/gtdb/gtdb-r220.fa
SYLDB=$DB_DIR/gtdb-r220.syldb
SKETCH_DIR=${SYLPH_DIR}/sketches
PROFILE_DIR=${SYLPH_DIR}/profiles
RESULTS_DIR=${SYLPH_DIR}/results

mkdir -p $DB_DIR $SKETCH_DIR $PROFILE_DIR $RESULTS_DIR

# 1) Vérifier base pré-construite
if [ ! -f "$SYLDB" ]; then
  echo "❌ Base Sylph GTDB manquante : $SYLDB"
  echo ""
  echo "1) Téléchargez manuellement GTDB release r220 FASTA :"
  echo "   https://data.ace.uq.edu.au/public/gtdb/data/releases/release_220/ "
  echo "   puis placez le fichier 'gtdb-r220.fa' dans :"
  echo "     $DB_DIR"
  echo ""
  echo "2) Si vous préférez construire la base vous-même :"
  echo "   sylph sketch -g $FASTADB -o $SYLDB"
  echo ""
  echo "Une fois la base disponible, relancez ce script."
  exit 1
fi

# 2) Sketch GTDB (si nécessaire)
if [ ! -f "$DB_DIR/gtdb-r220.sketch" ]; then
  echo "✅ Base Sylph détectée ($SYLDB), mais pas de sketch."
  echo "Création du sketch de la base GTDB..."
  sylph sketch -g $FASTADB -o $DB_DIR/gtdb-r220.sketch
fi

# 3) Sketching de vos échantillons
echo "Sketching des échantillons..."
for fq in $RAW_DATA/*.fastq $RAW_DATA/*.fastq.gz; do
  name=$(basename $fq | sed 's/\(.fastq\|.fq\)\(.gz\)\?$//')
  out=$SKETCH_DIR/${name}.sylsp
  [ -f "$out" ] && continue
  echo "  - $name"
  sylph sketch -t 8 -o "$out" "$fq"
done

# 4) Profiling Sylph
echo "Profiling taxonomique..."
for sk in $SKETCH_DIR/*.sylsp; do
  name=$(basename $sk .sylsp)
  prof=$PROFILE_DIR/${name}_profile.tsv
  [ -f "$prof" ] && continue
  echo "  - $name"
  sylph profile -t 8 $DB_DIR/gtdb-r220.sketch "$sk" > "$prof"
done

# 5) Extraction résumé
echo -e "Sample\t#Species\tTopSpecies\tAbundance" > $RESULTS_DIR/summary.tsv
for prof in $PROFILE_DIR/*_profile.tsv; do
  sample=${prof##*/}
  sample=${sample%_profile.tsv}
  total=$(tail -n +2 "$prof" | wc -l)
  top=$(tail -n +2 "$prof" | sort -k3nr | head -1 | awk '{print $1}')
  ab=$(tail -n +2 "$prof" | sort -k3nr | head -1 | awk '{print $3}')
  echo -e "$sample\t$total\t$top\t$ab" >> $RESULTS_DIR/summary.tsv
done

# Afficher résumé
column -t -s $'\t' $RESULTS_DIR/summary.tsv

echo ""
echo "✅ Pipeline Sylph terminé. Résumé disponible dans :"
echo "  $RESULTS_DIR/summary.tsv"
