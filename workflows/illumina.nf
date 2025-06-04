include { GATHER_ILLUMINA } from "../subworkflows/gather_illumina"
include { ILLUMINA_CORRECTION } from "../subworkflows/illumina_correction"
include { PRIMER_HANDLING } from "../subworkflows/primer_handling"
include { ALIGNMENT } from "../subworkflows/alignment"
include { QUALITY_CONTROL } from "../subworkflows/quality_control"
include { CONSENSUS } from "../subworkflows/consensus_calling"
include { VARIANTS } from "../subworkflows/variant_calling"
include { METAGENOMICS } from "../subworkflows/metagenomics"
include { PHYLO } from "../subworkflows/phylo"

workflow ILLUMINA {

    take:
        ch_primer_bed
        ch_refseq
        ch_ref_gbk
        ch_contam_fasta
        ch_snpeff_config
        ch_metagenome_ref
        ch_primer_tsv

    main:
        assert params.platform == "illumina"
        assert params.illumina_fastq_dir != "" :
        "Please double check that a directory of Illumina FASTQs or Nanopore POD5s is provided."
        assert file( params.illumina_fastq_dir ).isDirectory() :
        "The provided Illumina FASTQ directory ${params.illumina_fastq_dir} does not exist."

        GATHER_ILLUMINA ( )

        ILLUMINA_CORRECTION (
            GATHER_ILLUMINA.out,
            ch_contam_fasta
        )

        if ( params.primer_bed || params.primer_tsv ) {

            PRIMER_HANDLING (
                ILLUMINA_CORRECTION.out,
                ch_primer_bed,
                ch_refseq,
                ch_primer_tsv
            )

            // QUALITY_CONTROL (
            //     PRIMER_HANDLING.out,
            //     ch_contam_fasta
            // )

            METAGENOMICS(
                ch_metagenome_ref,
                PRIMER_HANDLING.out,
                Channel.empty()
            )

            ALIGNMENT (
                PRIMER_HANDLING.out,
                ch_refseq
            )

        } else {

            METAGENOMICS(
                ch_metagenome_ref,
                ILLUMINA_CORRECTION.out,
                Channel.empty()
            )

            ALIGNMENT (
                ILLUMINA_CORRECTION.out,
                ch_refseq
            )

        }

        CONSENSUS (
            ALIGNMENT.out
        )

        VARIANTS (
            ALIGNMENT.out,
            ch_refseq,
            ch_ref_gbk,

            ch_snpeff_config
        )

        PHYLO (
            CONSENSUS.out
        )

}
