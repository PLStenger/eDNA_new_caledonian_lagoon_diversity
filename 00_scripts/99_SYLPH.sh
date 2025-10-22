#!/bin/bash
#SBATCH --job-name=99_SYLPH
#SBATCH --ntasks=1
#SBATCH -p smp
#SBATCH --mem=1000G
#SBATCH --mail-user=pierrelouis.stenger@gmail.com
#SBATCH --mail-type=ALL 
#SBATCH --error="/home/plstenge/eDNA_new_caledonian_lagoon_diversity/00_scripts/99_SYLPH.err"
#SBATCH --output="/home/plstenge/eDNA_new_caledonian_lagoon_diversity/00_scripts/99_SYLPH.out"


# PIPELINE SYLPH - Taxonomie ultra-rapide pour eDNA Nouvelle-Calédonie
# Sylph: profiling métagénomique rapide et précis
# https://sylph-docs.github.io

#################################################################################
# CONFIGURATION
#################################################################################

PROJECT_DIR=/home/plstenge/eDNA_new_caledonian_lagoon_diversity
RAW_DATA=${PROJECT_DIR}/01_raw_data/raw_sequences_comp
SYLPH_DIR=${PROJECT_DIR}/05_sylph
SKETCH_DIR=${SYLPH_DIR}/sketches
PROFILE_DIR=${SYLPH_DIR}/profiles
RESULTS_DIR=${SYLPH_DIR}/results

# Bases de données Sylph (téléchargement automatique)
SYLPH_DB_DIR=${PROJECT_DIR}/sylph_databases

mkdir -p $SKETCH_DIR
mkdir -p $PROFILE_DIR
mkdir -p $RESULTS_DIR
mkdir -p $SYLPH_DB_DIR

cd $PROJECT_DIR

echo "======================================================================="
echo "PIPELINE SYLPH - Taxonomie métagénomique"
echo "Nouvelle-Calédonie - Biodiversité marine récifale"
echo "======================================================================="
echo ""
echo "Données: $RAW_DATA"
echo "Outputs: $SYLPH_DIR"
echo ""

#################################################################################
# ÉTAPE 1: INSTALLATION SYLPH
#################################################################################

echo "======================================================================="
echo "ÉTAPE 1: Installation Sylph"
echo "======================================================================="
echo ""

if ! command -v sylph &> /dev/null; then
    echo "Installation de Sylph..."
    
    # Option 1: Conda (recommandé)
    conda install -y -c bioconda sylph
    
    # Option 2: Cargo (si conda échoue)
    # cargo install sylph
    
    if [ $? -eq 0 ]; then
        echo "✅ Sylph installé"
    else
        echo "❌ Échec installation"
        echo ""
        echo "Installation manuelle:"
        echo "  1. Conda: conda install -c bioconda sylph"
        echo "  2. Cargo: cargo install sylph"
        echo "  3. Binary: wget https://github.com/bluenote-1577/sylph/releases/download/latest/sylph"
        exit 1
    fi
else
    echo "✅ Sylph déjà installé"
fi

sylph --version
echo ""

#################################################################################
# ÉTAPE 2: TÉLÉCHARGEMENT BASES DE DONNÉES
#################################################################################

echo "======================================================================="
echo "ÉTAPE 2: Téléchargement bases de données Sylph"
echo "======================================================================="
echo ""

cd $SYLPH_DB_DIR

# Base GTDB (Genomes - bactéries/archées) - ~15 GB
if [ ! -f "gtdb-r220-c200-dbv1.syldb" ]; then
    echo "Téléchargement GTDB database (bactéries/archées, ~15 GB)..."
    echo "Cela peut prendre 10-30 minutes selon connexion..."
    
    sylph download -d gtdb-r220 -o .
    
    if [ $? -eq 0 ]; then
        echo "✅ GTDB database téléchargée"
    else
        echo "⚠️  Téléchargement GTDB échoué"
        echo "   Téléchargement manuel possible depuis:"
        echo "   https://github.com/bluenote-1577/sylph/releases"
    fi
else
    echo "✅ GTDB database déjà présente"
fi

echo ""

# Base GenBank (plus complète, eucaryotes inclus) - peut être très volumineuse
echo "Options de bases supplémentaires:"
echo "  - GenBank viral: sylph download -d genbank-viral"
echo "  - GenBank fungi: sylph download -d genbank-fungi"
echo "  - GenBank protozoa: sylph download -d genbank-protozoa"
echo "  - Custom: Créer votre propre base avec 'sylph sketch'"
echo ""
echo "Pour eDNA marine, GTDB suffit généralement pour commencer."
echo ""

cd $PROJECT_DIR

#################################################################################
# ÉTAPE 3: SKETCHING DES ÉCHANTILLONS
#################################################################################

echo "======================================================================="
echo "ÉTAPE 3: Sketching des échantillons (création signatures)"
echo "======================================================================="
echo ""

# Trouver tous les fichiers FASTQ
FASTQ_FILES=$(find $RAW_DATA -name "*.fastq" -o -name "*.fq" -o -name "*.fastq.gz" -o -name "*.fq.gz" 2>/dev/null)

if [ -z "$FASTQ_FILES" ]; then
    echo "❌ Aucun fichier FASTQ trouvé dans $RAW_DATA"
    exit 1
fi

FASTQ_COUNT=$(echo "$FASTQ_FILES" | wc -l)
echo "📊 Fichiers FASTQ trouvés: $FASTQ_COUNT"
echo ""

# Sketching (création des signatures k-mer)
echo "Création des sketches (signatures k-mer)..."
echo "Cela prend quelques minutes par échantillon..."
echo ""

for FASTQ in $FASTQ_FILES; do
    BASENAME=$(basename "$FASTQ" | sed 's/\.\(fastq\|fq\)\(\.gz\)\?$//')
    SKETCH_FILE="${SKETCH_DIR}/${BASENAME}.sylsp"
    
    if [ -f "$SKETCH_FILE" ]; then
        echo "  ✓ $BASENAME (déjà fait)"
        continue
    fi
    
    echo "  Sketching: $BASENAME"
    
    sylph sketch \
        -t 8 \
        -o "$SKETCH_FILE" \
        "$FASTQ"
    
    if [ $? -eq 0 ]; then
        echo "    ✓ Sketch créé"
    else
        echo "    ❌ Échec"
    fi
done

echo ""
echo "✅ Sketching terminé"
echo ""

#################################################################################
# ÉTAPE 4: PROFILING TAXONOMIQUE
#################################################################################

echo "======================================================================="
echo "ÉTAPE 4: Profiling taxonomique avec GTDB"
echo "======================================================================="
echo ""

# Profiling avec la base GTDB
GTDB_DATABASE="${SYLPH_DB_DIR}/gtdb-r220-c200-dbv1.syldb"

if [ ! -f "$GTDB_DATABASE" ]; then
    echo "❌ Base GTDB manquante: $GTDB_DATABASE"
    exit 1
fi

echo "Profiling contre GTDB database..."
echo ""

# Profiling de tous les sketches
SKETCH_FILES=$(find $SKETCH_DIR -name "*.sylsp" 2>/dev/null)

for SKETCH in $SKETCH_FILES; do
    BASENAME=$(basename "$SKETCH" .sylsp)
    PROFILE_FILE="${PROFILE_DIR}/${BASENAME}_profile.tsv"
    
    if [ -f "$PROFILE_FILE" ]; then
        echo "  ✓ $BASENAME (déjà fait)"
        continue
    fi
    
    echo "  Profiling: $BASENAME"
    
    sylph profile \
        -t 8 \
        "$GTDB_DATABASE" \
        "$SKETCH" \
        > "$PROFILE_FILE"
    
    if [ $? -eq 0 ]; then
        # Stats rapides
        species_count=$(tail -n +2 "$PROFILE_FILE" | wc -l)
        echo "    ✓ $species_count espèces détectées"
    else
        echo "    ❌ Échec"
    fi
done

echo ""
echo "✅ Profiling terminé"
echo ""

#################################################################################
# ÉTAPE 5: ANALYSE ET RÉSUMÉS
#################################################################################

echo "======================================================================="
echo "ÉTAPE 5: Analyse et résumés"
echo "======================================================================="
echo ""

# Créer tableau résumé
SUMMARY_FILE="${RESULTS_DIR}/summary_all_samples.tsv"

echo -e "Sample\tTotal_species\tTop_species\tTop_abundance" > "$SUMMARY_FILE"

for PROFILE in ${PROFILE_DIR}/*_profile.tsv; do
    [ ! -f "$PROFILE" ] && continue
    
    SAMPLE=$(basename "$PROFILE" _profile.tsv)
    
    # Compter espèces
    TOTAL=$(tail -n +2 "$PROFILE" | wc -l)
    
    # Top espèce
    TOP_LINE=$(tail -n +2 "$PROFILE" | sort -k3 -nr | head -1)
    TOP_SPECIES=$(echo "$TOP_LINE" | awk '{print $1}')
    TOP_ABUND=$(echo "$TOP_LINE" | awk '{print $3}')
    
    echo -e "${SAMPLE}\t${TOTAL}\t${TOP_SPECIES}\t${TOP_ABUND}" >> "$SUMMARY_FILE"
done

echo "📊 RÉSUMÉ PAR ÉCHANTILLON:"
column -t -s $'\t' "$SUMMARY_FILE"
echo ""

# Top 30 espèces globales
echo "🏆 TOP 30 ESPÈCES (tous échantillons):"
echo ""

cat ${PROFILE_DIR}/*_profile.tsv | \
    tail -n +2 | \
    awk '{print $1"\t"$3}' | \
    awk '{sum[$1]+=$2} END {for (sp in sum) print sum[sp]"\t"sp}' | \
    sort -k1 -nr | \
    head -30 | \
    awk '{printf "%8.4f × %s\n", $1, $2}'

echo ""

# Focus sur groupes marins
echo "🌊 GROUPES MARINS DÉTECTÉS:"
echo ""

MARINE_SUMMARY="${RESULTS_DIR}/marine_groups.tsv"

echo -e "Sample\tVibrionaceae\tPseudomonadaceae\tFlavobacteriaceae\tRhodobacteraceae" > "$MARINE_SUMMARY"

for PROFILE in ${PROFILE_DIR}/*_profile.tsv; do
    [ ! -f "$PROFILE" ] && continue
    
    SAMPLE=$(basename "$PROFILE" _profile.tsv)
    
    # Compter familles marines communes
    vibrio=$(grep -i "Vibrionaceae" "$PROFILE" | awk '{sum+=$3} END {printf "%.4f", sum+0}')
    pseudo=$(grep -i "Pseudomonadaceae" "$PROFILE" | awk '{sum+=$3} END {printf "%.4f", sum+0}')
    flavo=$(grep -i "Flavobacteriaceae" "$PROFILE" | awk '{sum+=$3} END {printf "%.4f", sum+0}')
    rhodo=$(grep -i "Rhodobacteraceae" "$PROFILE" | awk '{sum+=$3} END {printf "%.4f", sum+0}')
    
    echo -e "${SAMPLE}\t${vibrio}\t${pseudo}\t${flavo}\t${rhodo}" >> "$MARINE_SUMMARY"
done

column -t -s $'\t' "$MARINE_SUMMARY"
echo ""

#################################################################################
# ÉTAPE 6: VISUALISATIONS
#################################################################################

echo "======================================================================="
echo "ÉTAPE 6: Export pour visualisation"
echo "======================================================================="
echo ""

# Créer fichier pour Krona
KRONA_INPUT="${RESULTS_DIR}/for_krona.txt"

> "$KRONA_INPUT"

for PROFILE in ${PROFILE_DIR}/*_profile.tsv; do
    [ ! -f "$PROFILE" ] && continue
    
    SAMPLE=$(basename "$PROFILE" _profile.tsv)
    
    # Convertir format Sylph → Krona
    tail -n +2 "$PROFILE" | \
        awk -v sample="$SAMPLE" '{
            # Extraire taxonomie du nom (format GTDB)
            split($1, parts, ";")
            printf "%s\t%s\n", $3*100, $1
        }' >> "$KRONA_INPUT"
done

echo "✅ Fichier pour Krona: $KRONA_INPUT"
echo ""

# Si Krona installé, créer visualisation
if command -v ktImportText &> /dev/null; then
    echo "Création graphique Krona..."
    
    ktImportText \
        -o "${RESULTS_DIR}/sylph_krona.html" \
        "$KRONA_INPUT"
    
    echo "✅ Krona HTML: ${RESULTS_DIR}/sylph_krona.html"
else
    echo "⚠️  Krona non installé (optionnel)"
    echo "   Installation: conda install -c bioconda krona"
fi

echo ""

#################################################################################
# RÉSUMÉ FINAL
#################################################################################

echo ""
echo "======================================================================="
echo "✅✅✅ PIPELINE SYLPH TERMINÉ ✅✅✅"
echo "======================================================================="
echo ""
echo "FICHIERS CRÉÉS:"
echo ""
echo "1. SKETCHES (signatures k-mer):"
echo "   → ${SKETCH_DIR}/*.sylsp"
echo ""
echo "2. PROFILS TAXONOMIQUES:"
echo "   → ${PROFILE_DIR}/*_profile.tsv"
echo ""
echo "3. RÉSUMÉS:"
echo "   → ${RESULTS_DIR}/summary_all_samples.tsv"
echo "   → ${RESULTS_DIR}/marine_groups.tsv"
echo "   → ${RESULTS_DIR}/sylph_krona.html (si Krona installé)"
echo ""
echo "POUR ANALYSER LES RÉSULTATS:"
echo ""
echo "# Voir profil d'un échantillon"
echo "less ${PROFILE_DIR}/[échantillon]_profile.tsv"
echo ""
echo "# Colonnes du profil Sylph:"
echo "  1. Genome_name (espèce/souche)"
echo "  2. Sequence_abundance (abondance séquence)"
echo "  3. Adjusted_abundance (abondance ajustée)"
echo "  4. ANI (identité nucléotidique moyenne)"
echo ""
echo "AVANTAGES SYLPH vs Kraken:"
echo "  ✅ 10-100x plus rapide"
echo "  ✅ Plus précis (utilise ANI)"
echo "  ✅ Estimations d'abondance meilleures"
echo "  ✅ Bases de données plus petites"
echo ""
echo "Bonne analyse ! 🧬🔬🌊"
echo ""
