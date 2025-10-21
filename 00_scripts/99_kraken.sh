#!/bin/bash
#SBATCH --job-name=99_kraken
#SBATCH --ntasks=1
#SBATCH -p smp
#SBATCH --mem=1000G
#SBATCH --mail-user=pierrelouis.stenger@gmail.com
#SBATCH --mail-type=ALL 
#SBATCH --error="/home/plstenge/eDNA_new_caledonian_lagoon_diversity/00_scripts/99_kraken.err"
#SBATCH --output="/home/plstenge/eDNA_new_caledonian_lagoon_diversity/00_scripts/99_kraken.out"

#!/usr/bin/env bash

# PIPELINE KRAKEN2 CORRIGÉ - Utilise données existantes ou télécharge avec fastq-dump
# Nouvelle-Calédonie eDNA

#################################################################################
# CONFIGURATION
#################################################################################

PROJECT_DIR=/home/plstenge/eDNA_new_caledonian_lagoon_diversity
RAW_DATA=${PROJECT_DIR}/01_raw_data
KRAKEN_CORE_DIR=${PROJECT_DIR}/02_kraken2_core_nt
KRAKEN_NT_DIR=${PROJECT_DIR}/03_kraken2_nt
KRONA_DIR=${PROJECT_DIR}/04_krona

# Bases Kraken2
KRAKEN2_DB_CORE="/home/plstenge/k2_core_nt_20250609"
KRAKEN2_DB_NT="/home/plstenge/k2_nt_20240530"

mkdir -p $RAW_DATA
mkdir -p $KRAKEN_CORE_DIR/{reports,outputs}
mkdir -p $KRAKEN_NT_DIR/{reports,outputs}
mkdir -p $KRONA_DIR/{core,nt,comparison}

cd $PROJECT_DIR

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
echo "ÉTAPE 1: Vérification/Téléchargement données"
echo "======================================================================="
echo ""

# Vérifier si données déjà présentes
cd $RAW_DATA

existing_count=$(ls -1 SRR*.fastq 2>/dev/null | wc -l)

if [ $existing_count -eq 20 ]; then
    echo "✅ Les 20 fichiers FASTQ sont déjà présents"
    echo "   Skip téléchargement SRA"
elif [ $existing_count -gt 0 ]; then
    echo "⚠️  $existing_count fichiers présents (attendu: 20)"
    echo "   Téléchargement des fichiers manquants..."
    
    # Installer sra-tools si besoin
    if ! command -v fastq-dump &> /dev/null; then
        echo "Installation sra-tools..."
        conda install -y -c bioconda sra-tools
    fi
    
    # Télécharger manquants
    for sample in "${!SAMPLES[@]}"; do
        srr="${SAMPLES[$sample]}"
        
        if [ ! -f "${srr}.fastq" ]; then
            echo "  Téléchargement: $sample ($srr)"
            
            prefetch $srr -O . 2>/dev/null
            fastq-dump --split-spot --skip-technical ${srr}/${srr}.sra -O . 2>/dev/null || \
            fastq-dump --split-spot --skip-technical $srr -O . 2>/dev/null
            
            rm -rf $srr  # Nettoyer dossier prefetch
        fi
    done
else
    echo "Aucun fichier présent. Téléchargement depuis SRA..."
    
    # Installer sra-tools
    if ! command -v fastq-dump &> /dev/null; then
        echo "Installation sra-tools..."
        conda install -y -c bioconda sra-tools
    fi
    
    # Télécharger tous
    for sample in $(echo "${!SAMPLES[@]}" | tr ' ' '\n' | sort); do
        srr="${SAMPLES[$sample]}"
        
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Téléchargement: $sample ($srr)"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        prefetch $srr -O . 2>&1 | grep -E "(Downloading|written)"
        fastq-dump --split-spot --skip-technical ${srr}/${srr}.sra -O . 2>&1 | grep -E "(Read|Written)"
        
        rm -rf $srr  # Nettoyer
        
        if [ -f "${srr}.fastq" ]; then
            reads=$(grep -c "^@" ${srr}.fastq)
            echo "  ✅ $reads reads"
        fi
        
        echo ""
    done
fi

# Vérification finale
echo "📊 Fichiers disponibles:"
ls -1 SRR*.fastq 2>/dev/null | wc -l
echo ""

cd $PROJECT_DIR

#################################################################################
# ÉTAPE 2: VÉRIFICATION OUTILS
#################################################################################

echo "======================================================================="
echo "ÉTAPE 2: Vérification outils"
echo "======================================================================="
echo ""

# Kraken2
if ! command -v kraken2 &> /dev/null; then
    echo "Installation Kraken2..."
    conda install -y -c bioconda kraken2
fi

# Krona
if ! command -v ktImportTaxonomy &> /dev/null; then
    echo "Installation Krona..."
    conda install -y -c bioconda krona
    ktUpdateTaxonomy.sh 2>/dev/null
fi

echo "✅ Kraken2: $(kraken2 --version 2>&1 | head -1)"
echo "✅ Krona installé"
echo ""

# Bases
if [ ! -d "$KRAKEN2_DB_CORE" ]; then
    echo "❌ Base CORE manquante: $KRAKEN2_DB_CORE"
    exit 1
fi

if [ ! -d "$KRAKEN2_DB_NT" ]; then
    echo "❌ Base NT manquante: $KRAKEN2_DB_NT"
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
        echo "  ⚠️  Manquant: $fastq"
        return 1
    fi
    
    if [ -f "$report" ]; then
        echo "  ✓ $sample ($db_name): déjà fait"
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
echo "✅ Classification BASE CORE terminée"
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
echo "✅ Classification BASE NT terminée"
echo ""

#################################################################################
# ÉTAPE 5-6: KRONA
#################################################################################

echo "======================================================================="
echo "ÉTAPES 5-6: Visualisations Krona"
echo "======================================================================="
echo ""

# Sites
declare -A SITES=(
    ["Poe"]="Poe1 Poe2 Poe3 Poe4"
    ["Kouare"]="Kouare1 Kouare2 Kouare3 Kouare4"
    ["GrandLagonNord"]="GrandLagonNord1 GrandLagonNord2 GrandLagonNord3"
    ["Pouebo"]="Pouebo1 Pouebo2 Pouebo2bis Pouebo4"
    ["Entrecasteaux"]="Entrecasteaux1 Entrecasteaux2 Entrecasteaux3 Entrecasteaux4"
)

# CORE
echo "--- BASE CORE ---"

for sample in $(echo "${!SAMPLES[@]}" | tr ' ' '\n' | sort); do
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

all_core=$(find ${KRAKEN_CORE_DIR}/reports -name "*_report.txt" -not -name "Control*" 2>/dev/null)
[ -n "$all_core" ] && ktImportTaxonomy -t 5 -m 3 -o "${KRONA_DIR}/core/ALL_SITES_core.html" $all_core 2>/dev/null

echo "  ✅ Krona CORE: $(ls -1 ${KRONA_DIR}/core/*.html 2>/dev/null | wc -l) fichiers"

# NT
echo "--- BASE NT ---"

for sample in $(echo "${!SAMPLES[@]}" | tr ' ' '\n' | sort); do
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

all_nt=$(find ${KRAKEN_NT_DIR}/reports -name "*_report.txt" -not -name "Control*" 2>/dev/null)
[ -n "$all_nt" ] && ktImportTaxonomy -t 5 -m 3 -o "${KRONA_DIR}/nt/ALL_SITES_nt.html" $all_nt 2>/dev/null

echo "  ✅ Krona NT: $(ls -1 ${KRONA_DIR}/nt/*.html 2>/dev/null | wc -l) fichiers"
echo ""

#################################################################################
# ÉTAPE 7: COMPARAISON
#################################################################################

echo "======================================================================="
echo "ÉTAPE 7: Comparaison CORE vs NT"
echo "======================================================================="
echo ""

comp_file="${KRONA_DIR}/comparison/comparison.tsv"

echo -e "Sample\tCore_total\tCore_class\tCore_%\tNT_total\tNT_class\tNT_%" > "$comp_file"

for sample in $(echo "${!SAMPLES[@]}" | tr ' ' '\n' | sort); do
    core_out="${KRAKEN_CORE_DIR}/outputs/${sample}_output.txt"
    nt_out="${KRAKEN_NT_DIR}/outputs/${sample}_output.txt"
    
    if [ -f "$core_out" ] && [ -f "$nt_out" ]; then
        core_tot=$(wc -l < "$core_out")
        core_cl=$(grep -c "^C" "$core_out" || echo 0)
        core_pct=$(awk "BEGIN {printf \"%.1f\", ($core_cl/$core_tot)*100}")
        
        nt_tot=$(wc -l < "$nt_out")
        nt_cl=$(grep -c "^C" "$nt_out" || echo 0)
        nt_pct=$(awk "BEGIN {printf \"%.1f\", ($nt_cl/$nt_tot)*100}")
        
        echo -e "${sample}\t${core_tot}\t${core_cl}\t${core_pct}\t${nt_tot}\t${nt_cl}\t${nt_pct}" >> "$comp_file"
    fi
done

echo "📊 COMPARAISON:"
cat "$comp_file" | column -t -s $'\t'
echo ""

#################################################################################
# ÉTAPE 8: TOP TAXA
#################################################################################

echo "======================================================================="
echo "ÉTAPE 8: Top taxa"
echo "======================================================================="
echo ""

echo "🏆 TOP 30 ESPÈCES - BASE CORE:"
cat ${KRAKEN_CORE_DIR}/reports/*_report.txt 2>/dev/null | \
    awk '$4=="S" {gsub(/^ +| +$/, "", $6); print $6"\t"$1}' | \
    awk '{sum[$1]+=$2} END {for (sp in sum) print sum[sp]"\t"sp}' | \
    sort -k1 -nr | head -30 | \
    awk '{printf "%8d × %s\n", $1, $2}'

echo ""
echo "🏆 TOP 30 ESPÈCES - BASE NT:"
cat ${KRAKEN_NT_DIR}/reports/*_report.txt 2>/dev/null | \
    awk '$4=="S" {gsub(/^ +| +$/, "", $6); print $6"\t"$1}' | \
    awk '{sum[$1]+=$2} END {for (sp in sum) print sum[sp]"\t"sp}' | \
    sort -k1 -nr | head -30 | \
    awk '{printf "%8d × %s\n", $1, $2}'

echo ""
echo "======================================================================="
echo "✅✅✅ TERMINÉ ✅✅✅"
echo "======================================================================="
echo ""
echo "Fichiers créés:"
echo "  → 04_krona/core/ALL_SITES_core.html"
echo "  → 04_krona/nt/ALL_SITES_nt.html"
echo "  → 04_krona/comparison/comparison.tsv"
echo ""
echo "Visualiser:"
echo "  firefox $PROJECT_DIR/04_krona/core/ALL_SITES_core.html"
echo "  firefox $PROJECT_DIR/04_krona/nt/ALL_SITES_nt.html"
echo ""
