#!/usr/bin/env bash
#SBATCH --job-name=99_SYLPH
#SBATCH --ntasks=1
#SBATCH -p smp
#SBATCH --mem=1000G
#SBATCH --mail-user=pierrelouis.stenger@gmail.com
#SBATCH --mail-type=ALL 
#SBATCH --error="/home/plstenge/eDNA_new_caledonian_lagoon_diversity/00_scripts/99_SYLPH.err"
#SBATCH --output="/home/plstenge/eDNA_new_caledonian_lagoon_diversity/00_scripts/99_SYLPH.out"

# CONFIGURATION
PROJECT_DIR=/home/plstenge/eDNA_new_caledonian_lagoon_diversity
RAW_DATA=${PROJECT_DIR}/01_raw_data/raw_sequences_comp
SYLPH_DIR=${PROJECT_DIR}/05_sylph_nt
SKETCH_DIR=${SYLPH_DIR}/sketches
PROFILE_DIR=${SYLPH_DIR}/profiles
RESULTS_DIR=${SYLPH_DIR}/results

# Base NCBI NT
NCBI_NT_FASTA="/storage/biodatabanks/ncbi/NT/current/fasta/All/all.fasta"
NT_SKETCH="${SYLPH_DIR}/ncbi_nt.syldb"

mkdir -p $SYLPH_DIR $SKETCH_DIR $PROFILE_DIR $RESULTS_DIR

echo "======================================================================="
echo "PIPELINE SYLPH avec NCBI NT - eDNA marin Nouvelle-Calédonie"
echo "======================================================================="
echo ""

sylph --version
echo ""

#################################################################################
# ÉTAPE 1: VÉRIFIER SKETCH NCBI NT
#################################################################################

# Correction nom fichier si nécessaire
if [ -f "${NT_SKETCH}.syldb" ]; then
    echo "⚠️  Correction du nom de fichier sketch..."
    mv "${NT_SKETCH}.syldb" "$NT_SKETCH"
fi

if [ ! -f "$NT_SKETCH" ]; then
    echo "❌ Sketch NCBI NT manquant: $NT_SKETCH"
    exit 1
else
    echo "=== ÉTAPE 1: Sketch NCBI NT déjà existant ==="
    sketch_size=$(du -h "$NT_SKETCH" | cut -f1)
    echo "✅ Sketch: $NT_SKETCH ($sketch_size)"
fi

echo ""

#################################################################################
# ÉTAPE 2: SKETCHING DES ÉCHANTILLONS
#################################################################################

echo "=== ÉTAPE 2: Sketching des échantillons ==="
echo ""

# Aller dans le dossier sketches pour que Sylph crée les fichiers là
cd $SKETCH_DIR

sample_count=0

for fastq in $RAW_DATA/*.fastq $RAW_DATA/*.fastq.gz; do
    [ ! -f "$fastq" ] && continue
    
    sample=$(basename "$fastq" | sed 's/\.\(fastq\|fq\)\(\.gz\)\?$//')
    sketch_out="${sample}.sylsp"
    
    if [ -f "$sketch_out" ]; then
        echo "  ✓ $sample (déjà fait)"
        ((sample_count++))
        continue
    fi
    
    echo "  Sketching: $sample"
    
    # Utiliser -d pour spécifier le nom du fichier de sortie pour les reads
    sylph sketch \
        -r "$fastq" \
        -d "$sketch_out" \
        -t 8 \
        2>&1 | grep -v "WARN.*-o is set"
    
    if [ $? -eq 0 ] && [ -f "$sketch_out" ]; then
        echo "    ✓ Terminé"
        ((sample_count++))
    else
        echo "    ❌ Échec"
    fi
done

cd $PROJECT_DIR

echo ""
echo "✅ Sketching terminé: $sample_count échantillons"
echo ""

#################################################################################
# ÉTAPE 3: PROFILING TAXONOMIQUE
#################################################################################

echo "=== ÉTAPE 3: Profiling taxonomique contre NCBI NT ==="
echo ""

for sketch in ${SKETCH_DIR}/*.sylsp; do
    [ ! -f "$sketch" ] && continue
    
    sample=$(basename "$sketch" .sylsp)
    profile_out="${PROFILE_DIR}/${sample}_profile.tsv"
    
    if [ -f "$profile_out" ]; then
        echo "  ✓ $sample (déjà fait)"
        continue
    fi
    
    echo "  Profiling: $sample"
    
    sylph profile \
        "$NT_SKETCH" \
        "$sketch" \
        -t 8 \
        > "$profile_out"
    
    if [ $? -eq 0 ]; then
        species_count=$(tail -n +2 "$profile_out" 2>/dev/null | wc -l)
        echo "    ✓ $species_count génomes détectés"
    else
        echo "    ❌ Échec"
    fi
done

echo ""
echo "✅ Profiling terminé"
echo ""

#################################################################################
# ÉTAPE 4: RÉSUMÉS
#################################################################################

echo "=== ÉTAPE 4: Création résumés ==="
echo ""

summary_file="${RESULTS_DIR}/summary_all_samples.tsv"

echo -e "Sample\tTotal_genomes\tTop_genome\tTop_abundance\tTop_ANI" > "$summary_file"

for profile in ${PROFILE_DIR}/*_profile.tsv; do
    [ ! -f "$profile" ] && continue
    
    sample=$(basename "$profile" _profile.tsv)
    
    # Stats
    total=$(tail -n +2 "$profile" 2>/dev/null | wc -l)
    
    if [ "$total" -gt 0 ]; then
        # Top genome
        top_line=$(tail -n +2 "$profile" | sort -k3 -nr | head -1)
        
        top_genome=$(echo "$top_line" | awk '{print $1}')
        top_abund=$(echo "$top_line" | awk '{print $3}')
        top_ani=$(echo "$top_line" | awk '{print $4}')
    else
        top_genome="NA"
        top_abund="0"
        top_ani="0"
    fi
    
    echo -e "${sample}\t${total}\t${top_genome}\t${top_abund}\t${top_ani}" >> "$summary_file"
done

echo "📊 RÉSUMÉ PAR ÉCHANTILLON:"
column -t -s$'\t' "$summary_file"
echo ""

# Top 50 génomes
echo "🏆 TOP 50 GÉNOMES (tous échantillons):"
echo ""

cat ${PROFILE_DIR}/*_profile.tsv 2>/dev/null | \
    tail -n +2 | \
    awk '{print $1"\t"$3}' | \
    awk '{sum[$1]+=$2} END {for (sp in sum) print sum[sp]"\t"sp}' | \
    sort -k1 -nr | \
    head -50 | \
    awk '{printf "%10.6f × %s\n", $1, $2}'

echo ""

# Focus groupes marins
echo "🌊 GROUPES MARINS PRINCIPAUX:"
echo ""

marine_summary="${RESULTS_DIR}/marine_taxa.tsv"

echo -e "Sample\tCnidaria\tMollusca\tCrustacea\tActinopterygii" > "$marine_summary"

for profile in ${PROFILE_DIR}/*_profile.tsv; do
    [ ! -f "$profile" ] && continue
    
    sample=$(basename "$profile" _profile.tsv)
    
    cnidaria=$(grep -i "Cnidaria\|Anthozoa\|coral" "$profile" 2>/dev/null | awk '{sum+=$3} END {printf "%.6f", sum+0}')
    mollusca=$(grep -i "Mollusca\|Gastropoda\|Bivalvia" "$profile" 2>/dev/null | awk '{sum+=$3} END {printf "%.6f", sum+0}')
    crusta=$(grep -i "Crustacea\|Decapoda" "$profile" 2>/dev/null | awk '{sum+=$3} END {printf "%.6f", sum+0}')
    actino=$(grep -i "Actinopterygii\|Teleostei\|fish" "$profile" 2>/dev/null | awk '{sum+=$3} END {printf "%.6f", sum+0}')
    
    echo -e "${sample}\t${cnidaria}\t${mollusca}\t${crusta}\t${actino}" >> "$marine_summary"
done

column -t -s$'\t' "$marine_summary"

echo ""

#################################################################################
# RÉSUMÉ FINAL
#################################################################################

echo "======================================================================="
echo "✅✅✅ PIPELINE SYLPH-NT TERMINÉ ✅✅✅"
echo "======================================================================="
echo ""
echo "FICHIERS CRÉÉS:"
echo "  → Sketch NCBI NT: $NT_SKETCH (14G)"
echo "  → Sketches échantillons: ${SKETCH_DIR}/*.sylsp ($(ls ${SKETCH_DIR}/*.sylsp 2>/dev/null | wc -l) fichiers)"
echo "  → Profils: ${PROFILE_DIR}/*_profile.tsv ($(ls ${PROFILE_DIR}/*_profile.tsv 2>/dev/null | wc -l) fichiers)"
echo "  → Résumés:"
echo "      • ${RESULTS_DIR}/summary_all_samples.tsv"
echo "      • ${RESULTS_DIR}/marine_taxa.tsv"
echo ""
echo "Analyse taxonomique terminée ! 🧬🌊"
echo ""
