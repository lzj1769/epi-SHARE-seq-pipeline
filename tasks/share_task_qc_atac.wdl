version 1.0

# TASK
# SHARE-atac-qc-atac

task qc_atac {
    meta {
        version: 'v0.1'
        author: 'Eugenio Mattei (emattei@broadinstitute.org) at Broad Institute of MIT and Harvard'
        description: 'Broad Institute of MIT and Harvard SHARE-Seq pipeline: ATAC qc statistics task'
    }

    input {
        # This function takes in input the raw and filtered bams
        # and compute some alignment metrics along with the TSS
        # enrichment plot.

        Int cpus= 4
        File raw_bam
        File raw_bam_index
        File filtered_bam
        File filtered_bam_index
        File tss
        String? barcode_tag = "CB"
        String genome_name
        String? prefix
        String docker_image = "us.gcr.io/buenrostro-share-seq/share_task_qc_atac"
    }

    #Int disk_gb = round(20.0 + 4 * input_file_size_gb)
    Int disk_gb = 100
    Float input_file_size_gb = size(raw_bam, "G")
    Int mem_gb = 16

    String stats_log = '${default="share-seq" prefix}.atac.qc.stats.${genome_name}.log.txt'
    String hist_log = '${default="share-seq" prefix}.atac.qc.hist.${genome_name}.log.txt'
    # pdf string needed as required input to Picard CollectInsertSizeMetrics
    String hist_log_pdf = '${default="share-seq" prefix}.atac.qc.hist.${genome_name}.log.pdf'
    String hist_log_png = '${default="share-seq" prefix}.atac.qc.hist.${genome_name}.log.png'
    String tss_pileup_prefix = '${default="share-seq" prefix}.atac.qc.tss.pileup.${genome_name}.log'
    String tss_pileup_out = '${default="share-seq" prefix}.atac.qc.tss.pileup.${genome_name}.log.png'
    String samstats_log = "${prefix}.atac.align.${genome_name}.samstats.raw.log"


    command {
        set -e

        ln -s ${raw_bam} in.raw.bam
        ln -s ${raw_bam_index} in.raw.bam.bai
        ln -s ${filtered_bam} in.filtered.bam
        ln -s ${filtered_bam_index} in.filtered.bam.bai

        # samstats raw
        # output of bowtie2
        samtools view -o - in.raw.bam | SAMstats --sorted_sam_file - --outf {WRITE OUTPUT} > {samstats_log}

         # The script creates two log file with bulk and barcode statistics.
        # "{prefix}.mito.bulk-metrics.tsv"
        # "{prefix}.mito.bc-metrics.tsv"
        python3 $(which filter_mito_reads.py) --prefix ~{prefix} --bc_tag ~{barcode_tag} in.bam

        # library complexity
        # queryname_final_bam from filter
        samtools view {queryname_final_bam} | python3 $(which pbc_stats.py) {output}

        # SAMstat final filtered file
        # final bam
        "samtools view -o - {input.bam} | "
        "SAMstats --sorted_sam_file -  --outf {output} > {log}"



        echo -e "Chromosome\tLength\tProperPairs\tBadPairs:Raw" > ${stats_log}
        samtools idxstats in.raw.bam >> ${stats_log}

        echo -e "Chromosome\tLength\tProperPairs\tBadPairs:Filtered" >> ${stats_log}
        samtools idxstats in.filtered.bam >> ${stats_log}

        echo '' > ${hist_log}
        java -jar $(which picard.jar) CollectInsertSizeMetrics \
            VALIDATION_STRINGENCY=SILENT \
            I=in.raw.bam \
            O=${hist_log} \
            H=${hist_log_pdf} \
            W=1000  2>> picard_run.log

        python3 $(which plot_insert_size_hist.py) ${hist_log} ${prefix} ${hist_log_png}

        # make TSS pileup fig # original code has a 'set +e' why?
        # the pyMakeVplot is missing
        python2 $(which make-tss-pileup-jbd.py) \
            -a in.filtered.bam \
            -b ${tss} \
            -e 2000 \
            -p ends \
            -v \
            -u \
            -o ${tss_pileup_prefix}

    }

    output {
        File atac_final_stats = stats_log
        File atac_final_hist_png = hist_log_png
        File atac_final_hist = stats_log
        File atac_tss_pileup_png = tss_pileup_out
        File atac_hist_log = hist_log
    }

    runtime {
        cpu : cpus
        memory : mem_gb+'G'
        disks : 'local-disk ${disk_gb} SSD'
        maxRetries : 0
        docker: docker_image
    }

    parameter_meta {
        raw_bam: {
                description: 'Unfiltered bam',
                help: 'Not filtered alignment bam file.',
                example: 'aligned.hg38.bam'
            }
        raw_bam: {
                description: 'Filtered bam',
                help: 'Filtered alignment bam file. Typically, no duplicates and quality filtered.',
                example: 'aligned.hg38.rmdup.filtered.bam'
            }
        tss: {
                description: 'TSS bed file',
                help: 'List of TSS in bed format used for the enrichment plot.',
                example: 'refseq.tss.bed'
            }
        genome_name: {
                description: 'Reference name',
                help: 'The name of the reference genome used by the aligner.',
                examples: ['hg38', 'mm10', 'both']
            }
        cpus: {
                description: 'Number of cpus',
                help: 'Set the number of cpus useb by bowtie2',
                examples: '4'
            }
        docker_image: {
                description: 'Docker image.',
                help: 'Docker image for preprocessing step. Dependencies: python3 -m pip install Levenshtein pyyaml Bio; apt install pigz',
                example: ['put link to gcr or dockerhub']
            }
    }
}
