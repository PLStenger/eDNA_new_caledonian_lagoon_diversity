#!/usr/bin/env bash

# Script CORRIGÉ - Deinterleaving robuste avec Python
# Nouvelle-Calédonie

WORKING_DIRECTORY=/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity/05_QIIME2
RAW_DATA=/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity/01_raw_data
DATABASE=/nvme/bio/data_fungi/eDNA_new_caledonian_lagoon_diversity/98_database_files
QIIME_ENV="qiime2-amplicon-2025.7"

cd $WORKING_DIRECTORY

echo "======================================================================="
echo "NOUVELLE-CALÉDONIE - Deinterleaving CORRIGÉ"
echo "======================================================================="
echo ""

rm -rf 00-deinterleave
mkdir -p 00-deinterleave

#################################################################################
# SCRIPT PYTHON POUR DEINTERLEAVE ROBUSTE
#################################################################################

cat > 00-deinterleave/deinterleave.py << 'PYEOF'
#!/usr/bin/env python3
import sys
import gzip

def deinterleave_fastq(input_file, output_r1, output_r2):
    """
    Deinterleave un fichier FASTQ où R1 et R2 alternent
    """
    with open(input_file, 'r') as fin, \
         gzip.open(output_r1, 'wt') as fout1, \
         gzip.open(output_r2, 'wt') as fout2:
        
        record_count = 0
        current_record = []
        
        for line in fin:
            current_record.append(line)
            
            # Un record FASTQ = 4 lignes
            if len(current_record) == 4:
                record_count += 1
                
                # Records impairs → R1, records pairs → R2
                if record_count % 2 == 1:
                    fout1.writelines(current_record)
                else:
                    fout2.writelines(current_record)
                
                current_record = []
        
        print(f"  Processed {record_count} records ({record_count//2} pairs)")

if __name__ == '__main__':
    if len(sys.argv) != 4:
        print("Usage: deinterleave.py input.fastq output_R1.fastq.gz output_R2.fastq.gz")
        sys.exit(1)
    
    deinterleave_fastq(sys.argv[1], sys.argv[2], sys.argv[3])
PYEOF

chmod +x 00-deinterleave/deinterleave.py

#################################################################################
# MÉTADONNÉES
#################################################################################

cat > sample_mapping.tsv << 'EOF'
sample-id	srr
Poe1	SRR29659654
Kouare1	SRR29659655
GrandLagonNord1	SRR29659657
Pouebo1	SRR29659658
Entrecasteaux1	SRR29659660
GrandLagonNord2	SRR29659906
Kouare2	SRR29659907
Entrecasteaux2	SRR29659651
Pouebo2	SRR29659652
Poe2	SRR29659653
Pouebo2bis	SRR29659656
GrandLagonNord3	SRR29659899
Poe3	SRR29659903
Kouare3	SRR29659904
Entrecasteaux3	SRR29659905
Entrecasteaux4	SRR29659896
Kouare4	SRR29659898
Poe4	SRR29659900
Pouebo4	SRR29659902
Control	SRR29659756
EOF

#################################################################################
# ÉTAPE 1: DEINTERLEAVE AVEC PYTHON
#################################################################################

echo "=== ÉTAPE 1: Deinterleaving avec Python ==="
echo ""

while IFS=$'\t' read -r sample_name srr_id; do
    if [ "$sample_name" != "sample-id" ]; then
        echo "Deinterleaving: $sample_name ($srr_id)"
        
        input_file="${RAW_DATA}/${srr_id}.fastq"
        output_r1="00-deinterleave/${sample_name}_R1.fastq.gz"
        output_r2="00-deinterleave/${sample_name}_R2.fastq.gz"
        
        if [ -f "$output_r1" ] && [ -f "$output_r2" ]; then
            echo "  ✓ Déjà fait"
        else
            python3 00-deinterleave/deinterleave.py "$input_file" "$output_r1" "$output_r2"
            echo "  ✓ R1: $output_r1"
            echo "  ✓ R2: $output_r2"
        fi
        echo ""
    fi
done < sample_mapping.tsv

echo "✓ Deinterleaving terminé"
echo ""

#################################################################################
# VÉRIFICATION FORMAT
#################################################################################

echo "=== Vérification du format FASTQ ==="
echo ""

check_file="00-deinterleave/Poe1_R1.fastq.gz"
if [ -f "$check_file" ]; then
    echo "Aperçu de $check_file (20 premières lignes):"
    zcat "$check_file" | head -20
    echo ""
    
    # Vérifier que chaque 4e ligne commence par @
    echo "Vérification structure FASTQ..."
    issue_count=$(zcat "$check_file" | awk 'NR%4==1 && substr($0,1,1)!="@" {print NR}' | wc -l)
    
    if [ $issue_count -eq 0 ]; then
        echo "✓ Format FASTQ valide"
    else
        echo "❌ ERREUR: $issue_count lignes header mal formatées"
        echo "Les premières erreurs:"
        zcat "$check_file" | awk 'NR%4==1 && substr($0,1,1)!="@" {print "Ligne " NR ": " $0; if(++count>=3) exit}'
        exit 1
    fi
fi

echo ""

#################################################################################
# ÉTAPE 2: IMPORT QIIME2
#################################################################################

echo "=== ÉTAPE 2: Import QIIME2 (paired-end) ==="
echo ""

# Créer manifest
manifest_file="02-qiime2/manifest_all_samples.tsv"

printf "sample-id\tforward-absolute-filepath\treverse-absolute-filepath\n" > "$manifest_file"

while IFS=$'\t' read -r sample_name srr_id; do
    if [ "$sample_name" != "sample-id" ]; then
        r1_path=$(realpath "00-deinterleave/${sample_name}_R1.fastq.gz")
        r2_path=$(realpath "00-deinterleave/${sample_name}_R2.fastq.gz")
        
        if [ -f "$r1_path" ] && [ -f "$r2_path" ]; then
            printf "%s\t%s\t%s\n" "$sample_name" "$r1_path" "$r2_path" >> "$manifest_file"
        fi
    fi
done < sample_mapping.tsv

echo "✓ Manifest créé: $manifest_file"
echo "Aperçu:"
head -3 "$manifest_file"
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
        echo "✓ Import réussi: demux_all.qza"
    else
        echo "❌ Import échoué"
        exit 1
    fi
else
    echo "✓ Import existe déjà"
fi

# Visualisation
if [ ! -f "02-qiime2/demux_all_summary.qzv" ]; then
    conda run -n $QIIME_ENV qiime demux summarize \
        --i-data "02-qiime2/demux_all.qza" \
        --o-visualization "02-qiime2/demux_all_summary.qzv"
    
    echo "✓ Visualisation: demux_all_summary.qzv"
fi

echo ""

#################################################################################
# ÉTAPE 3: DADA2 PAIRED-END
#################################################################################

echo "=== ÉTAPE 3: DADA2 paired-end ==="
echo ""

if [ ! -f "03-dada2/table_all.qza" ]; then
    echo "Lancement DADA2 (cela peut prendre 30-60 minutes)..."
    echo ""
    
    conda run -n $QIIME_ENV qiime dada2 denoise-paired \
        --i-demultiplexed-seqs "02-qiime2/demux_all.qza" \
        --p-trim-left-f 0 \
        --p-trim-left-r 0 \
        --p-trunc-len-f 240 \
        --p-trunc-len-r 240 \
        --p-max-ee-f 3 \
        --p-max-ee-r 3 \
        --p-n-threads 8 \
        --o-table "03-dada2/table_all.qza" \
        --o-representative-sequences "03-dada2/rep_seqs_all.qza" \
        --o-denoising-stats "03-dada2/stats_all.qza" \
        --verbose
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "✓ DADA2 réussi"
        
        # Visualisations
        conda run -n $QIIME_ENV qiime metadata tabulate \
            --m-input-file "03-dada2/stats_all.qza" \
            --o-visualization "03-dada2/stats_all.qzv"
        
        conda run -n $QIIME_ENV qiime feature-table tabulate-seqs \
            --i-data "03-dada2/rep_seqs_all.qza" \
            --o-visualization "03-dada2/rep_seqs_all.qzv"
        
        conda run -n $QIIME_ENV qiime feature-table summarize \
            --i-table "03-dada2/table_all.qza" \
            --o-visualization "03-dada2/table_all.qzv"
        
        echo "✓ Visualisations créées"
    else
        echo "❌ DADA2 a échoué"
        exit 1
    fi
else
    echo "✓ DADA2 déjà effectué"
fi

echo ""

#################################################################################
# ÉTAPE 4: ASSIGNATIONS TAXONOMIQUES
#################################################################################

echo "=== ÉTAPE 4: Assignations taxonomiques multiples ==="
echo ""

assign_taxonomy() {
    local name=$1
    local classifier=$2
    
    echo "--- Assignation: $name ---"
    
    if [ ! -f "$DATABASE/$classifier" ]; then
        echo "  ⚠️  Classificateur manquant: $classifier"
        echo "  Créez d'abord les bases avec: qiime2_complete_v2.sh"
        return 1
    fi
    
    if [ ! -f "04-taxonomy/taxonomy_${name}.qza" ]; then
        conda run -n $QIIME_ENV qiime feature-classifier classify-sklearn \
            --i-classifier "$DATABASE/$classifier" \
            --i-reads "03-dada2/rep_seqs_all.qza" \
            --o-classification "04-taxonomy/taxonomy_${name}.qza" \
            --p-confidence 0.7 \
            --p-n-jobs 6
    fi
    
    # Export TSV
    conda run -n $QIIME_ENV qiime tools export \
        --input-path "04-taxonomy/taxonomy_${name}.qza" \
        --output-path "export/taxonomy/temp_${name}/"
    
    mv "export/taxonomy/temp_${name}/taxonomy.tsv" "export/taxonomy/taxonomy_${name}.tsv"
    rm -rf "export/taxonomy/temp_${name}/"
    
    local total=$(($(wc -l < "export/taxonomy/taxonomy_${name}.tsv") - 2))
    echo "  ✓ ASVs assignés: $total"
    echo "  ✓ Fichier: export/taxonomy/taxonomy_${name}.tsv"
    echo ""
}

assign_taxonomy "12SMifish" "mifish_marine_classifier.qza"
assign_taxonomy "12SMimammal" "mammal_marine_12s_classifier.qza"
assign_taxonomy "12STeleo" "teleo_marine_12s_classifier.qza"
assign_taxonomy "CO1" "coi_marine_classifier.qza"
assign_taxonomy "16S" "vert_marine_16s_classifier.qza"

echo ""
echo "======================================================================="
echo "✓ PIPELINE TERMINÉ AVEC SUCCÈS"
echo "======================================================================="
echo ""
echo "Fichiers créés:"
echo "  1. 02-qiime2/demux_all_summary.qzv - Statistiques séquençage"
echo "  2. 03-dada2/stats_all.qzv - Résultats DADA2"
echo "  3. 03-dada2/table_all.qzv - Table ASVs"
echo "  4. 03-dada2/rep_seqs_all.qzv - Séquences représentatives"
echo "  5. export/taxonomy/*.tsv - 5 fichiers taxonomie"
echo ""
echo "PROCHAINES ÉTAPES:"
echo ""
echo "1. Visualiser les stats:"
echo "   https://view.qiime2.org"
echo ""
echo "2. Analyser les taxonomies:"
echo "   cd export/taxonomy"
echo "   head taxonomy_*.tsv"
echo ""
echo "3. Identifier le marqueur de chaque ASV:"
echo "   Comparer les 5 assignations pour déterminer quel classificateur"
echo "   donne la meilleure assignation (plus spécifique, plus confiante)"
echo ""
