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

# Base NCBI NT (existante sur votre cluster)
NCBI_NT_FASTA="/storage/biodatabanks/ncbi/NT/current/fasta/All/all.fasta"
NT_SKETCH="${SYLPH_DIR}/ncbi_nt.syldb"

mkdir -p $SYLPH_DIR $SKETCH_DIR $PROFILE_DIR $RESULTS_DIR

echo "======================================================================="
echo "PIPELINE SYLPH avec NCBI NT - eDNA marin Nouvelle-Calédonie"
echo "======================================================================="
echo ""

#################################################################################
# ÉTAPE 1: CRÉATION SKETCH NCBI NT (une seule fois, ~2-4h)
#################################################################################

if [ ! -f "$NT_SKETCH" ]; then
    echo "=== ÉTAPE 1: Création sketch NCBI NT ==="
    echo "Base FASTA: $NCBI_NT_FASTA"
    echo "Sketch de sortie: $NT_SKETCH"
    echo ""
    echo "⚠️  ATTENTION: Cette étape prend 2-4 heures et ~100-200 GB RAM"
    echo "   Le sketch sera réutilisable pour tous vos futurs projets !"
    echo ""
    
    # Créer le sketch de la base NT
    sylph sketch \
        -g "$NCBI_NT_FASTA" \
        -o "$NT_SKETCH" \
        -t 16 \
        --min-count 2
    
    if [ $? -eq 0 ]; then
        echo "✅ Sketch NCBI NT créé avec succès"
        
        # Taille du sketch
        sketch_size=$(du -h "$NT_SKETCH" | cut -f1)
        echo "   Taille: $sketch_size"
    else
        echo "❌ Échec création sketch NCBI NT"
        exit 1
    fi
else
    echo "=== ÉTAPE 1: Sketch NCBI NT déjà existant ==="
    sketch_size=$(du -h "$NT_SKETCH" | cut -f1)
    echo "✅ Sketch trouvé: $NT_SKETCH ($sketch_size)"
fi

echo ""

#################################################################################
# ÉTAPE 2: SKETCHING DES ÉCHANTILLONS
#################################################################################

echo "=== ÉTAPE 2: Sketching des échantillons ==="
echo ""

sample_count=0

for fastq in $RAW_DATA/*.fastq $RAW_DATA/*.fastq.gz; do
    [ ! -f "$fastq" ] && continue
    
    sample=$(basename "$fastq" | sed 's/\.\(fastq\|fq\)\(\.gz\)\?$//')
    sketch_out="${SKETCH_DIR}/${sample}.sylsp"
    
    if [ -f "$sketch_out" ]; then
        echo "  ✓ $sample (déjà fait)"
        ((sample_count++))
        continue
    fi
    
    echo "  Sketching: $sample"
    
    sylph sketch \
        -r "$fastq" \
        -o "$sketch_out" \
        -t 8
    
    if [ $? -eq 0 ]; then
        echo "    ✓ Terminé"
        ((sample_count++))
    else
        echo "    ❌ Échec"
    fi
done

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
        species_count=$(tail -n +2 "$profile_out" | wc -l)
        echo "    ✓ $species_count espèces détectées"
    else
        echo "    ❌ Échec"
    fi
done

echo ""
echo "✅ Profiling terminé"
echo ""

#################################################################################
# ÉTAPE 4: RÉSUMÉS ET STATISTIQUES
#################################################################################

echo "=== ÉTAPE 4: Création résumés ==="
echo ""

# Résumé par échantillon
summary_file="${RESULTS_DIR}/summary_all_samples.tsv"

echo -e "Sample\tTotal_species\tTop_species\tTop_abundance\tTop_ANI" > "$summary_file"

for profile in ${PROFILE_DIR}/*_profile.tsv; do
    [ ! -f "$profile" ] && continue
    
    sample=$(basename "$profile" _profile.tsv)
    
    # Stats
    total=$(tail -n +2 "$profile" | wc -l)
    
    # Top espèce (ligne avec plus grande abondance)
    top_line=$(tail -n +2 "$profile" | sort -k3 -nr | head -1)
    
    if [ -n "$top_line" ]; then
        top_species=$(echo "$top_line" | awk '{print $1}')
        top_abund=$(echo "$top_line" | awk '{print $3}')
        top_ani=$(echo "$top_line" | awk '{print $4}')
    else
        top_species="NA"
        top_abund="0"
        top_ani="0"
    fi
    
    echo -e "${sample}\t${total}\t${top_species}\t${top_abund}\t${top_ani}" >> "$summary_file"
done

echo "📊 RÉSUMÉ PAR ÉCHANTILLON:"
column -t -s $'\t' "$summary_file"
echo ""

# Top 50 espèces globales
echo "🏆 TOP 50 ESPÈCES (tous échantillons):"
echo ""

cat ${PROFILE_DIR}/*_profile.tsv | \
    tail -n +2 | \
    awk '{print $1"\t"$3}' | \
    awk '{sum[$1]+=$2} END {for (sp in sum) print sum[sp]"\t"sp}' | \
    sort -k1 -nr | \
    head -50 | \
    awk '{printf "%10.6f × %s\n", $1, $2}'

echo ""

# Focus groupes marins
echo "🌊 GROUPES MARINS DÉTECTÉS:"
echo ""

marine_summary="${RESULTS_DIR}/marine_taxa.tsv"

echo -e "Sample\tCnidaria\tMollusca\tEchinodermata\tCrustacea\tActinopterygii" > "$marine_summary"

for profile in ${PROFILE_DIR}/*_profile.tsv; do
    [ ! -f "$profile" ] && continue
    
    sample=$(basename "$profile" _profile.tsv)
    
    cnidaria=$(grep -i "Cnidaria\|Anthozoa\|Scleractinia" "$profile" | awk '{sum+=$3} END {printf "%.6f", sum+0}')
    mollusca=$(grep -i "Mollusca\|Gastropoda\|Bivalvia" "$profile" | awk '{sum+=$3} END {printf "%.6f", sum+0}')
    echino=$(grep -i "Echinodermata" "$profile" | awk '{sum+=$3} END {printf "%.6f", sum+0}')
    crusta=$(grep -i "Crustacea" "$profile" | awk '{sum+=$3} END {printf "%.6f", sum+0}')
    actino=$(grep -i "Actinopterygii\|Teleostei" "$profile" | awk '{sum+=$3} END {printf "%.6f", sum+0}')
    
    echo -e "${sample}\t${cnidaria}\t${mollusca}\t${echino}\t${crusta}\t${actino}" >> "$marine_summary"
done

column -t -s $'\t' "$marine_summary"

echo ""
echo "======================================================================="
echo "✅✅✅ PIPELINE SYLPH-NT TERMINÉ ✅✅✅"
echo "======================================================================="
echo ""
echo "FICHIERS CRÉÉS:"
echo "  → Sketch NCBI NT: $NT_SKETCH (réutilisable)"
echo "  → Profils: ${PROFILE_DIR}/*_profile.tsv"
echo "  → Résumés: ${RESULTS_DIR}/*.tsv"
echo ""
echo "Base NCBI NT couvre:"
echo "  ✅ Bactéries, Archées"
echo "  ✅ Eucaryotes (coraux, poissons, mollusques...)"
echo "  ✅ Plantes, Fungi, Protistes"
echo "  ✅ TOUT le règne Metazoa marin"
echo ""
echo "Votre eDNA marine est maintenant complètement profilé ! 🧬🌊"
echo ""
