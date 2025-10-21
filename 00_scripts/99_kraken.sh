#!/bin/bash
#SBATCH --job-name=99_kraken
#SBATCH --ntasks=1
#SBATCH -p smp
#SBATCH --mem=1000G
#SBATCH --mail-user=pierrelouis.stenger@gmail.com
#SBATCH --mail-type=ALL 
#SBATCH --error="/home/plstenge/eDNA_new_caledonian_lagoon_diversity/00_scripts/99_kraken.err"
#SBATCH --output="/home/plstenge/eDNA_new_caledonian_lagoon_diversity/00_scripts/99_kraken.out"

# PIPELINE COMPLET - Téléchargement SRA + Kraken2 (2 bases) + Krona

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
echo "PIPELINE COMPLET - Kraken2 (2 bases) + Krona"
echo "Nouvelle-Calédonie - Biodiversité marine récifale"
echo "======================================================================="
echo ""
echo "Projet: $PROJECT_DIR"
echo "Sites: Poe, Kouaré, Grand Lagon Nord, Pouébo, Entrecasteaux"
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
# ÉTAPE 1: TÉLÉCHARGEMENT SRA
#################################################################################

echo "======================================================================="
echo "ÉTAPE 1: Téléchargement données SRA"
echo "======================================================================="
echo ""

# Vérifier sra-tools
if ! command -v fasterq-dump &> /dev/null; then
    echo "Installation de sra-tools..."
    conda install -y -c bioconda sra-tools
fi

# Configurer SRA toolkit
vdb-config --prefetch-to-cwd

cd $RAW_DATA

download_srr() {
    local sample=$1
    local srr=$2
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Téléchargement: $sample ($srr)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [ -f "${srr}.fastq" ] || [ -f "${srr}.fastq.gz" ]; then
        echo "  ✓ Déjà téléchargé"
        return 0
    fi
    
    # Télécharger avec fasterq-dump
    fasterq-dump $srr \
        --split-spot \
        --skip-technical \
        --threads 4 \
        --progress \
        --temp .
    
    if [ $? -eq 0 ]; then
        echo "  ✓ Téléchargement réussi"
        
        # Vérifier qualité
        total_reads=$(grep -c "^@" ${srr}.fastq || echo 0)
        echo "  Total reads: $total_reads"
    else
        echo "  ❌ Échec téléchargement"
        return 1
    fi
    
    echo ""
}

echo "Téléchargement des 20 échantillons..."
echo ""

for sample in $(echo "${!SAMPLES[@]}" | tr ' ' '\n' | sort); do
    download_srr "$sample" "${SAMPLES[$sample]}"
done

echo "✓ Téléchargement terminé"
echo ""

# Stats globales
fastq_count=$(ls -1 *.fastq 2>/dev/null | wc -l)
echo "📊 Fichiers FASTQ: $fastq_count / 20"
echo ""

cd $PROJECT_DIR

#################################################################################
# ÉTAPE 2: INSTALLATION OUTILS
#################################################################################

echo "======================================================================="
echo "ÉTAPE 2: Vérification des outils"
echo "======================================================================="
echo ""

# Kraken2
if ! command -v kraken2 &> /dev/null; then
    echo "Installation de Kraken2..."
    conda install -y -c bioconda kraken2
fi

# KronaTools
if ! command -v ktImportTaxonomy &> /dev/null; then
    echo "Installation de KronaTools..."
    conda install -y -c bioconda krona
    ktUpdateTaxonomy.sh
fi

echo "✓ Kraken2: $(kraken2 --version 2>&1 | head -1)"
echo "✓ Krona installé"
echo ""

# Vérifier bases de données
echo "Vérification bases Kraken2:"
if [ -d "$KRAKEN2_DB_CORE" ]; then
    echo "  ✅ Base CORE: $KRAKEN2_DB_CORE"
else
    echo "  ❌ Base CORE manquante: $KRAKEN2_DB_CORE"
    exit 1
fi

if [ -d "$KRAKEN2_DB_NT" ]; then
    echo "  ✅ Base NT: $KRAKEN2_DB_NT"
else
    echo "  ❌ Base NT manquante: $KRAKEN2_DB_NT"
    exit 1
fi

echo ""

#################################################################################
# ÉTAPE 3: CLASSIFICATION KRAKEN2 - BASE CORE
#################################################################################

echo "======================================================================="
echo "ÉTAPE 3: Classification Kraken2 - BASE CORE"
echo "======================================================================="
echo ""

classify_kraken() {
    local sample=$1
    local srr=$2
    local db=$3
    local output_dir=$4
    local db_name=$5
    
    local fastq="${RAW_DATA}/${srr}.fastq"
    local report="${output_dir}/reports/${sample}_${db_name}_report.txt"
    local output="${output_dir}/outputs/${sample}_${db_name}_output.txt"
    
    if [ ! -f "$fastq" ]; then
        echo "  ⚠️  Fichier manquant: $fastq"
        return 1
    fi
    
    if [ -f "$report" ]; then
        echo "  ✓ $sample ($db_name): déjà classifié"
        return 0
    fi
    
    echo "  Classification: $sample avec $db_name..."
    
    kraken2 \
        --db "$db" \
        --threads 8 \
        --report "$report" \
        --output "$output" \
        --use-names \
        "$fastq" 2>&1 | grep -E "(processed|classified)"
    
    if [ $? -eq 0 ] && [ -f "$report" ]; then
        # Stats
        total=$(wc -l < "$output")
        classified=$(grep -c "^C" "$output" || echo 0)
        percent=$(awk "BEGIN {printf \"%.1f\", ($classified/$total)*100}")
        
        echo "    Total: $total | Classifiés: $classified ($percent%)"
    else
        echo "    ❌ Échec"
        return 1
    fi
}

echo "Classification avec BASE CORE (k2_core_nt)..."
echo ""

for sample in $(echo "${!SAMPLES[@]}" | tr ' ' '\n' | sort); do
    classify_kraken "$sample" "${SAMPLES[$sample]}" "$KRAKEN2_DB_CORE" "$KRAKEN_CORE_DIR" "core"
done

echo ""
echo "✓ Classification BASE CORE terminée"
echo ""

#################################################################################
# ÉTAPE 4: CLASSIFICATION KRAKEN2 - BASE NT
#################################################################################

echo "======================================================================="
echo "ÉTAPE 4: Classification Kraken2 - BASE NT"
echo "======================================================================="
echo ""

echo "Classification avec BASE NT (k2_nt)..."
echo ""

for sample in $(echo "${!SAMPLES[@]}" | tr ' ' '\n' | sort); do
    classify_kraken "$sample" "${SAMPLES[$sample]}" "$KRAKEN2_DB_NT" "$KRAKEN_NT_DIR" "nt"
done

echo ""
echo "✓ Classification BASE NT terminée"
echo ""

#################################################################################
# ÉTAPE 5: VISUALISATIONS KRONA - BASE CORE
#################################################################################

echo "======================================================================="
echo "ÉTAPE 5: Visualisations Krona - BASE CORE"
echo "======================================================================="
echo ""

# Individuels
echo "--- Graphiques individuels (BASE CORE) ---"
for sample in $(echo "${!SAMPLES[@]}" | tr ' ' '\n' | sort); do
    report="${KRAKEN_CORE_DIR}/reports/${sample}_core_report.txt"
    
    if [ ! -f "$report" ]; then
        continue
    fi
    
    ktImportTaxonomy \
        -t 5 -m 3 \
        -o "${KRONA_DIR}/core/${sample}_core_krona.html" \
        "$report" 2>/dev/null
    
    echo "  ✓ ${sample}_core_krona.html"
done

# Par site
echo ""
echo "--- Par site (BASE CORE) ---"

declare -A SITES=(
    ["Poe"]="Poe1 Poe2 Poe3 Poe4"
    ["Kouare"]="Kouare1 Kouare2 Kouare3 Kouare4"
    ["GrandLagonNord"]="GrandLagonNord1 GrandLagonNord2 GrandLagonNord3"
    ["Pouebo"]="Pouebo1 Pouebo2 Pouebo2bis Pouebo4"
    ["Entrecasteaux"]="Entrecasteaux1 Entrecasteaux2 Entrecasteaux3 Entrecasteaux4"
)

for site in "${!SITES[@]}"; do
    reports=""
    for s in ${SITES[$site]}; do
        r="${KRAKEN_CORE_DIR}/reports/${s}_core_report.txt"
        [ -f "$r" ] && reports="$reports $r"
    done
    
    if [ -n "$reports" ]; then
        ktImportTaxonomy \
            -t 5 -m 3 \
            -o "${KRONA_DIR}/core/${site}_core_krona.html" \
            $reports 2>/dev/null
        
        echo "  ✓ ${site}_core_krona.html"
    fi
done

# Global
echo ""
echo "--- Global (BASE CORE) ---"
all_core=$(find ${KRAKEN_CORE_DIR}/reports -name "*_core_report.txt" -not -name "Control*")
ktImportTaxonomy \
    -t 5 -m 3 \
    -o "${KRONA_DIR}/core/ALL_SITES_core_krona.html" \
    $all_core 2>/dev/null

echo "  ✓ ALL_SITES_core_krona.html"
echo ""

#################################################################################
# ÉTAPE 6: VISUALISATIONS KRONA - BASE NT
#################################################################################

echo "======================================================================="
echo "ÉTAPE 6: Visualisations Krona - BASE NT"
echo "======================================================================="
echo ""

# Individuels
echo "--- Graphiques individuels (BASE NT) ---"
for sample in $(echo "${!SAMPLES[@]}" | tr ' ' '\n' | sort); do
    report="${KRAKEN_NT_DIR}/reports/${sample}_nt_report.txt"
    
    if [ ! -f "$report" ]; then
        continue
    fi
    
    ktImportTaxonomy \
        -t 5 -m 3 \
        -o "${KRONA_DIR}/nt/${sample}_nt_krona.html" \
        "$report" 2>/dev/null
    
    echo "  ✓ ${sample}_nt_krona.html"
done

# Par site
echo ""
echo "--- Par site (BASE NT) ---"

for site in "${!SITES[@]}"; do
    reports=""
    for s in ${SITES[$site]}; do
        r="${KRAKEN_NT_DIR}/reports/${s}_nt_report.txt"
        [ -f "$r" ] && reports="$reports $r"
    done
    
    if [ -n "$reports" ]; then
        ktImportTaxonomy \
            -t 5 -m 3 \
            -o "${KRONA_DIR}/nt/${site}_nt_krona.html" \
            $reports 2>/dev/null
        
        echo "  ✓ ${site}_nt_krona.html"
    fi
done

# Global
echo ""
echo "--- Global (BASE NT) ---"
all_nt=$(find ${KRAKEN_NT_DIR}/reports -name "*_nt_report.txt" -not -name "Control*")
ktImportTaxonomy \
    -t 5 -m 3 \
    -o "${KRONA_DIR}/nt/ALL_SITES_nt_krona.html" \
    $all_nt 2>/dev/null

echo "  ✓ ALL_SITES_nt_krona.html"
echo ""

#################################################################################
# ÉTAPE 7: COMPARAISON DES DEUX BASES
#################################################################################

echo "======================================================================="
echo "ÉTAPE 7: Comparaison BASE CORE vs BASE NT"
echo "======================================================================="
echo ""

comparison_file="${KRONA_DIR}/comparison/core_vs_nt_comparison.tsv"

echo -e "Sample\tCore_total\tCore_classified\tCore_percent\tNT_total\tNT_classified\tNT_percent" > "$comparison_file"

for sample in $(echo "${!SAMPLES[@]}" | tr ' ' '\n' | sort); do
    core_output="${KRAKEN_CORE_DIR}/outputs/${sample}_core_output.txt"
    nt_output="${KRAKEN_NT_DIR}/outputs/${sample}_nt_output.txt"
    
    if [ -f "$core_output" ] && [ -f "$nt_output" ]; then
        # Stats CORE
        core_total=$(wc -l < "$core_output")
        core_class=$(grep -c "^C" "$core_output" || echo 0)
        core_pct=$(awk "BEGIN {printf \"%.1f\", ($core_class/$core_total)*100}")
        
        # Stats NT
        nt_total=$(wc -l < "$nt_output")
        nt_class=$(grep -c "^C" "$nt_output" || echo 0)
        nt_pct=$(awk "BEGIN {printf \"%.1f\", ($nt_class/$nt_total)*100}")
        
        echo -e "${sample}\t${core_total}\t${core_class}\t${core_pct}%\t${nt_total}\t${nt_class}\t${nt_pct}%" >> "$comparison_file"
    fi
done

echo "📊 COMPARAISON DES BASES:"
echo ""
cat "$comparison_file" | column -t -s $'\t'
echo ""

#################################################################################
# ÉTAPE 8: TOP TAXA PAR BASE
#################################################################################

echo "======================================================================="
echo "ÉTAPE 8: Top taxa détectés"
echo "======================================================================="
echo ""

echo "🏆 TOP 30 ESPÈCES - BASE CORE:"
cat ${KRAKEN_CORE_DIR}/reports/*_core_report.txt | \
    awk '$4=="S" {gsub(/^ +| +$/, "", $6); print $6"\t"$1}' | \
    awk '{sum[$1]+=$2} END {for (sp in sum) print sum[sp]"\t"sp}' | \
    sort -k1 -nr | head -30 | \
    awk '{printf "%8d × %s\n", $1, $2}'

echo ""
echo "🏆 TOP 30 ESPÈCES - BASE NT:"
cat ${KRAKEN_NT_DIR}/reports/*_nt_report.txt | \
    awk '$4=="S" {gsub(/^ +| +$/, "", $6); print $6"\t"$1}' | \
    awk '{sum[$1]+=$2} END {for (sp in sum) print sum[sp]"\t"sp}' | \
    sort -k1 -nr | head -30 | \
    awk '{printf "%8d × %s\n", $1, $2}'

echo ""

#################################################################################
# ÉTAPE 9: FOCUS FAUNE MARINE
#################################################################################

echo "======================================================================="
echo "ÉTAPE 9: Focus sur la faune marine récifale"
echo "======================================================================="
echo ""

marine_core="${KRONA_DIR}/comparison/marine_taxa_core.tsv"
marine_nt="${KRONA_DIR}/comparison/marine_taxa_nt.tsv"

# CORE
echo -e "Sample\tCnidaria\tMollusca\tEchinodermata\tCrustacea\tActinopteri" > "$marine_core"

for sample in $(echo "${!SAMPLES[@]}" | tr ' ' '\n' | sort); do
    report="${KRAKEN_CORE_DIR}/reports/${sample}_core_report.txt"
    
    if [ ! -f "$report" ]; then
        continue
    fi
    
    cnidaria=$(grep -i "Cnidaria" "$report" | awk '{sum+=$1} END {print sum+0}')
    mollusca=$(grep -i "Mollusca" "$report" | awk '{sum+=$1} END {print sum+0}')
    echino=$(grep -i "Echinodermata" "$report" | awk '{sum+=$1} END {print sum+0}')
    crusta=$(grep -i "Crustacea" "$report" | awk '{sum+=$1} END {print sum+0}')
    actino=$(grep -i "Actinopteri" "$report" | awk '{sum+=$1} END {print sum+0}')
    
    echo -e "${sample}\t${cnidaria}\t${mollusca}\t${echino}\t${crusta}\t${actino}" >> "$marine_core"
done

# NT
echo -e "Sample\tCnidaria\tMollusca\tEchinodermata\tCrustacea\tActinopteri" > "$marine_nt"

for sample in $(echo "${!SAMPLES[@]}" | tr ' ' '\n' | sort); do
    report="${KRAKEN_NT_DIR}/reports/${sample}_nt_report.txt"
    
    if [ ! -f "$report" ]; then
        continue
    fi
    
    cnidaria=$(grep -i "Cnidaria" "$report" | awk '{sum+=$1} END {print sum+0}')
    mollusca=$(grep -i "Mollusca" "$report" | awk '{sum+=$1} END {print sum+0}')
    echino=$(grep -i "Echinodermata" "$report" | awk '{sum+=$1} END {print sum+0}')
    crusta=$(grep -i "Crustacea" "$report" | awk '{sum+=$1} END {print sum+0}')
    actino=$(grep -i "Actinopteri" "$report" | awk '{sum+=$1} END {print sum+0}')
    
    echo -e "${sample}\t${cnidaria}\t${mollusca}\t${echino}\t${crusta}\t${actino}" >> "$marine_nt"
done

echo "📊 GROUPES MARINS (BASE CORE):"
cat "$marine_core" | column -t -s $'\t'

echo ""
echo "📊 GROUPES MARINS (BASE NT):"
cat "$marine_nt" | column -t -s $'\t'

echo ""

#################################################################################
# RÉSUMÉ FINAL
#################################################################################

echo ""
echo "======================================================================="
echo "✓✓✓ PIPELINE TERMINÉ ✓✓✓"
echo "======================================================================="
echo ""
echo "STRUCTURE DES FICHIERS:"
echo ""
echo "01_raw_data/"
echo "  ├─ *.fastq (20 échantillons SRA)"
echo ""
echo "02_kraken2_core_nt/"
echo "  ├─ reports/*.txt"
echo "  └─ outputs/*.txt"
echo ""
echo "03_kraken2_nt/"
echo "  ├─ reports/*.txt"
echo "  └─ outputs/*.txt"
echo ""
echo "04_krona/"
echo "  ├─ core/*.html (visualisations BASE CORE)"
echo "  ├─ nt/*.html (visualisations BASE NT)"
echo "  └─ comparison/*.tsv (comparaisons)"
echo ""
echo "VISUALISATIONS INTERACTIVES:"
echo ""
echo "  BASE CORE:"
echo "    → 04_krona/core/ALL_SITES_core_krona.html"
echo ""
echo "  BASE NT:"
echo "    → 04_krona/nt/ALL_SITES_nt_krona.html"
echo ""
echo "COMPARAISON:"
echo "  → 04_krona/comparison/core_vs_nt_comparison.tsv"
echo ""
echo "Pour visualiser:"
echo "  firefox 04_krona/core/ALL_SITES_core_krona.html"
echo "  firefox 04_krona/nt/ALL_SITES_nt_krona.html"
echo ""
echo "Bonne exploration! 🪸🐚🦔🌊"
echo ""
