#!/usr/bin/env python3
"""
Normalizes the Kraken2 MPA taxonomy by filling in missing ranks
Usage: python3 fix_taxonomy_mpa.py combined_mpa.tsv > combined_mpa_fixed.tsv
"""

import sys
import pandas as pd

def parse_taxonomy(tax_string):
    """Parse la chaîne taxonomique et retourne un dict avec tous les rangs"""
    
    # Définir l'ordre des rangs taxonomiques
    ranks = ['k', 'p', 'c', 'o', 'f', 'g', 's']
    rank_names = {
        'k': 'Kingdom',
        'p': 'Phylum',
        'c': 'Class',
        'o': 'Order',
        'f': 'Family',
        'g': 'Genus',
        's': 'Species'
    }
    
    # Initialiser avec des valeurs vides
    tax_dict = {rank: '' for rank in ranks}
    
    # Parser la taxonomie
    if pd.isna(tax_string) or tax_string == '':
        return tax_dict
    
    levels = tax_string.split('|')
    
    for level in levels:
        if '__' in level:
            rank_code = level.split('__')[0]
            taxon_name = level.split('__')[1]
            
            if rank_code in tax_dict:
                tax_dict[rank_code] = taxon_name
    
    return tax_dict

def fill_missing_ranks(tax_dict):
    """Remplit les rangs manquants avec des placeholders"""
    
    ranks = ['k', 'p', 'c', 'o', 'f', 'g', 's']
    
    last_known = None
    
    for rank in ranks:
        if tax_dict[rank] == '' or tax_dict[rank] is None:
            # Rang manquant, créer un placeholder
            if last_known:
                tax_dict[rank] = f"unclassified_{last_known}"
            else:
                tax_dict[rank] = f"unclassified_{rank}"
        else:
            last_known = tax_dict[rank]
    
    return tax_dict

def rebuild_taxonomy(tax_dict):
    """Reconstruit la chaîne taxonomique complète"""
    
    ranks = ['k', 'p', 'c', 'o', 'f', 'g', 's']
    
    tax_parts = []
    for rank in ranks:
        if tax_dict[rank]:
            tax_parts.append(f"{rank}__{tax_dict[rank]}")
    
    return '|'.join(tax_parts)

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 fix_taxonomy_mpa.py combined_mpa.tsv > combined_mpa_fixed.tsv")
        sys.exit(1)
    
    input_file = sys.argv[1]
    
    # Lire le fichier
    df = pd.read_csv(input_file, sep='\t')
    
    # Traiter chaque ligne
    fixed_taxonomy = []
    
    for idx, row in df.iterrows():
        tax_string = row['#Classification']
        
        # Parser
        tax_dict = parse_taxonomy(tax_string)
        
        # Remplir les rangs manquants
        tax_dict_filled = fill_missing_ranks(tax_dict)
        
        # Reconstruire
        new_tax = rebuild_taxonomy(tax_dict_filled)
        
        fixed_taxonomy.append(new_tax)
    
    # Remplacer la colonne
    df['#Classification'] = fixed_taxonomy
    
    # Sauvegarder
    df.to_csv(sys.stdout, sep='\t', index=False)

if __name__ == '__main__':
    main()
