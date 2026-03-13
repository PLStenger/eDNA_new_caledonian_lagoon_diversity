#!/usr/bin/env bash

#SBATCH --job-name=kraken2_NC_ASV
#SBATCH --cpus-per-task=36
#SBATCH --mem=120G
#SBATCH --time=24:00:00
#SBATCH --output=kraken2_NC_ASV.%j.out
#SBATCH --error=kraken2_NC_ASV.%j.err

set -euo pipefail

# Paramètres
KRAKEN2_DB="/home/plstenge/k2_core_nt_20250609"
THREADS=36
INPUT_FASTA="/home/plstenge/eDNA_new_caledonian_lagoon_diversity/01_raw_data/NC_ASV.fasta"
OUTDIR="/home/plstenge/eDNA_new_caledonian_lagoon_diversity/02_kraken2_core_nt_20250609"

mkdir -p "${OUTDIR}"

module load conda/4.12.0
source ~/.bashrc
conda activate metagenomics

# Rapport standard + table détaillée par ASV
kraken2 \
  --db "${KRAKEN2_DB}" \
  --threads "${THREADS}" \
  --use-names \
  --report "${OUTDIR}/NC_ASV.kraken2.report.txt" \
  --output "${OUTDIR}/NC_ASV.kraken2.classification.txt" \
  --fasta-input \
  "${INPUT_FASTA}"

# Optionnel : produire un rapport "Bracken-like" par taxon (format krona/visualisation)
# kraken2 \
#   --db "${KRAKEN2_DB}" \
#   --threads "${THREADS}" \
#   --use-names \
#   --report-zero-counts \
#   --report "${OUTDIR}/NC_ASV.kraken2.report_zero.txt" \
#   --fasta-input \
#   "${INPUT_FASTA}"

echo "Terminé. Résultats :"
echo " - Classification ASV : ${OUTDIR}/NC_ASV.kraken2.classification.txt"
echo " - Rapport global     : ${OUTDIR}/NC_ASV.kraken2.report.txt"
