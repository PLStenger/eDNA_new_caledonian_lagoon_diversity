#!/bin/bash
#SBATCH --job-name=99_kraken_clean
#SBATCH --ntasks=1
#SBATCH -p smp
#SBATCH --mem=1000G
#SBATCH --mail-user=pierrelouis.stenger@gmail.com
#SBATCH --mail-type=ALL 
#SBATCH --error="/home/plstenge/eDNA_new_caledonian_lagoon_diversity/00_scripts/99_kraken_clean.err"
#SBATCH --output="/home/plstenge/eDNA_new_caledonian_lagoon_diversity/00_scripts/99_kraken_clean.out"

# PIPELINE KRAKEN2 avec NETTOYAGE préalable

#################################################################################
# CONFIGURATION
#################################################################################

PROJECT_DIR=/home/plstenge/eDNA_new_caledonian_lagoon_diversity
RAW_DATA=${PROJECT_DIR}/01_raw_data/raw_sequences_comp
CLEAN_DATA=${PROJECT_DIR}/01b_cleaned_data
KRAKEN_CORE_DIR=${PROJECT_DIR}/02b_kraken2_core_nt_cleaned
KRAKEN_NT_DIR=${PROJECT_DIR}/03b_kraken2_nt_cleaned
KRONA_DIR=${PROJECT_DIR}/04b_krona_cleaned

# SOURCE des données brutes
SOURCE_DATA="/home/plstenge/eDNA_new_caledonian_lagoon_diversity/01_raw_data/raw_sequences_comp"

# Bases Kraken2
KRAKEN2_DB_CORE="/home/plstenge/k2_core_nt_20250609"
KRAKEN2_DB_NT="/home/plstenge/k2_nt_20240530"

mkdir -p $CLEAN_DATA
mkdir -p $KRAKEN_CORE_DIR/{reports,outputs}
mkdir -p $KRAKEN_NT_DIR/{reports,outputs}
mkdir -p $KRONA_DIR/{core,nt,comparison}

echo "======================================================================="
echo "PIPELINE KRAKEN2 + NETTOYAGE - Nouvelle-Calédonie"
echo "======================================================================="
echo ""

#################################################################################
# ÉCHANTILLONS
#################################################################################

declare -A SAMPLES=(
    ["Poe1"]="SRR29659654"
    ["Kouare1"]="SRR29659655"
    ["GrandLagonNord1"]="SRR29659657"
    ["Pouebo1"]="SRR29659658"
    ["Entrecasteaux1"]="SRR29659660"
    ["GrandLagonNord2"]="SRR29659906"
    ["Kouare2"]="SRR29659907"
    ["Entrecasteaux2"]="SRR29659651"
    ["Pouebo2"]="SRR29659652"
    ["Poe2"]="SRR29659653"
    ["Pouebo2bis"]="SRR29659656"
    ["GrandLagonNord3"]="SRR29659899"
    ["Poe3"]="SRR29659903"
    ["Kouare3"]="SRR29659904"
    ["Entrecasteaux3"]="SRR29659905"
    ["Entrecasteaux4"]="SRR29659896"
    ["Kouare4"]="SRR29659898"
    ["Poe4"]="SRR29659900"
    ["Pouebo4"]="SRR29659902"
    ["Control"]="SRR29659756"
)

#################################################################################
# ÉTAPE 0: VÉRIFICATION OUTILS
#################################################################################

echo "======================================================================="
echo "ÉTAPE 0: Vérification outils"
echo "======================================================================="
echo ""

# Kraken2
if ! command -v kraken2 &> /dev/null; then
    echo "❌ Kraken2 non trouvé"
    exit 1
fi

# Fastp pour nettoyage
if ! command -v fastp &> /dev/null; then
    echo "❌ fastp non trouvé - Installation..."
    conda install -y -c bioconda fastp
fi

# Krona
if ! command -v ktImportTaxonomy &> /dev/null; then
    echo "Installation Krona..."
    conda install -y -c bioconda krona
    ktUpdateTaxonomy.sh 2>/dev/null
fi

echo "✅ Kraken2: $(kraken2 --version 2>&1 | head -1)"
echo "✅ fastp: $(fastp --version 2>&1 | head -1)"
echo "✅ Krona installé"
echo ""

if [ ! -d "$KRAKEN2_DB_CORE" ] || [ ! -d "$KRAKEN2_DB_NT" ]; then
    echo "❌ Bases Kraken2 manquantes"
    exit 1
fi

echo "✅ Base CORE: $KRAKEN2_DB_CORE"
echo "✅ Base NT: $KRAKEN2_DB_NT"
echo ""

#################################################################################
# ÉTAPE 1: NETTOYAGE DES DONNÉES
#################################################################################

echo "======================================================================="
echo "ÉTAPE 1: Nettoyage des données avec fastp"
echo "======================================================================="
echo ""

cd $SOURCE_DATA

for sample in $(echo "${!SAMPLES[@]}" | tr ' ' '\n' | sort); do
    srr="${SAMPLES[$sample]}"
    raw_fastq="${SOURCE_DATA}/${srr}.fastq"
    clean_fastq="${CLEAN_DATA}/${srr}_clean.fastq"
    json_report="${CLEAN_DATA}/${srr}_fastp.json"
    html_report="${CLEAN_DATA}/${srr}_fastp.html"
    
    # Si déjà nettoyé, skip
    if [ -f "$clean_fastq" ]; then
        echo "  ✓ $sample (déjà nettoyé)"
        continue
    fi
    
    # Si pas de fichier source
    if [ ! -f "$raw_fastq" ]; then
        echo "  ⚠️  Skip $sample: fichier manquant"
        continue
    fi
    
    echo "  Nettoyage: $sample"
    
    # Nettoyage avec fastp
    # - Suppression adaptateurs
    # - Filtrage qualité >Q20
    # - Longueur minimale 50bp
    # - Trim poly-G/poly-X
    # - Correction erreurs
    
    fastp \
        -i "$raw_fastq" \
        -o "$clean_fastq" \
        --thread 8 \
        --qualified_quality_phred 20 \
        --length_required 50 \
        --cut_front \
        --cut_tail \
        --cut_window_size 4 \
        --cut_mean_quality 20 \
        --trim_poly_g \
        --trim_poly_x \
        --overrepresentation_analysis \
        --json "$json_report" \
        --html "$html_report" \
        2>&1 | grep -E "(reads passed|reads failed)"
    
    if [ $? -eq 0 ]; then
        raw_count=$(grep -c "^@" "$raw_fastq" || echo 0)
        clean_count=$(grep -c "^@" "$clean_fastq" || echo 0)
        percent=$(awk "BEGIN {printf \"%.1f\", ($clean_count/$raw_count)*100}")
        echo "    → $clean_count / $raw_count reads conservés ($percent%)"
    else
        echo "    ❌ Échec nettoyage"
    fi
done

echo ""
echo "✅ Nettoyage terminé"
echo "   Fichiers nettoyés: $(ls -1 ${CLEAN_DATA}/*_clean.fastq 2>/dev/null | wc -l) / 20"
echo ""

cd $PROJECT_DIR

#################################################################################
# FONCTION CLASSIFICATION
#################################################################################

classify_sample() {
    local sample=$1
    local srr=$2
    local db=$3
    local output_dir=$4
    local db_name=$5
    
    local fastq="${CLEAN_DATA}/${srr}_clean.fastq"
    local report="${output_dir}/reports/${sample}_report.txt"
    local output="${output_dir}/outputs/${sample}_output.txt"
    
    if [ ! -f "$fastq" ]; then
        echo "  ⚠️  Skip: $sample (fichier nettoyé manquant)"
        return 1
    fi
    
    if [ -f "$report" ]; then
        total=$(wc -l < "$output" 2>/dev/null || echo 0)
        classified=$(grep -c "^C" "$output" 2>/dev/null || echo 0)
        percent=$(awk "BEGIN {printf \"%.1f\", ($classified > 0 ? ($classified/$total)*100 : 0)}")
        echo "  ✓ $sample ($db_name): $classified/$total ($percent%)"
        return 0
    fi
    
    echo "  $sample ($db_name)..."
    
    kraken2 \
        --db "$db" \
        --threads 8 \
        --report "$report" \
        --output "$output" \
        --use-names \
        "$fastq" 2>&1 | grep -E "(processed|classified)" | head -2
    
    if [ -f "$report" ]; then
        total=$(wc -l < "$output")
        classified=$(grep -c "^C" "$output" || echo 0)
        percent=$(awk "BEGIN {printf \"%.1f\", ($classified/$total)*100}")
        echo "    → $classified/$total ($percent%)"
    fi
}

#################################################################################
# ÉTAPE 2: CLASSIFICATION BASE CORE
#################################################################################

echo "======================================================================="
echo "ÉTAPE 2: Classification BASE CORE (données nettoyées)"
echo "======================================================================="
echo ""

for sample in $(echo "${!SAMPLES[@]}" | tr ' ' '\n' | sort); do
    classify_sample "$sample" "${SAMPLES[$sample]}" "$KRAKEN2_DB_CORE" "$KRAKEN_CORE_DIR" "CORE"
done

echo ""
echo "✅ BASE CORE terminée"
echo ""

#################################################################################
# ÉTAPE 3: CLASSIFICATION BASE NT
#################################################################################

echo "======================================================================="
echo "ÉTAPE 3: Classification BASE NT (données nettoyées)"
echo "======================================================================="
echo ""

for sample in $(echo "${!SAMPLES[@]}" | tr ' ' '\n' | sort); do
    classify_sample "$sample" "${SAMPLES[$sample]}" "$KRAKEN2_DB_NT" "$KRAKEN_NT_DIR" "NT"
done

echo ""
echo "✅ BASE NT terminée"
echo ""

#################################################################################
# ÉTAPE 4: KRONA
#################################################################################

echo "======================================================================="
echo "ÉTAPE 4: Visualisations Krona"
echo "======================================================================="
echo ""

declare -A SITES=(
    ["Poe"]="Poe1 Poe2 Poe3 Poe4"
    ["Kouare"]="Kouare1 Kouare2 Kouare3 Kouare4"
    ["GrandLagonNord"]="GrandLagonNord1 GrandLagonNord2 GrandLagonNord3"
    ["Pouebo"]="Pouebo1 Pouebo2 Pouebo2bis Pouebo4"
    ["Entrecasteaux"]="Entrecasteaux1 Entrecasteaux2 Entrecasteaux3 Entrecasteaux4"
)

# CORE
for sample in "${!SAMPLES[@]}"; do
    r="${KRAKEN_CORE_DIR}/reports/${sample}_report.txt"
    [ -f "$r" ] && ktImportTaxonomy -t 5 -m 3 -o "${KRONA_DIR}/core/${sample}_core.html" "$r" 2>/dev/null
done

for site in "${!SITES[@]}"; do
    reports=""
    for s in ${SITES[$site]}; do
        r="${KRAKEN_CORE_DIR}/reports/${s}_report.txt"
        [ -f "$r" ] && reports="$reports $r"
    done
    [ -n "$reports" ] && ktImportTaxonomy -t 5 -m 3 -o "${KRONA_DIR}/core/${site}_core.html" $reports 2>/dev/null
done

all_core=$(find ${KRAKEN_CORE_DIR}/reports -name "*_report.txt" -not -name "Control*" 2>/dev/null | tr '\n' ' ')
[ -n "$all_core" ] && ktImportTaxonomy -t 5 -m 3 -o "${KRONA_DIR}/core/ALL_SITES_core_cleaned.html" $all_core 2>/dev/null

echo "  ✅ Krona CORE: $(ls -1 ${KRONA_DIR}/core/*.html 2>/dev/null | wc -l) fichiers"

# NT
for sample in "${!SAMPLES[@]}"; do
    r="${KRAKEN_NT_DIR}/reports/${sample}_report.txt"
    [ -f "$r" ] && ktImportTaxonomy -t 5 -m 3 -o "${KRONA_DIR}/nt/${sample}_nt.html" "$r" 2>/dev/null
done

for site in "${!SITES[@]}"; do
    reports=""
    for s in ${SITES[$site]}; do
        r="${KRAKEN_NT_DIR}/reports/${s}_report.txt"
        [ -f "$r" ] && reports="$reports $r"
    done
    [ -n "$reports" ] && ktImportTaxonomy -t 5 -m 3 -o "${KRONA_DIR}/nt/${site}_nt.html" $reports 2>/dev/null
done

all_nt=$(find ${KRAKEN_NT_DIR}/reports -name "*_report.txt" -not -name "Control*" 2>/dev/null | tr '\n' ' ')
[ -n "$all_nt" ] && ktImportTaxonomy -t 5 -m 3 -o "${KRONA_DIR}/nt/ALL_SITES_nt_cleaned.html" $all_nt 2>/dev/null

echo "  ✅ Krona NT: $(ls -1 ${KRONA_DIR}/nt/*.html 2>/dev/null | wc -l) fichiers"
echo ""

#################################################################################
# ÉTAPE 5: STATISTIQUES NETTOYAGE
#################################################################################

echo "======================================================================="
echo "ÉTAPE 5: Statistiques nettoyage"
echo "======================================================================="
echo ""

echo "📊 Rapport nettoyage par échantillon:"
echo ""

for sample in $(echo "${!SAMPLES[@]}" | tr ' ' '\n' | sort); do
    srr="${SAMPLES[$sample]}"
    json_report="${CLEAN_DATA}/${srr}_fastp.json"
    
    if [ -f "$json_report" ]; then
        before=$(grep '"total_reads"' "$json_report" | head -1 | grep -oP '\d+')
        after=$(grep '"total_reads"' "$json_report" | tail -1 | grep -oP '\d+')
        percent=$(awk "BEGIN {printf \"%.1f\", ($after/$before)*100}")
        echo "  $sample: $after / $before reads ($percent%)"
    fi
done

echo ""

#################################################################################
# RÉSUMÉ
#################################################################################

echo "======================================================================="
echo "✅✅✅ TERMINÉ ✅✅✅"
echo "======================================================================="
echo ""
echo "Données nettoyées: ${CLEAN_DATA}/"
echo "  → Fichiers FASTQ nettoyés"
echo "  → Rapports HTML fastp"
echo ""
echo "Visualisations principales:"
echo "  → ${KRONA_DIR}/core/ALL_SITES_core_cleaned.html"
echo "  → ${KRONA_DIR}/nt/ALL_SITES_nt_cleaned.html"
echo ""
echo "Pour visualiser:"
echo "  firefox ${KRONA_DIR}/core/ALL_SITES_core_cleaned.html &"
echo "  firefox ${KRONA_DIR}/nt/ALL_SITES_nt_cleaned.html &"
echo ""
echo "Comparaison brut vs nettoyé:"
echo "  Brut:     ${PROJECT_DIR}/04_krona/"
echo "  Nettoyé:  ${PROJECT_DIR}/04b_krona_cleaned/"
echo ""
