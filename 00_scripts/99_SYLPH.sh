#!/usr/bin/env bash
#SBATCH --job-name=99_SYLPH_NT
#SBATCH --ntasks=1
#SBATCH -p smp
#SBATCH --mem=1000G
#SBATCH --mail-user=pierrelouis.stenger@gmail.com
#SBATCH --mail-type=ALL 
#SBATCH --error="/home/plstenge/eDNA_new_caledonian_lagoon_diversity/00_scripts/99_SYLPH_NT.err"
#SBATCH --output="/home/plstenge/eDNA_new_caledonian_lagoon_diversity/00_scripts/99_SYLPH_NT.out"

PROJECT_DIR=/home/plstenge/eDNA_new_caledonian_lagoon_diversity
RAW_DATA=${PROJECT_DIR}/01_raw_data/raw_sequences_comp
SYLPH_DIR=${PROJECT_DIR}/05_sylph_nt
SKETCH_DIR=${SYLPH_DIR}/sketches
PROFILE_DIR=${SYLPH_DIR}/profiles
RESULTS_DIR=${SYLPH_DIR}/results

NCBI_NT_FASTA="/storage/biodatabanks/ncbi/NT/current/fasta/All/all.fasta"
NT_SKETCH="${SYLPH_DIR}/ncbi_nt.syldb"

mkdir -p $SYLPH_DIR $SKETCH_DIR $PROFILE_DIR $RESULTS_DIR

echo "======================================================================="
echo "PIPELINE SYLPH avec NCBI NT"
echo "======================================================================="
echo ""

sylph --version
echo ""

# Correction nom fichier si nécessaire
if [ -f "${NT_SKETCH}.syldb" ]; then
    mv "${NT_SKETCH}.syldb" "$NT_SKETCH"
fi

if [ ! -f "$NT_SKETCH" ]; then
    echo "❌ Sketch NCBI NT manquant"
    exit 1
fi

echo "✅ Sketch NCBI NT: $NT_SKETCH ($(du -h "$NT_SKETCH" | cut -f1))"
echo ""

#################################################################################
# ÉTAPE 2: SKETCHING
#################################################################################

echo "=== Sketching des échantillons ==="
echo ""

cd $SKETCH_DIR

sample_count=0

for fastq in $RAW_DATA/*.fastq $RAW_DATA/*.fastq.gz; do
    [ ! -f "$fastq" ] && continue
    
    sample=$(basename "$fastq" | sed 's/\.\(fastq\|fq\)\(\.gz\)\?$//')
    
    # Sylph crée un DOSSIER avec ce nom, pas un fichier
    sketch_dir="${sample}.sylsp"
    sketch_file="${sketch_dir}/${sample}.fastq.sylsp"
    
    # Si le sketch existe déjà
    if [ -f "$sketch_file" ]; then
        echo "  ✓ $sample (déjà fait)"
        ((sample_count++))
        continue
    fi
    
    echo "  Sketching: $sample"
    
    # Sylph créera automatiquement le dossier
    sylph sketch \
        -r "$fastq" \
        -d "$sketch_dir" \
        -t 8 \
        2>&1 | grep -v "WARN"
    
    # Vérifier si le fichier sketch a été créé
    if [ -f "$sketch_file" ]; then
        echo "    ✓ Sketch créé"
        ((sample_count++))
    else
        echo "    ⚠️  Sketch pas créé (peut être ignoré pour profiling)"
    fi
done

cd $PROJECT_DIR

echo ""
echo "✅ Sketching: $sample_count / 20 échantillons"
echo ""

#################################################################################
# ÉTAPE 3: PROFILING - Utiliser directement les dossiers sketches
#################################################################################

echo "=== Profiling taxonomique ==="
echo ""

profile_count=0

for sketch_dir in ${SKETCH_DIR}/*.sylsp; do
    [ ! -d "$sketch_dir" ] && continue
    
    sample=$(basename "$sketch_dir" .sylsp)
    profile_out="${PROFILE_DIR}/${sample}_profile.tsv"
    
    if [ -f "$profile_out" ]; then
        echo "  ✓ $sample (déjà fait)"
        ((profile_count++))
        continue
    fi
    
    echo "  Profiling: $sample"
    
    # Passer le DOSSIER sketch, pas le fichier
    sylph profile \
        "$NT_SKETCH" \
        "$sketch_dir" \
        -t 8 \
        > "$profile_out" 2>&1
    
    if [ $? -eq 0 ] && [ -s "$profile_out" ]; then
        genomes=$(tail -n +2 "$profile_out" 2>/dev/null | wc -l)
        echo "    ✓ $genomes génomes"
        ((profile_count++))
    else
        echo "    ❌ Échec"
        rm "$profile_out"
    fi
done

echo ""
echo "✅ Profiling: $profile_count profils créés"
echo ""

#################################################################################
# ÉTAPE 4: RÉSUMÉS
#################################################################################

echo "=== Résumés ==="
echo ""

summary_file="${RESULTS_DIR}/summary_all_samples.tsv"

echo -e "Sample\tTotal_genomes\tTop_genome\tTop_abundance" > "$summary_file"

for profile in ${PROFILE_DIR}/*_profile.tsv; do
    [ ! -f "$profile" ] && continue
    
    sample=$(basename "$profile" _profile.tsv)
    total=$(tail -n +2 "$profile" 2>/dev/null | wc -l)
    
    if [ "$total" -gt 0 ]; then
        top_line=$(tail -n +2 "$profile" | sort -k3 -nr | head -1)
        top_genome=$(echo "$top_line" | awk '{print $1}')
        top_abund=$(echo "$top_line" | awk '{printf "%.6f", $3}')
    else
        top_genome="NA"
        top_abund="0"
    fi
    
    echo -e "${sample}\t${total}\t${top_genome}\t${top_abund}" >> "$summary_file"
done

echo "📊 RÉSUMÉ:"
column -t -s$'\t' "$summary_file"

echo ""
echo "======================================================================="
echo "✅ TERMINÉ"
echo "======================================================================="
echo ""
echo "Résultats dans: ${RESULTS_DIR}/"
echo ""
