process FIND_COMPLETE_AMPLICONS {

    /* */

	errorStrategy { task.attempt < 3 ? 'retry' : 'ignore' }
	maxRetries 2

	cpus 3

    input:
	each path(reads)
    each path(patterns)

    output:
    tuple val(barcode), path("${barcode}_amplicons.fastq.gz")

    script:
	barcode = file(reads).getSimpleName()
    """
	cat ${reads} | \
    seqkit grep \
	--threads ${task.cpus} \
	--max-mismatch ${params.max_mismatch} \
	--by-seq \
	--delete-matched \
	--use-regexp \
	--pattern-file ${patterns} \
	-o ${barcode}_amplicons.fastq.gz
    """

}

process MERGE_BY_SAMPLE {

    /* */

	tag "${barcode}"
	publishDir params.complete_amplicons, mode: 'copy', overwrite: true

	errorStrategy { task.attempt < 3 ? 'retry' : 'ignore' }
	maxRetries 2

	cpus 3

	input:
	tuple val(barcode), path("fastqs/???.fastq.gz")

	output:
	tuple val(barcode), path("${barcode}.amplicons.fastq.gz")

	script:
	"""
	seqkit scat \
	--find-only \
	--threads ${task.cus}
	fastqs/ \
	| gzip -c > ${barcode}.amplicons.fastq.gz
	"""
}

process AMPLICON_STATS {

    /* */

	tag "${barcode}"
	publishDir params.complete_amplicons, mode: 'copy', overwrite: true

	errorStrategy { task.attempt < 3 ? 'retry' : 'ignore' }
	maxRetries 2

	cpus 3

	input:
	tuple val(barcode), path("amplicons/*")

    output:
    path "*"

    script:
    """
    seqkit stats --all --tabular amplicons/*.f{a,q}.gz
    """

}