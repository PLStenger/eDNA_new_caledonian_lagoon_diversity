#!/usr/bin/env bash

# PIPELINE COMPLET - Nouvelle-Calédonie eDNA
# Téléchargement SRA + Analyse complète
# UNESCO eDNA Expeditions - Récifs coralliens

#################################################################################
# CONFIGURATION
#################################################################################

PROJECT_DIR=/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity
RAW_DATA=${PROJECT_DIR}/01_raw_data
WORKING_DIR=${PROJECT_DIR}/05_QIIME2
DATABASE=${PROJECT_DIR}/98_database_files
QIIME_ENV="qiime2-amplicon-2025.7"

mkdir -p $RAW_DATA
mkdir -p $WORKING_DIR
mkdir -p $DATABASE

cd $PROJECT_DIR

echo "======================================================================="
echo "PIPELINE COMPLET - NEW CALEDONIA LAGOON DIVERSITY"
echo "UNESCO eDNA Expeditions - Récifs coralliens"
echo "======================================================================="
echo ""
echo "Projet: Biodiversité marine Nouvelle-Calédonie"
echo "Sites: Poe, Kouaré, Grand Lagon Nord, Pouébo, Entrecasteaux"
echo "Marqueurs: 12S-MiFish, 12S-Mimammal, 12S-Teleo, COI, 16S-Vert"
echo ""

#################################################################################
# LISTE DES SRR
#################################################################################

cat > ${RAW_DATA}/srr_list.txt << 'EOF'
SRR29659651	Entrecasteaux2
SRR29659652	Pouebo2
SRR29659653	Poe2
SRR29659654	Poe1
SRR29659655	Kouare1
SRR29659656	Pouebo2bis
SRR29659657	GrandLagonNord1
SRR29659658	Pouebo1
SRR29659660	Entrecasteaux1
SRR29659756	Control
SRR29659896	Entrecasteaux4
SRR29659898	Kouare4
SRR29659899	GrandLagonNord3
SRR29659900	Poe4
SRR29659902	Pouebo4
SRR29659903	Poe3
SRR29659904	Kouare3
SRR29659905	Entrecasteaux3
SRR29659906	GrandLagonNord2
SRR29659907	Kouare2
EOF

echo "✓ Liste des SRR créée: ${RAW_DATA}/srr_list.txt"
echo ""

#################################################################################
# ÉTAPE 1: TÉLÉCHARGEMENT DEPUIS SRA AVEC SRA-TOOLKIT
#################################################################################

echo "======================================================================="
echo "ÉTAPE 1: Téléchargement des données SRA"
echo "======================================================================="
echo ""

# Vérifier que sra-toolkit est installé
if ! command -v fasterq-dump &> /dev/null; then
    echo "Installation de sra-tools..."
    conda install -y -c bioconda sra-tools
fi

# Configurer SRA toolkit
echo "Configuration SRA toolkit..."
vdb-config --prefetch-to-cwd

cd $RAW_DATA

echo ""
echo "Téléchargement des 20 échantillons depuis NCBI SRA..."
echo "Cela peut prendre 1-3 heures selon votre connexion"
echo ""

# Fonction de téléchargement
download_srr() {
    local srr=$1
    local sample=$2
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Téléchargement: $srr ($sample)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Vérifier si déjà téléchargé
    if [ -f "${srr}.fastq" ] || [ -f "${srr}.fastq.gz" ]; then
        echo "  ✓ Déjà téléchargé"
        return 0
    fi
    
    # Télécharger avec fasterq-dump (préserve les scores de qualité)
    # --split-spot : sépare paired-end en même fichier (interleaved)
    # --skip-technical : ignore les reads techniques
    fasterq-dump $srr \
        --split-spot \
        --skip-technical \
        --threads 4 \
        --progress \
        --temp .
    
    if [ $? -eq 0 ]; then
        echo "  ✓ Téléchargement réussi: ${srr}.fastq"
        
        # Vérifier les scores de qualité
        echo "  Vérification qualité (premières lignes):"
        head -8 ${srr}.fastq | tail -2
        
        # Vérifier que les scores ne sont pas tous "?"
        quality_check=$(head -100 ${srr}.fastq | awk 'NR%4==0' | grep -v "^?*$" | wc -l)
        if [ $quality_check -gt 0 ]; then
            echo "  ✓ Scores de qualité OK"
        else
            echo "  ⚠️  ATTENTION: Scores de qualité suspects (tous '?')"
        fi
    else
        echo "  ❌ ERREUR lors du téléchargement de $srr"
        return 1
    fi
    
    echo ""
}

# Télécharger tous les SRR
while IFS=$'\t' read -r srr sample; do
    download_srr "$srr" "$sample"
done < srr_list.txt

echo ""
echo "✓ Téléchargement terminé"
echo ""
echo "Statistiques:"
fastq_count=$(ls -1 *.fastq 2>/dev/null | wc -l)
echo "  Fichiers FASTQ téléchargés: $fastq_count / 20"
echo ""

if [ $fastq_count -lt 20 ]; then
    echo "⚠️  ATTENTION: Tous les fichiers n'ont pas été téléchargés"
    echo "Vérifiez les erreurs ci-dessus"
    echo ""
fi

#################################################################################
# ÉTAPE 2: DEINTERLEAVE ET IMPORT QIIME2
#################################################################################

echo "======================================================================="
echo "ÉTAPE 2: Deinterleaving et import QIIME2"
echo "======================================================================="
echo ""

cd $WORKING_DIR

mkdir -p 00-deinterleave
mkdir -p 02-qiime2

# Script Python pour deinterleave
cat > 00-deinterleave/deinterleave.py << 'PYEOF'
#!/usr/bin/env python3
import sys
import gzip

def deinterleave_fastq(input_file, output_r1, output_r2):
    with open(input_file, 'r') as fin, \
         gzip.open(output_r1, 'wt') as fout1, \
         gzip.open(output_r2, 'wt') as fout2:
        
        record_count = 0
        current_record = []
        
        for line in fin:
            current_record.append(line)
            
            if len(current_record) == 4:
                record_count += 1
                
                if record_count % 2 == 1:
                    fout1.writelines(current_record)
                else:
                    fout2.writelines(current_record)
                
                current_record = []
        
        print(f"  {record_count//2} paires traitées")

if __name__ == '__main__':
    deinterleave_fastq(sys.argv[1], sys.argv[2], sys.argv[3])
PYEOF

chmod +x 00-deinterleave/deinterleave.py

echo "Deinterleaving des fichiers paired-end..."
echo ""

while IFS=$'\t' read -r srr sample; do
    input="${RAW_DATA}/${srr}.fastq"
    output_r1="00-deinterleave/${sample}_R1.fastq.gz"
    output_r2="00-deinterleave/${sample}_R2.fastq.gz"
    
    if [ -f "$input" ]; then
        if [ ! -f "$output_r1" ]; then
            echo "Deinterleaving: $sample ($srr)"
            python3 00-deinterleave/deinterleave.py "$input" "$output_r1" "$output_r2"
        else
            echo "  ✓ $sample déjà deinterleaved"
        fi
    fi
done < ${RAW_DATA}/srr_list.txt

echo ""
echo "✓ Deinterleaving terminé"
echo ""

# Créer le manifest QIIME2
echo "Création du manifest QIIME2..."

manifest_file="02-qiime2/manifest_all.tsv"
printf "sample-id\tforward-absolute-filepath\treverse-absolute-filepath\n" > "$manifest_file"

while IFS=$'\t' read -r srr sample; do
    r1_path=$(realpath "00-deinterleave/${sample}_R1.fastq.gz" 2>/dev/null)
    r2_path=$(realpath "00-deinterleave/${sample}_R2.fastq.gz" 2>/dev/null)
    
    if [ -f "$r1_path" ] && [ -f "$r2_path" ]; then
        printf "%s\t%s\t%s\n" "$sample" "$r1_path" "$r2_path" >> "$manifest_file"
    fi
done < ${RAW_DATA}/srr_list.txt

echo "✓ Manifest créé: $manifest_file"
echo ""

# Import QIIME2
if [ ! -f "02-qiime2/demux_all.qza" ]; then
    echo "Import dans QIIME2..."
    
    conda run -n $QIIME_ENV qiime tools import \
        --type 'SampleData[PairedEndSequencesWithQuality]' \
        --input-path "$manifest_file" \
        --output-path "02-qiime2/demux_all.qza" \
        --input-format PairedEndFastqManifestPhred33V2
    
    if [ $? -eq 0 ]; then
        echo "✓ Import réussi"
        
        # Visualisation qualité
        conda run -n $QIIME_ENV qiime demux summarize \
            --i-data "02-qiime2/demux_all.qza" \
            --o-visualization "02-qiime2/demux_summary.qzv"
        
        echo "✓ Visualisation créée: 02-qiime2/demux_summary.qzv"
        echo ""
        echo "📊 IMPORTANT: Ouvrez ce fichier sur https://view.qiime2.org"
        echo "   et notez la position où la qualité chute pour ajuster DADA2"
        echo ""
    else
        echo "❌ Import échoué"
        exit 1
    fi
else
    echo "✓ Import déjà effectué"
fi

echo ""

#################################################################################
# ÉTAPE 3: DADA2 DENOISING
#################################################################################

echo "======================================================================="
echo "ÉTAPE 3: DADA2 Denoising"
echo "======================================================================="
echo ""

mkdir -p 03-dada2

# Demander les paramètres de troncature
echo "Basé sur la visualisation de qualité (demux_summary.qzv):"
echo "À quelle position tronquer Forward (R1)? [défaut: 220]"
read -p "> " trunc_f
trunc_f=${trunc_f:-220}

echo "À quelle position tronquer Reverse (R2)? [défaut: 200]"
read -p "> " trunc_r
trunc_r=${trunc_r:-200}

echo ""
echo "Lancement DADA2 avec:"
echo "  - trunc-len-f: $trunc_f"
echo "  - trunc-len-r: $trunc_r"
echo "  - max-ee: 3,3 (permissif)"
echo ""
echo "Cela peut prendre 30-90 minutes..."
echo ""

if [ ! -f "03-dada2/table.qza" ]; then
    conda run -n $QIIME_ENV qiime dada2 denoise-paired \
        --i-demultiplexed-seqs "02-qiime2/demux_all.qza" \
        --p-trim-left-f 0 \
        --p-trim-left-r 0 \
        --p-trunc-len-f $trunc_f \
        --p-trunc-len-r $trunc_r \
        --p-max-ee-f 3.0 \
        --p-max-ee-r 3.0 \
        --p-n-threads 8 \
        --o-table "03-dada2/table.qza" \
        --o-representative-sequences "03-dada2/rep_seqs.qza" \
        --o-denoising-stats "03-dada2/stats.qza" \
        --verbose
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "✓ DADA2 réussi"
        
        # Visualisations
        conda run -n $QIIME_ENV qiime metadata tabulate \
            --m-input-file "03-dada2/stats.qza" \
            --o-visualization "03-dada2/stats.qzv"
        
        conda run -n $QIIME_ENV qiime feature-table summarize \
            --i-table "03-dada2/table.qza" \
            --o-visualization "03-dada2/table.qzv"
        
        conda run -n $QIIME_ENV qiime feature-table tabulate-seqs \
            --i-data "03-dada2/rep_seqs.qza" \
            --o-visualization "03-dada2/rep_seqs.qzv"
        
        echo "✓ Visualisations créées"
    else
        echo ""
        echo "❌ DADA2 a échoué"
        echo ""
        echo "Essayez avec des paramètres plus relaxés:"
        echo "  - Troncature plus courte (150, 150)"
        echo "  - max-ee plus élevé (5, 5)"
        echo ""
        exit 1
    fi
else
    echo "✓ DADA2 déjà effectué"
fi

echo ""

#################################################################################
# ÉTAPE 4: ASSIGNATIONS TAXONOMIQUES
#################################################################################

echo "======================================================================="
echo "ÉTAPE 4: Assignations taxonomiques"
echo "======================================================================="
echo ""

mkdir -p 04-taxonomy
mkdir -p export/taxonomy

assign_taxonomy() {
    local name=$1
    local classifier=$2
    
    echo "--- $name ---"
    
    if [ ! -f "$DATABASE/$classifier" ]; then
        echo "  ⚠️  Classificateur manquant: $classifier"
        echo "  Créez d'abord les bases de données avec qiime2_complete_v2.sh"
        return 1
    fi
    
    if [ ! -f "04-taxonomy/taxonomy_${name}.qza" ]; then
        conda run -n $QIIME_ENV qiime feature-classifier classify-sklearn \
            --i-classifier "$DATABASE/$classifier" \
            --i-reads "03-dada2/rep_seqs.qza" \
            --o-classification "04-taxonomy/taxonomy_${name}.qza" \
            --p-confidence 0.7 \
            --p-n-jobs 8
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
    
    local total=$(($(wc -l < "export/taxonomy/taxonomy_${name}.tsv") - 2))
    echo "  ✓ $total ASVs assignés"
    echo ""
}

echo "Assignations avec les 5 classificateurs marins..."
echo ""

assign_taxonomy "12SMifish" "mifish_marine_classifier.qza"
assign_taxonomy "12SMimammal" "mammal_marine_12s_classifier.qza"
assign_taxonomy "12STeleo" "teleo_marine_12s_classifier.qza"
assign_taxonomy "CO1" "coi_marine_classifier.qza"
assign_taxonomy "16S" "vert_marine_16s_classifier.qza"

#################################################################################
# RÉSUMÉ FINAL
#################################################################################

echo ""
echo "======================================================================="
echo "✓✓✓ PIPELINE COMPLET TERMINÉ ✓✓✓"
echo "======================================================================="
echo ""
echo "RÉCAPITULATIF DES FICHIERS CRÉÉS:"
echo ""
echo "1. DONNÉES BRUTES:"
echo "   → ${RAW_DATA}/*.fastq (20 échantillons)"
echo ""
echo "2. DONNÉES QIIME2:"
echo "   → 02-qiime2/demux_all.qza"
echo "   → 02-qiime2/demux_summary.qzv"
echo ""
echo "3. RÉSULTATS DADA2:"
echo "   → 03-dada2/table.qza (table ASV)"
echo "   → 03-dada2/rep_seqs.qza (séquences représentatives)"
echo "   → 03-dada2/stats.qzv (statistiques)"
echo ""
echo "4. TAXONOMIES (5 marqueurs):"
ls -1 export/taxonomy/taxonomy_*.tsv 2>/dev/null | while read f; do
    count=$(($(wc -l < "$f") - 2))
    echo "   → $(basename $f) ($count ASVs)"
done
echo ""
echo "5. VISUALISATIONS (.qzv):"
echo "   → Ouvrir sur https://view.qiime2.org"
find . -name "*.qzv" -type f 2>/dev/null | head -10 | while read f; do
    echo "   → $f"
done
echo ""
echo "══════════════════════════════════════════════════════════════════════"
echo "ANALYSES SUGGÉRÉES"
echo "══════════════════════════════════════════════════════════════════════"
echo ""
echo "1. BIODIVERSITÉ PAR SITE:"
echo "   qiime diversity core-metrics-phylogenetic \\"
echo "     --i-table 03-dada2/table.qza \\"
echo "     --i-phylogeny tree.qza \\"
echo "     --p-sampling-depth 1000 \\"
echo "     --m-metadata-file metadata.tsv \\"
echo "     --output-dir diversity"
echo ""
echo "2. COMPARER LES 5 SITES:"
echo "   - Poe (récif barrière SO)"
echo "   - Kouaré (récif intermédiaire N)"
echo "   - Grand Lagon Nord"
echo "   - Pouébo (NE)"
echo "   - Entrecasteaux (S)"
echo ""
echo "3. IDENTIFIER LES MARQUEURS:"
echo "   Comparer les assignations dans export/taxonomy/"
echo "   pour déterminer quel ASV correspond à quel marqueur"
echo ""
echo "Bonne analyse de la biodiversité marine! 🐠🪸🇳🇨"
echo ""
