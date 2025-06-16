include {
    SKETCH_DATABASE_KMERS ;
    SKETCH_SAMPLE_KMERS ;
    CLASSIFY_SAMPLE ;
    OVERLAY_TAXONOMY ;
    SYLPH_TAX_DOWNLOAD ;
    MERGE_TAXONOMY
} from "../modules/sylph"

workflow METAGENOMICS {

    take:
    ch_ref
    ch_sylph_tax_db
    ch_sample_reads
    ch_taxonomy_files

    main:
    ch_custom_ref = ch_ref.filter { fa ->
        file(fa).getBaseName().endsWith("fasta") || file(fa).getBaseName().endsWith("fasta")
    }

    ch_prebuilt_ref = ch_ref.filter { fa ->
        !file(fa).getBaseName().endsWith("fasta") || !file(fa).getBaseName().endsWith("fasta")
    }

    SKETCH_DATABASE_KMERS(ch_custom_ref)

    ch_sylph_db_queue = SKETCH_DATABASE_KMERS.out.mix(ch_prebuilt_ref)

    SKETCH_SAMPLE_KMERS(ch_sample_reads)

    CLASSIFY_SAMPLE(
        SKETCH_SAMPLE_KMERS.out.combine(ch_sylph_db_queue)
    )

    if(params.sylph_tax_db){

        SYLPH_TAX_DOWNLOAD(
            CLASSIFY_SAMPLE.out
        )

        OVERLAY_TAXONOMY(
            // CLASSIFY_SAMPLE.out.combine(ch_taxonomy_files)            
            CLASSIFY_SAMPLE.out,
            ch_sylph_tax_db,
            SYLPH_TAX_DOWNLOAD.out
        )

        MERGE_TAXONOMY(
            OVERLAY_TAXONOMY.out
        )
    }

}
