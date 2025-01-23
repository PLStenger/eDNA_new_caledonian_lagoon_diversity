# eDNA_new_caledonian_lagoon_diversity
eDNA_new_caledonian_lagoon_diversity from UNESCO data

### Installing pipeline :

First, open your terminal. Then, run these two command lines :

    cd -place_in_your_local_computer
    git clone https://github.com/PLStenger/eDNA_new_caledonian_lagoon_diversity.git

### Update the pipeline in local by :

    git pull
    
### If necessary, install softwares by :   

    cd 99_softwares/
    conda install -c bioconda fastqc
    conda install -c bioconda trimmomatic
    conda install -c bioconda multiqc

For install QIIME2, please refer to http://qiime.org/install/install.html

### Know the number of CPU (threads) of your computer (here for MacOs) :   

    sysctl hw.ncpu
    > hw.ncpu: 4

### Run scripts in local by :


    # Put you in your working directory
    cd /scratch_vol1/fungi/Coral_block_colonisation/00_scripts
    
    
    # For run all pipeline, lunch only this command line : 
    time nohup bash 000_run_all_pipeline_in_one_script.sh &> 000_run_all_pipeline_in_one_script.out

    # For run pipeline step by step, lunch :
    # Run the first script for check the quality of your data and then for choosing the good cleanning parameters
    time nohup bash 01_quality_check_by_FastQC.sh &> 01_quality_check_by_FastQC.out
    
        real	2m29.904s
        user	3m14.842s
        sys	    0m14.673s
    
    # Go out of the folder
    cd ..
    
    # Go in the "02_quality_check" folder
    cd 02_quality_check
    
    # Run multiqc for synthetized information
    multiqc .
    
    # Go out of the folder
    cd ..
    
    # Go in the script folder
    cd 00_script

    # Run the third script for checking the quality of your cleaned data 
    time nohup bash 03_check_quality_of_cleaned_data.sh &> 03_check_quality_of_cleaned_data.out

        real	5m5.974s
        user	5m42.971s
        sys	    0m27.492s
        
    # Go out of the folder
    cd ..
    
    # Go in the "04_quality_check" folder
    cd 04_quality_check
    
    # Run multiqc for synthetized information
    multiqc .
    
    # Go out of the folder
    cd ..
    
    # Go in the script folder
    cd 00_script
    
    # Try to deal with the V1V3 - V3V4 situation :
    time nohup bash 04_fastq-cat.sh &> 04_fastq-cat.out

        real	0m1.264s
        user	0m0.039s
        sys	    0m0.692s

    # Import the data in QIIME2 format
    time nohup bash 05_qiime2_import_PE.sh &> 05_qiime2_import_PE.out
    
        real	1m56.160s
        user	0m55.588s
        sys	    0m11.154s
    
    # Run the Denoise
    time nohup bash 06_qiime2_denoise_PE.sh &> 06_qiime2_denoise_PE.out
        real	66m29.579s
        user	129m35.661s
        sys	    4m17.156s
    
    # Run the tree construction
    time nohup bash 07_qiime2_tree_PE.sh &> 07_qiime2_tree_PE.out
        real	8m29.501s
        user	2m23.194s
        sys	0m20.178s
    
    # Run the rarefaction
    time nohup bash 08_qiime2_rarefaction_PE.sh &> 08_qiime2_rarefaction_PE.out
        real	1m15.788s
        user	0m28.194s
        sys	       0m8.118s
        
    # For obtainning better plots, run this script on your computer :    
    08_qiime2_rarefaction_PE_plots.R
    
    time nohup bash 09_qiime2_calculate_and_explore_diversity_metrics_PE.sh &> 09_qiime2_calculate_and_explore_diversity_metrics_PE.out
        real	59m0.552s
        user	7m23.905s
        sys	1m51.603s
    
    time nohup bash 10_qiime2_assign_taxonomy_PE.sh &> 10_qiime2_assign_taxonomy_PE.out
        real	82m44.469s
        user	74m58.003s
        sys	    1m21.506s
    time nohup bash 11_core_biom_PE.sh &> 11_core_biom_PE.out
    
    Run "12_FunGuild.sh" localy please
