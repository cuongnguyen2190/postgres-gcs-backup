#!/bin/bash
set -o pipefail
set -o errexit
set -o errtrace
set -o nounset
# set -o xtrace

JOB_NAME=${JOB_NAME:-default-job}
BACKUP_DIR=${BACKUP_DIR:-/tmp}
BOTO_CONFIG_PATH=${BOTO_CONFIG_PATH:-/root/.boto}
GCS_BUCKET=${GCS_BUCKET:-}
GCS_KEY_FILE_PATH=${GCS_KEY_FILE_PATH:-}
POSTGRES_HOST=${POSTGRES_HOST:-localhost}
POSTGRES_PORT=${POSTGRES_PORT:-5432}
POSTGRES_DB=${POSTGRES_DB:-}
POSTGRES_USER=${POSTGRES_USER:-}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-}
SLACK_ALERTS=${SLACK_ALERTS:-}
SLACK_AUTHOR_NAME=${SLACK_AUTHOR_NAME:-postgres-gcs-backup}
SLACK_WEBHOOK_URL=${SLACK_WEBHOOK_URL:-}

backup() {
  mkdir -p $BACKUP_DIR
  date=$(date "+%Y-%m-%dT%H:%M:%SZ")
  archive_name="$date-$JOB_NAME-backup.sql.gz"
  cmd_auth_part=""
  if [[ ! -z $POSTGRES_USER ]] && [[ ! -z $POSTGRES_PASSWORD ]]
  then
    cmd_auth_part="--username=\"$POSTGRES_USER\" "
  fi

  cmd_db_part=""
  if [[ ! -z $POSTGRES_DB ]]
  then
    cmd_db_part="--db=\"$POSTGRES_DB\""
  fi

  export PGPASSWORD=$POSTGRES_PASSWORD
  cmd="pg_dump --host=\"$POSTGRES_HOST\" --port=\"$POSTGRES_PORT\" $cmd_auth_part $cmd_db_part | gzip > $BACKUP_DIR/$archive_name"
  echo "starting to backup PostGRES host=$POSTGRES_HOST port=$POSTGRES_PORT"

  eval "$cmd"
}

upload_to_gcs() {
  if [[ ! "$GCS_BUCKET" =~ gs://* ]]; then
    GCS_BUCKET="gs://${GCS_BUCKET}"
  fi

  if [[ $GCS_KEY_FILE_PATH != "" ]]
  then
cat <<EOF > $BOTO_CONFIG_PATH
[Credentials]
gs_service_key_file = $GCS_KEY_FILE_PATH
[Boto]
https_validate_certificates = True
[GoogleCompute]
[GSUtil]
content_language = en
default_api_version = 2
[OAuth2]
EOF
  fi
  echo "uploading backup archive to GCS bucket=$GCS_BUCKET"
  gsutil cp $BACKUP_DIR/$archive_name $GCS_BUCKET
}

send_discord_message() {
  local message=${1}

  curl -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST --data "{\"text\": \"${message}\"}" \
    ${SLACK_WEBHOOK_URL} || true
  echo
}

err() {
  err_msg="${JOB_NAME} Something went wrong on line $(caller)"
  echo $err_msg >&2
  if [[ $SLACK_ALERTS == "true" ]]
  then
    send_discord_message "Error while performing postgres backup: $err_msg"
  fi
}

cleanup() {
  rm $BACKUP_DIR/$archive_name
}

date=$(date "+%Y-%m-%dT%H:%M:%SZ")
trap err ERR
backup
upload_to_gcs
cleanup
send_discord_message "Backup is done: ${date}"