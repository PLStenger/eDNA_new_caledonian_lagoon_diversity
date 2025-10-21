#!/usr/bin/env bash

# PIPELINE KRAKEN2 - Utilise fichiers FASTQ existants
# Assume que les fichiers sont dans /nvme/bio/data_fungi/.../01_raw_data

#################################################################################
# CONFIGURATION
#################################################################################

PROJECT_DIR=/home/plstenge/eDNA_new_caledonian_lagoon_diversity
RAW_DATA=${PROJECT_DIR}/01_raw_data
KRAKEN_CORE_DIR=${PROJECT_DIR}/02_kraken2_core_nt
KRAKEN_NT_DIR=${PROJECT_DIR}/03_kraken2_nt
KRONA_DIR=${PROJECT_DIR}/04_krona

# SOURCE des données (ajuster selon votre cas)
SOURCE_DATA="/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity/01_raw_data"

# Bases Kraken2
KRAKEN2_DB_CORE="/home/plstenge/k2_core_nt_20250609"
KRAKEN2_DB_NT="/home/plstenge/k2_nt_20240530"

mkdir -p $RAW_DATA
mkdir -p $KRAKEN_CORE_DIR/{reports,outputs}
mkdir -p $KRAKEN_NT_DIR/{reports,outputs}
mkdir -p $KRONA_DIR/{core,nt,comparison}

echo "======================================================================="
echo "PIPELINE KRAKEN2 + KRONA - Nouvelle-Calédonie"
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
# ÉTAPE 1: PRÉPARATION DONNÉES
#################################################################################

echo "======================================================================="
echo "ÉTAPE 1: Préparation données"
echo "======================================================================="
echo ""

cd $RAW_DATA

# Vérifier fichiers locaux
local_count=$(ls -1 SRR*.fastq 2>/dev/null | wc -l)

if [ $local_count -eq 20 ]; then
    echo "✅ Les 20 fichiers FASTQ sont présents localement"
else
    echo "📂 Fichiers locaux: $local_count / 20"
    echo ""
    
    # Chercher dans la source
    if [ -d "$SOURCE_DATA" ]; then
        echo "Copie depuis: $SOURCE_DATA"
        
        for srr in "${SAMPLES[@]}"; do
            if [ ! -f "${srr}.fastq" ]; then
                if [ -f "${SOURCE_DATA}/${srr}.fastq" ]; then
                    echo "  Copie: ${srr}.fastq"
                    cp "${SOURCE_DATA}/${srr}.fastq" .
                elif [ -f "${SOURCE_DATA}/${srr}.fastq.gz" ]; then
                    echo "  Décompression: ${srr}.fastq.gz"
                    gunzip -c "${SOURCE_DATA}/${srr}.fastq.gz" > ${srr}.fastq
                fi
            fi
        done
    else
        echo "⚠️  Source non trouvée: $SOURCE_DATA"
        echo ""
        echo "SOLUTIONS:"
        echo ""
        echo "1. Copier manuellement les fichiers:"
        echo "   cp /nvme/bio/.../01_raw_data/SRR*.fastq $RAW_DATA/"
        echo ""
        echo "2. Créer liens symboliques:"
        echo "   cd $RAW_DATA"
        echo "   ln -s /nvme/bio/.../01_raw_data/SRR*.fastq ."
        echo ""
        echo "3. Télécharger avec parallel-fastq-dump:"
        echo "   parallel-fastq-dump --sra-id SRR29659654 --threads 4 --split-files"
        echo ""
        exit 1
    fi
fi

# Vérification finale
echo ""
echo "📊 Fichiers disponibles: $(ls -1 SRR*.fastq 2>/dev/null | wc -l) / 20"

missing=0
for srr in "${SAMPLES[@]}"; do
    if [ ! -f "${srr}.fastq" ]; then
        echo "  ⚠️  Manquant: ${srr}.fastq"
        missing=$((missing + 1))
    fi
done

if [ $missing -gt 0 ]; then
    echo ""
    echo "❌ $missing fichiers manquants"
    echo ""
    echo "Pour télécharger manuellement:"
    echo "  module load sra-toolkit  # si module disponible"
    echo "  prefetch SRR29659654 && fastq-dump --split-spot SRR29659654"
    exit 1
fi

echo "✅ Tous les fichiers présents"
echo ""

cd $PROJECT_DIR

#################################################################################
# ÉTAPE 2: OUTILS
#################################################################################

echo "======================================================================="
echo "ÉTAPE 2: Vérification outils"
echo "======================================================================="
echo ""

if ! command -v kraken2 &> /dev/null; then
    echo "❌ Kraken2 non trouvé"
    echo "   Installation: conda install -c bioconda kraken2"
    exit 1
fi

if ! command -v ktImportTaxonomy &> /dev/null; then
    echo "Installation Krona..."
    conda install -y -c bioconda krona
    ktUpdateTaxonomy.sh 2>/dev/null
fi

echo "✅ Kraken2: $(kraken2 --version 2>&1 | head -1)"
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
# FONCTION CLASSIFICATION
#################################################################################

classify_sample() {
    local sample=$1
    local srr=$2
    local db=$3
    local output_dir=$4
    local db_name=$5
    
    local fastq="${RAW_DATA}/${srr}.fastq"
    local report="${output_dir}/reports/${sample}_report.txt"
    local output="${output_dir}/outputs/${sample}_output.txt"
    
    if [ ! -f "$fastq" ]; then
        echo "  ⚠️  Skip: $sample"
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
# ÉTAPE 3: CLASSIFICATION BASE CORE
#################################################################################

echo "======================================================================="
echo "ÉTAPE 3: Classification BASE CORE"
echo "======================================================================="
echo ""

for sample in $(echo "${!SAMPLES[@]}" | tr ' ' '\n' | sort); do
    classify_sample "$sample" "${SAMPLES[$sample]}" "$KRAKEN2_DB_CORE" "$KRAKEN_CORE_DIR" "CORE"
done

echo ""
echo "✅ BASE CORE terminée"
echo ""

#################################################################################
# ÉTAPE 4: CLASSIFICATION BASE NT
#################################################################################

echo "======================================================================="
echo "ÉTAPE 4: Classification BASE NT"
echo "======================================================================="
echo ""

for sample in $(echo "${!SAMPLES[@]}" | tr ' ' '\n' | sort); do
    classify_sample "$sample" "${SAMPLES[$sample]}" "$KRAKEN2_DB_NT" "$KRAKEN_NT_DIR" "NT"
done

echo ""
echo "✅ BASE NT terminée"
echo ""

#################################################################################
# ÉTAPE 5: KRONA
#################################################################################

echo "======================================================================="
echo "ÉTAPE 5: Visualisations Krona"
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
[ -n "$all_core" ] && ktImportTaxonomy -t 5 -m 3 -o "${KRONA_DIR}/core/ALL_SITES_core.html" $all_core 2>/dev/null

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
[ -n "$all_nt" ] && ktImportTaxonomy -t 5 -m 3 -o "${KRONA_DIR}/nt/ALL_SITES_nt.html" $all_nt 2>/dev/null

echo "  ✅ Krona NT: $(ls -1 ${KRONA_DIR}/nt/*.html 2>/dev/null | wc -l) fichiers"
echo ""

#################################################################################
# RÉSUMÉ
#################################################################################

echo "======================================================================="
echo "✅✅✅ TERMINÉ ✅✅✅"
echo "======================================================================="
echo ""
echo "Visualisations principales:"
echo "  → ${KRONA_DIR}/core/ALL_SITES_core.html"
echo "  → ${KRONA_DIR}/nt/ALL_SITES_nt.html"
echo ""
echo "Pour visualiser:"
echo "  firefox ${KRONA_DIR}/core/ALL_SITES_core.html &"
echo "  firefox ${KRONA_DIR}/nt/ALL_SITES_nt.html &"
echo ""
