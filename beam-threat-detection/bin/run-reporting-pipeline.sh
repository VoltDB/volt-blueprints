#!/usr/bin/env bash
# Launch the ReportingPipeline (Beam batch, Path 3) on Google Cloud Dataflow.
#
# Reads new rows from VoltDB TRANSACTIONS since the watermark, enriches with
# GeoIP, and writes to the BigQuery `transactions` table (which is defined
# with table_format='ICEBERG' + storage_uri in GCS, so BigQuery stores each
# written row as Iceberg Parquet files on GCS under
# beam_threat_detection/transactions/).
#
# Prerequisites (all one-time, see RUNBOOK §4, §5, §7):
#   - VoltDB cluster running on GKE (central1 / beam-threat ns, release mp-threat).
#   - Internal LB `mp-threat-voltdb-dataflow-ilb` with EXTERNAL-IP = $VOLTDB_ILB.
#   - BQ dataset `beam_threat_detection` in us-central1 with the Iceberg-backed
#     `transactions` table already created (see RUNBOOK §7).
#   - GeoLite2-City.mmdb uploaded to gs://$BUCKET/geoip/.
#   - gcloud application-default credentials: `gcloud auth application-default login`.
#
# Overridable via env vars (all have working defaults):
#   PROJECT, REGION, BUCKET, VOLTDB_ILB, INITIAL_WATERMARK_MS,
#   BQ_DATASET, BQ_TABLE, GEOIP_MMDB
#
# Common run shapes:
#   # fresh full-pull backfill:
#   ./bin/run-reporting-pipeline.sh
#   # resume from BQ MAX(TXN_TIME) (production cadence):
#   INITIAL_WATERMARK_MS=-1 ./bin/run-reporting-pipeline.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

PROJECT="${PROJECT:-voltdb-operator}"
REGION="${REGION:-us-central1}"
BUCKET="${BUCKET:-mpopova_volt_central1}"
VOLTDB_ILB="${VOLTDB_ILB:-10.128.0.40}"
INITIAL_WATERMARK_MS="${INITIAL_WATERMARK_MS:-0}"
BQ_DATASET="${BQ_DATASET:-beam_threat_detection}"
BQ_TABLE="${BQ_TABLE:-transactions}"
GEOIP_MMDB="${GEOIP_MMDB:-gs://${BUCKET}/geoip/GeoLite2-City.mmdb}"

JOB_NAME="reporting-$(date -u +%Y%m%d-%H%M%S)"

mvn -q compile exec:java -Pdataflow-runner \
    -Dexec.mainClass=org.voltdb.example.threat.pipelines.ReportingPipeline \
    -Dexec.args="\
        --runner=DataflowRunner \
        --project=${PROJECT} \
        --region=${REGION} \
        --tempLocation=gs://${BUCKET}/dataflow/temp \
        --stagingLocation=gs://${BUCKET}/dataflow/staging \
        --jobName=${JOB_NAME} \
        --voltdbHosts=${VOLTDB_ILB}:21212 \
        --initialWatermarkMs=${INITIAL_WATERMARK_MS} \
        --bqDataset=${BQ_DATASET} \
        --bqTable=${BQ_TABLE} \
        --geoipDbGcsUri=${GEOIP_MMDB} \
        $*"
