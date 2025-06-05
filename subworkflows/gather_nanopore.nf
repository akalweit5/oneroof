#!/usr/bin/env nextflow

include { WATCH_FOR_POD5S     } from "../modules/file_watcher"
include { PUBLISH_COMMAND     } from "../modules/reporting"
include { DOWNLOAD_MODELS ; BASECALL ; DEMULTIPLEX } from "../modules/dorado"
include { MERGE_BAMS          } from "../modules/samtools"
include { VALIDATE_NANOPORE   } from "../modules/validate"
include { FILTER_WITH_CHOPPER } from "../modules/chopper"
include { COMPRESS_TO_SORTED_FASTA } from "../modules/seqkit"
include { FAIDX             } from "../modules/samtools"
include { EARLY_RASUSA_READ_DOWNSAMPLING } from "../modules/rasusa"



workflow GATHER_NANOPORE {
    main:

    PUBLISH_COMMAND()

    // Invoke Dorado basecaller and demultiplexer if pod5's are provided
    // ------------------------------------------------------------------ //

    if (params.remote_pod5_location != "" || params.pod5_dir != "") {

        assert params.kit : "Please provide the Nanopore barcoding kit used."

        DOWNLOAD_MODELS()

        if (params.remote_pod5_location != "") {

            assert params.file_watcher_config && file(params.file_watcher_config).isFile() : """
                To watch for remote files, a YAML-formatted configuration file with
                an IP address, username/password, remote path, and file pattern
                must be provided with the parameter `--file_watcher_config`. An
                example template can be found at ${projectDir}/conf/file_watcher.template.yml
                """

            ch_remote_pod5s = Channel.from(params.remote_pod5_location)

            WATCH_FOR_POD5S(
                ch_remote_pod5s
            )

            ch_staged_pod5s = Channel
                .watchPath("${params.pod5_staging}/*.pod5", 'create')
                .until { x -> file(x).getSimpleName() == "DONE" }
                .buffer(size: params.pod5_batch_size ?: 100)

            BASECALL(
                DOWNLOAD_MODELS.out.collect(),
                ch_staged_pod5s,
            )
        }
        else {

            assert file(params.pod5_dir).isDirectory() : "Please double check that the provided POD5 directory exists: ${params.pod5_dir}"

            pod5_count = file("${params.pod5_dir}/*.pod5").size()

            assert pod5_count > 0 : "Provided pod5 directory '${params.pod5_dir}' contains no files with the .pod5 extension."

            ch_local_pod5s = Channel
                .fromPath("${params.pod5_dir}/*.pod5")
                .buffer(size: params.pod5_batch_size ?: pod5_count)

            BASECALL(
                DOWNLOAD_MODELS.out.collect(),
                ch_local_pod5s,
            )
        }

        MERGE_BAMS(
            BASECALL.out.collect()
        )

        DEMULTIPLEX(
            MERGE_BAMS.out
        )

        VALIDATE_NANOPORE(
            DEMULTIPLEX.out
                .flatten()
                .filter { !it[0].toString().contains("unclassified") }
                .groupTuple(by: 0)
        )
    }
    else if (params.precalled_staging != "") {

        assert params.precalled_staging && file(params.precalled_staging).isDirectory() : """
            No local or remote pod5 directories were supplied. Please supply a directory of
            pre-called and pre-demultiplexed BAM or FASTQ files to run the Nanopore pipeline.
            """

        ch_fastq_staging = Channel
            .watchPath("${params.precalled_staging}/*.fastq.gz", 'create')
            .until { x -> file(x).getSimpleName() == "DONE" }
            .map { fastq -> tuple(file(fastq).getSimpleName(), file(fastq)) }

        ch_bam_staging = Channel
            .watchPath("${params.precalled_staging}/*.bam", 'create')
            .until { x -> file(x).getSimpleName() == "DONE" }
            .map { bam -> tuple(file(bam).getSimpleName(), file(bam)) }

        VALIDATE_NANOPORE(
            ch_fastq_staging.mix(ch_bam_staging)
        )
    }
    else if (params.prepped_data && params.prepped_data != "") {

        assert file(params.prepped_data).isDirectory() : """
            No local or remote pod5 directories were supplied. Please supply a directory of
            pre-called and pre-demultiplexed BAM or FASTQ files to run the Nanopore pipeline.
            """

        ch_prepped_fastq = Channel
            .fromPath("${params.prepped_data}/*.fastq.gz")
            .map { fastq -> tuple(file(fastq).getSimpleName(), file(fastq)) }

        ch_prepped_bam = Channel
            .fromPath("${params.prepped_data}/*.bam")
            .map { bam -> tuple(file(bam).getSimpleName(), file(bam)) }

        VALIDATE_NANOPORE(
            ch_prepped_fastq.mix(ch_prepped_bam)
        )
    }
    else {

        error "No directories containing valid data provided."
    }

    // ------------------------------------------------------------------ //

    FILTER_WITH_CHOPPER(
        VALIDATE_NANOPORE.out.map { label, seq_file, _status -> tuple(label, file(seq_file)) }
    )
    

    COMPRESS_TO_SORTED_FASTA(
        FILTER_WITH_CHOPPER.out
    )

    FAIDX(
        COMPRESS_TO_SORTED_FASTA.out
            .map { id, fastq -> tuple(id, fastq, file(fastq).countFasta()) }
            .filter { it[2] > 0 }
            .map { id, fastq, _read_count -> tuple(id, file(fastq)) }
    )

    EARLY_RASUSA_READ_DOWNSAMPLING(
        FAIDX.out
    )

    emit:
    EARLY_RASUSA_READ_DOWNSAMPLING.out

}
