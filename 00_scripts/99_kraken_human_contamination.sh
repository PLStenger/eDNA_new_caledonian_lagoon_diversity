#!/bin/bash

# Top 20 espèces dans Entrecasteaux4
awk '$4=="S"' Entrecasteaux4_report.txt | sort -k1 -nr | head -20

# Compter combien de reads Homo sapiens (contamination)
grep "Homo sapiens" Entrecasteaux4_report.txt


# Vérifier contamination humaine dans TOUS les échantillons
for report in *_report.txt; do
    sample=$(basename $report _report.txt)
    human=$(grep "Homo sapiens" "$report" | head -1 | awk '{print $1}')
    echo "$sample: $human%"
done | sort -k2 -n


# Entrecasteaux3: 1.09%
# Kouare2: 1.36%
# Poe1: 1.50%
# Poe3: 1.58%
# Poe4: 1.24%
# GrandLagonNord2: 2.12%
# Poe2: 2.00%
# Pouebo4: 3.56%
# Entrecasteaux1: 4.66%
# Entrecasteaux4: 4.83%
# Pouebo1: 4.03%
# Entrecasteaux2: 7.97%
# Kouare1: 7.89%
# Kouare3: 8.55%
# GrandLagonNord3: 11.48%
# GrandLagonNord1: 12.49%
# Pouebo2: 12.51%
# Pouebo2bis: 20.66%
# Control: 28.31%
# Kouare4: 37.68%


# Vérifier contamination humaine dans TOUS les échantillons
for report in *_report.txt; do
    sample=$(basename $report _report.txt)
    human=$(grep "Homo sapiens subsp. 'Denisova'" "$report" | head -1 | awk '{print $1}')
    echo "$sample: $human%"
done | sort -k2 -n

# Control: %
# Entrecasteaux1: 0.01%
# Entrecasteaux2: 0.01%
# Entrecasteaux3: 0.00%
# Entrecasteaux4: 0.01%
# GrandLagonNord1: 0.02%
# GrandLagonNord2: 0.02%
# GrandLagonNord3: 0.02%
# Kouare1: 0.00%
# Kouare2: 0.00%
# Kouare3: 0.00%
# Kouare4: 0.03%
# Poe1: 0.00%
# Poe2: 0.00%
# Poe3: 0.00%
# Poe4: 0.00%
# Pouebo1: 0.01%
# Pouebo2: 0.03%
# Pouebo2bis: 0.01%
# Pouebo4: 0.01%



for report in *_report.txt; do
>     sample=$(basename $report _report.txt)
>     human=$(grep "Homo sapiens neanderthalensis" "$report" | head -1 | awk '{print $1}')
>     echo "$sample: $human%"
> done | sort -k2 -n
# Control: %
# Entrecasteaux1: %
# Entrecasteaux2: %
# Entrecasteaux3: %
# Entrecasteaux4: %
# GrandLagonNord1: 0.00%
# GrandLagonNord2: %
# GrandLagonNord3: %
# Kouare1: %
# Kouare2: %
# Kouare3: %
# Kouare4: %
# Poe1: %
# Poe2: %
# Poe3: %
# Poe4: %
# Pouebo1: 0.00%
# Pouebo2: 0.00%
# Pouebo2bis: %
# Pouebo4: %



# Site            Échantillon      Contamination_humaine  Statut
# Control         Control          28.31                  À_EXCLURE
# Entrecasteaux   Entrecasteaux1   4.66                   OK
# Entrecasteaux   Entrecasteaux2   7.97                   Acceptable
# Entrecasteaux   Entrecasteaux3   1.09                   OK
# Entrecasteaux   Entrecasteaux4   4.83                   OK
# GrandLagonNord  GrandLagonNord1  12.49                  Acceptable
# GrandLagonNord  GrandLagonNord2  2.12                   OK
# GrandLagonNord  GrandLagonNord3  11.48                  Acceptable
# Kouare          Kouare1          7.89                   Acceptable
# Kouare          Kouare2          1.36                   OK
# Kouare          Kouare3          8.55                   Acceptable
# Kouare          Kouare4          37.68                  À_EXCLURE
# Poe             Poe1             1.50                   OK
# Poe             Poe2             2.00                   OK
# Poe             Poe3             1.58                   OK
# Poe             Poe4             1.24                   OK
# Pouebo          Pouebo1          4.03                   OK
# Pouebo2bis      Pouebo2bis       20.66                  À_EXCLURE
# Pouebo          Pouebo2          12.51                  Acceptable
# Pouebo          Pouebo4          3.56                   OK






