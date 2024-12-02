#!/usr/bin/env bash
##
# Seed image with a database from file.
#
# The seeding process has 3-phases build:
# 1. Create extracted DB files by starting a temporary container and importing database.
# 2. Build a new image from the base image and extracted DB files.
# 3. Start a container from the new image and verify that the database was imported.
#
# Usage:
# ./seed-db.sh path/to/db.sql myorg/myimage:latest
#
# DOCKER_DEFAULT_PLATFORM=linux/amd64 ./seed-db.sh path/to/db.sql myorg/myimage:latest
#
# shellcheck disable=SC2002,SC2015

set -eu
[ -n "${DREVOPS_DEBUG:-}" ] && set -x

# Database dump file as a first argument to the script.
DB_FILE="${DB_FILE:-$1}"

# Destination image as a second argument to the script.
DST_IMAGE="${DST_IMAGE:-$2}"

# Base image to start with.
# We have to use the same base image for phase 1 because we need a known mounted
# volume path to export databases.
BASE_IMAGE="${BASE_IMAGE:-drevops/mariadb-drupal-data:latest}"

# Docker target platform architecture.
# Note that some shells report platform incorrectly. In such cases, run
# as `DOCKER_DEFAULT_PLATFORM=linux/amd64 ./seed-db.sh path/to/db.sql myorg/myimage:latest`
DOCKER_DEFAULT_PLATFORM="${DOCKER_DEFAULT_PLATFORM:-}"

# Destination platforms to build for.
DESTINATION_PLATFORMS="${DESTINATION_PLATFORMS:-linux/amd64,linux/arm64}"

# Log directory on host to store container logs.
LOG_DIR="${LOG_DIR:-.logs}"

# Temporary data directory on host.
TMP_DATA_DIR="${TMP_DATA_DIR:-.data}"

# ------------------------------------------------------------------------------

# @formatter:off
#info() { printf "%s\n" "$1"; echo;}

info() { [ -z "${TERM_NO_COLOR:-}" ] && tput colors >/dev/null 2>&1 && printf "\n[\033[36mINFO\033[0m] %s\n\n" "$1" || printf "\n[INFO] %s\n" "$1"; }
task() { [ -z "${TERM_NO_COLOR:-}" ] && tput colors >/dev/null 2>&1 && printf "[\033[34mTASK\033[0m] %s\n" "$1" || printf "[TASK] %s\n" "$1"; }
pass() { [ -z "${TERM_NO_COLOR:-}" ] && tput colors >/dev/null 2>&1 && printf "[ \033[32mOK\033[0m ] %s\n" "$1" || printf "[ OK ] %s\n" "$1"; }
fail() { [ -z "${TERM_NO_COLOR:-}" ] && tput colors >/dev/null 2>&1 && printf "\033[31m[FAIL] %s\033[0m\n" "$1" || printf "[FAIL] %s\n" "$1"; }
note() { printf "       %s\n" "$1"; }
# @formatter:on

[ -z "${DB_FILE}" ] && fail "Path to the database dump file must be provided as a first argument." && exit 1
[ -z "${DST_IMAGE}" ] && fail "Destination docker image name must be provided as a second argument." && exit 1
[ ! -f "${DB_FILE}" ] && fail "Specified database dump file ${DB_FILE} does not exist." && exit 1
[ "${BASE_IMAGE##*/}" = "$BASE_IMAGE" ] && fail "${BASE_IMAGE} should be in a format myorg/myimage." && exit 1
[ "${DST_IMAGE##*/}" = "$DST_IMAGE" ] && fail "${DST_IMAGE} should be in a format myorg/myimage." && exit 1

log_container() {
  mkdir -p "${LOG_DIR}" >/dev/null
  docker logs "${1}" >>"${LOG_DIR}/${2:-}${1}.log" 2>&1
}

wait_for_db_service() {
  echo -n "       Waiting for the service to become ready."
  docker exec --user 1000 -i "${1}" sh -c "until nc -z localhost 3306; do sleep 1; echo -n .; done; echo"
  log_container "${cid}"
  pass "MYSQL is running."
}

assert_db_system_tables_present() {
  if docker exec --user 1000 "${1}" /usr/bin/mysql -e "show tables from information_schema;" | grep -q user_variables; then
    pass "Database system tables present."
  else
    pass "Database system tables are not present in container ${1}"
    exit 1
  fi
}

assert_db_was_imported() {
  if docker exec --user 1000 "${1}" /usr/bin/mysql -e "show tables;" | grep -q users; then
    pass "Imported database exists."
  else
    fail "Imported database does not exist in container ${1}"
    exit 1
  fi
}

start_container() {
  task "Start container from the image ${1}"
  cid=$(docker run -d --rm "${1}" 2>"$LOG_DIR"/container-start.log)
  cat "${LOG_DIR}"/container-start.log >>"$LOG_DIR/${cid}.log" && rm "${LOG_DIR}"/container-start.log || true
  pass "Started container ${cid}"
  wait_for_db_service "${cid}"
  assert_db_system_tables_present "${cid}"
}

get_started_container_id() {
  docker ps -q --filter ancestor="${1}" --filter status=running | head -n 1
}

stop_container() {
  task "Stop and removing container ${1}"
  # Log container output before stopping it into a separate log file for debugging.
  log_container "${1}" "stopped-"
  docker stop "${1}" >/dev/null
  pass "Stopped and removed container ${1}"
}

# ------------------------------------------------------------------------------

info "Started database seeding."

rm -Rf "${LOG_DIR}" >/dev/null
mkdir -p "${LOG_DIR}" >/dev/null

rm -Rf "${TMP_DATA_DIR}" >/dev/null
mkdir -p "${TMP_DATA_DIR}" >/dev/null

if [ "$(uname -m)" = "arm64" ]; then
  export DOCKER_DEFAULT_PLATFORM=linux/amd64
fi

if [ -n "${DOCKER_DEFAULT_PLATFORM}" ]; then
  task "Source platform architecture: ${DOCKER_DEFAULT_PLATFORM}"
fi

# Normalise image - add ":latest" if tag was not provided.
[ -n "${DST_IMAGE##*:*}" ] && DST_IMAGE="${DST_IMAGE}:latest"
note "Destination image: ${DST_IMAGE}"
note "Destination platform(s): ${DESTINATION_PLATFORMS}"

info "Stage 1: Produce database structure files from dump"

start_container "${BASE_IMAGE}"
cid="$(get_started_container_id "${BASE_IMAGE}")"

task "Import database from the ${DB_FILE} file."
cat "${DB_FILE}" | docker exec -i "${cid}" /usr/bin/mysql
assert_db_was_imported "${cid}"

task "Upgrade database after import."
docker exec "${cid}" /usr/bin/mysql -e "FLUSH TABLES WITH READ LOCK;"
docker exec "${cid}" /usr/bin/mysql -e "UNLOCK TABLES;"
docker exec "${cid}" bash -c "mysql_upgrade --force"
docker exec "${cid}" /usr/bin/mysql -e "FLUSH TABLES WITH READ LOCK;"
assert_db_was_imported "${cid}"
pass "Upgraded database after import."

task "Update permissions on the seeded database files."
docker exec "${cid}" bash -c "chown -R mysql /var/lib/db-data && /bin/fix-permissions /var/lib/db-data" || true
pass "Updated permissions on the seeded database files."

task "Copy expanded database files to host"
mkdir -p "${TMP_DATA_DIR}"
docker cp "${cid}":/var/lib/db-data/. "${TMP_DATA_DIR}/"
[ ! -d "${TMP_DATA_DIR}/mysql" ] && fail "Unable to copy expanded database files to host " && ls -al "${TMP_DATA_DIR}" && exit 1
pass "Copied expanded database files to host"

stop_container "${cid}"

info "Stage 2: Build image"

task "Build image ${DST_IMAGE} for ${DESTINATION_PLATFORMS} platform(s)."
docker buildx build --no-cache --platform "${DESTINATION_PLATFORMS}" --tag "${DST_IMAGE}" --push -f Dockerfile.seed .
pass "Built image ${DST_IMAGE} for ${DESTINATION_PLATFORMS} platform(s)."

info "Stage 3: Test image"

start_container "${DST_IMAGE}"
cid="$(get_started_container_id "${DST_IMAGE}")"
assert_db_was_imported "${cid}"
stop_container "${cid}"

info "Finished database seeding."
note "https://hub.docker.com/r/${DST_IMAGE%:*}/tags"
