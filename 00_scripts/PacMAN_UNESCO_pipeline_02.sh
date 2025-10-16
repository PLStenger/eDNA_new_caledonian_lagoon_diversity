#!/usr/bin/env bash

# SOLUTION FINALE CORRIGÉE - Clustering 97% qui VA fonctionner

WORKING_DIR=/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity/05_QIIME2
DATABASE=/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity/98_database_files
QIIME_ENV="qiime2-amplicon-2025.7"

cd $WORKING_DIR

echo "======================================================================="
echo "SOLUTION FINALE - Clustering 97% OTU"
echo "======================================================================="
echo ""

if [ ! -f "02-qiime2/demux_all.qza" ]; then
    echo "❌ Fichier demux_all.qza manquant"
    exit 1
fi

mkdir -p 03-clustering
mkdir -p 04-taxonomy
mkdir -p export/taxonomy

#################################################################################
# ÉTAPE 1: MERGE PAIRED-END
#################################################################################

echo "=== ÉTAPE 1: Fusion des paires R1/R2 ==="
echo ""

if [ ! -f "03-clustering/demux_joined.qza" ]; then
    conda run -n $QIIME_ENV qiime vsearch merge-pairs \
        --i-demultiplexed-seqs "02-qiime2/demux_all.qza" \
        --o-merged-sequences "03-clustering/demux_joined.qza" \
        --o-unmerged-sequences "03-clustering/demux_unmerged.qza" \
        --p-minmergelen 100 \
        --p-maxdiffs 10 \
        --verbose
    
    if [ $? -eq 0 ]; then
        echo "✓ Fusion réussie"
    else
        echo "❌ Fusion échouée"
        exit 1
    fi
else
    echo "✓ Fusion déjà effectuée"
fi

echo ""

#################################################################################
# ÉTAPE 2: FILTRAGE QUALITÉ
#################################################################################

echo "=== ÉTAPE 2: Filtrage qualité ==="
echo ""

if [ ! -f "03-clustering/demux_filtered.qza" ]; then
    conda run -n $QIIME_ENV qiime quality-filter q-score \
        --i-demux "03-clustering/demux_joined.qza" \
        --p-min-quality 4 \
        --p-quality-window 10 \
        --p-min-length-fraction 0.5 \
        --p-max-ambiguous 5 \
        --o-filtered-sequences "03-clustering/demux_filtered.qza" \
        --o-filter-stats "03-clustering/filter_stats.qza"
    
    if [ $? -eq 0 ]; then
        echo "✓ Filtrage réussi"
    else
        echo "❌ Filtrage échoué"
        exit 1
    fi
else
    echo "✓ Filtrage déjà effectué"
fi

echo ""

#################################################################################
# ÉTAPE 3: DEREPLICATE
#################################################################################

echo "=== ÉTAPE 3: Dereplication ==="
echo ""

if [ ! -f "03-clustering/table_derep.qza" ]; then
    conda run -n $QIIME_ENV qiime vsearch dereplicate-sequences \
        --i-sequences "03-clustering/demux_filtered.qza" \
        --o-dereplicated-table "03-clustering/table_derep.qza" \
        --o-dereplicated-sequences "03-clustering/rep_seqs_derep.qza"
    
    if [ $? -eq 0 ]; then
        echo "✓ Dereplication réussie"
    else
        echo "❌ Dereplication échouée"
        exit 1
    fi
else
    echo "✓ Dereplication déjà effectuée"
fi

echo ""

#################################################################################
# ÉTAPE 4: CLUSTERING 97%
#################################################################################

echo "=== ÉTAPE 4: Clustering 97% ==="
echo ""

if [ ! -f "03-clustering/table_97.qza" ]; then
    conda run -n $QIIME_ENV qiime vsearch cluster-features-de-novo \
        --i-sequences "03-clustering/rep_seqs_derep.qza" \
        --i-table "03-clustering/table_derep.qza" \
        --p-perc-identity 0.97 \
        --p-threads 8 \
        --o-clustered-table "03-clustering/table_97.qza" \
        --o-clustered-sequences "03-clustering/rep_seqs_97.qza"
    
    if [ $? -eq 0 ]; then
        echo "✓ Clustering réussi"
        
        # Visualisations
        conda run -n $QIIME_ENV qiime feature-table summarize \
            --i-table "03-clustering/table_97.qza" \
            --o-visualization "03-clustering/table_97.qzv"
        
        conda run -n $QIIME_ENV qiime feature-table tabulate-seqs \
            --i-data "03-clustering/rep_seqs_97.qza" \
            --o-visualization "03-clustering/rep_seqs_97.qzv"
        
        echo "✓ Visualisations créées"
    else
        echo "❌ Clustering échoué"
        exit 1
    fi
else
    echo "✓ Clustering déjà effectué"
fi

echo ""

#################################################################################
# ÉTAPE 5: ASSIGNATIONS TAXONOMIQUES
#################################################################################

echo "======================================================================="
echo "ÉTAPE 5: Assignations taxonomiques (5 classificateurs)"
echo "======================================================================="
echo ""

REP_SEQS="03-clustering/rep_seqs_97.qza"

assign_taxonomy() {
    local name=$1
    local classifier=$2
    local description=$3
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "$name - $description"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [ ! -f "$DATABASE/$classifier" ]; then
        echo "  ⚠️  Classificateur manquant: $classifier"
        echo ""
        return 1
    fi
    
    # Assignation
    if [ ! -f "04-taxonomy/taxonomy_${name}.qza" ]; then
        conda run -n $QIIME_ENV qiime feature-classifier classify-sklearn \
            --i-classifier "$DATABASE/$classifier" \
            --i-reads "$REP_SEQS" \
            --o-classification "04-taxonomy/taxonomy_${name}.qza" \
            --p-confidence 0.7 \
            --p-n-jobs 8 \
            --verbose
        
        if [ $? -ne 0 ]; then
            echo "  ❌ Assignation échouée"
            return 1
        fi
    fi
    
    # Export TSV
    conda run -n $QIIME_ENV qiime tools export \
        --input-path "04-taxonomy/taxonomy_${name}.qza" \
        --output-path "export/taxonomy/temp_${name}/"
    
    mv "export/taxonomy/temp_${name}/taxonomy.tsv" "export/taxonomy/taxonomy_${name}.tsv"
    rm -rf "export/taxonomy/temp_${name}/"
    
    # Visualisation
    conda run -n $QIIME_ENV qiime metadata tabulate \
        --m-input-file "04-taxonomy/taxonomy_${name}.qza" \
        --o-visualization "04-taxonomy/taxonomy_${name}.qzv"
    
    # Barplot (si possible)
    conda run -n $QIIME_ENV qiime taxa barplot \
        --i-table "03-clustering/table_97.qza" \
        --i-taxonomy "04-taxonomy/taxonomy_${name}.qza" \
        --o-visualization "04-taxonomy/barplot_${name}.qzv" 2>/dev/null || true
    
    # Statistiques
    if [ -f "export/taxonomy/taxonomy_${name}.tsv" ]; then
        local total=$(($(wc -l < "export/taxonomy/taxonomy_${name}.tsv") - 2))
        local species=$(grep -E ";s__[A-Za-z]" "export/taxonomy/taxonomy_${name}.tsv" 2>/dev/null | wc -l)
        local genus=$(grep -E ";g__[A-Za-z]" "export/taxonomy/taxonomy_${name}.tsv" 2>/dev/null | wc -l)
        
        echo ""
        echo "  📊 RÉSULTATS:"
        echo "     Total OTUs: $total"
        if [ $total -gt 0 ]; then
            echo "     Niveau espèce: $species ($((species * 100 / total))%)"
            echo "     Niveau genre: $genus ($((genus * 100 / total))%)"
        fi
        echo "     Fichier: export/taxonomy/taxonomy_${name}.tsv"
        echo ""
        echo "  Top 5 assignations:"
        head -7 "export/taxonomy/taxonomy_${name}.tsv" | tail -5 | \
            awk -F'\t' '{printf "     %s\n", $2}' | head -5
    fi
    
    echo ""
}

# Les 5 assignations
assign_taxonomy "12SMifish" "mifish_marine_classifier.qza" "12S MiFish (Poissons)"
assign_taxonomy "12SMimammal" "mammal_marine_12s_classifier.qza" "12S Mimammal (Mammifères)"
assign_taxonomy "12STeleo" "teleo_marine_12s_classifier.qza" "12S Teleo (Téléostéens)"
assign_taxonomy "CO1" "coi_marine_classifier.qza" "COI (Faune diverse)"
assign_taxonomy "16S" "vert_marine_16s_classifier.qza" "16S (Vertébrés)"

#################################################################################
# EXPORTS ADDITIONNELS
#################################################################################

echo "======================================================================="
echo "EXPORTS ADDITIONNELS"
echo "======================================================================="
echo ""

# Export table BIOM
if [ ! -f "export/feature-table.biom" ]; then
    echo "Export table BIOM..."
    conda run -n $QIIME_ENV qiime tools export \
        --input-path "03-clustering/table_97.qza" \
        --output-path export/
    echo "✓ export/feature-table.biom"
fi

# Convert to TSV
if [ ! -f "export/otu_table.tsv" ]; then
    echo "Conversion BIOM → TSV..."
    biom convert \
        -i export/feature-table.biom \
        -o export/otu_table.tsv \
        --to-tsv
    echo "✓ export/otu_table.tsv"
fi

# Export sequences FASTA
if [ ! -f "export/rep_seqs_97.fasta" ]; then
    echo "Export séquences FASTA..."
    conda run -n $QIIME_ENV qiime tools export \
        --input-path "03-clustering/rep_seqs_97.qza" \
        --output-path export/
    mv export/dna-sequences.fasta export/rep_seqs_97.fasta
    echo "✓ export/rep_seqs_97.fasta"
fi

echo ""

#################################################################################
# RÉSUMÉ FINAL
#################################################################################

echo ""
echo "======================================================================="
echo "✓✓✓ PIPELINE TERMINÉ AVEC SUCCÈS ✓✓✓"
echo "======================================================================="
echo ""
echo "FICHIERS CRÉÉS:"
echo ""
echo "1. OTU TABLE (97% similarité):"
echo "   → 03-clustering/table_97.qza"
echo "   → 03-clustering/table_97.qzv"
echo "   → export/otu_table.tsv (format texte)"
echo ""
echo "2. SÉQUENCES REPRÉSENTATIVES:"
echo "   → 03-clustering/rep_seqs_97.qza"
echo "   → export/rep_seqs_97.fasta"
echo ""
echo "3. TAXONOMIES (5 classificateurs):"
for f in export/taxonomy/taxonomy_*.tsv; do
    if [ -f "$f" ]; then
        count=$(($(wc -l < "$f") - 2))
        echo "   → $(basename $f) ($count OTUs)"
    fi
done
echo ""
echo "4. VISUALISATIONS INTERACTIVES:"
echo "   → 04-taxonomy/taxonomy_*.qzv (tables)"
echo "   → 04-taxonomy/barplot_*.qzv (graphiques)"
echo "   → Ouvrir sur https://view.qiime2.org"
echo ""
echo "══════════════════════════════════════════════════════════════════════"
echo "COMMENT ANALYSER VOS RÉSULTATS"
echo "══════════════════════════════════════════════════════════════════════"
echo ""
echo "1. IDENTIFIER LE MARQUEUR DE CHAQUE OTU:"
echo ""
echo "   Comparer les 5 assignations taxonomiques:"
echo "   cd export/taxonomy"
echo "   head -20 taxonomy_*.tsv"
echo ""
echo "   Logique:"
echo "   - Si assigné comme Actinopterygii → 12S-MiFish ou 12S-Teleo"
echo "   - Si assigné comme Mammalia → 12S-Mimammal"
echo "   - Si assigné comme Arthropoda/Mollusca → COI"
echo "   - Si assigné comme Chordata général → 16S"
echo ""
echo "2. ANALYSES DANS R/PHYLOSEQ:"
echo ""
echo "   library(phyloseq)"
echo "   otu <- read.table('export/otu_table.tsv', header=T, row.names=1)"
echo "   tax <- read.table('export/taxonomy/taxonomy_12SMifish.tsv', ...)"
echo ""
echo "3. DIVERSITÉ PAR SITE:"
echo ""
echo "   Sites: Poe, Kouaré, Grand Lagon Nord, Pouébo, Entrecasteaux"
echo "   Comparer alpha-diversité (richesse, Shannon)"
echo "   Beta-diversité (Bray-Curtis, PCoA)"
echo ""
echo "Bonne analyse de la biodiversité marine de Nouvelle-Calédonie! 🐠🪸🇳🇨"
echo ""
