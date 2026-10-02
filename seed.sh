#!/usr/bin/env bash
##
# Seed image with a database from a file.
# @see https://github.com/drevops/mariadb-drupal-data/blob/main/seed.sh
#
# The seeding process has 3 phases:
# 1. Create extracted DB files by starting a temporary container and
#    importing the database.
# 2. Build a new image from the base image and extracted DB files.
# 3. Start a container from the new image and verify that the database was
#    imported.
#
# Usage:
# ./seed.sh path/to/db.sql myorg/myimage:latest
#
# DESTINATION_PLATFORMS=linux/amd64,linux/arm64 ./seed.sh path/to/db.sql myorg/myimage:latest
#
# DOCKER_DEFAULT_PLATFORM=linux/amd64 ./seed.sh path/to/db.sql myorg/myimage:latest
#
# shellcheck disable=SC2002,SC2015

set -eu
[ -n "${DEBUG:-}" ] && set -x

DB_FILE="${DB_FILE:-${1}}"

DST_IMAGE="${DST_IMAGE:-${2}}"

# Exporting the databases needs a known mounted volume path, so phase 1 uses
# this same base image.
BASE_IMAGE="${BASE_IMAGE:-drevops/mariadb-drupal-data:latest}"

# Some shells report the platform incorrectly; in such cases, run as
# `DOCKER_DEFAULT_PLATFORM=linux/amd64 ./seed.sh path/to/db.sql myorg/myimage:latest`
DOCKER_DEFAULT_PLATFORM="${DOCKER_DEFAULT_PLATFORM:-}"

case "$(uname -m)" in
  x86_64) HOST_PLATFORM="linux/amd64" ;;
  arm64 | aarch64) HOST_PLATFORM="linux/arm64" ;;
  *) HOST_PLATFORM="linux/$(uname -m)" ;;
esac

# Defaults to the host platform, so Stage 3 starts and tests the Stage 2
# image natively on the machine running the seeding.
DESTINATION_PLATFORMS="${DESTINATION_PLATFORMS:-${HOST_PLATFORM}}"

LOG_DIR="${LOG_DIR:-.logs}"

TMP_STRUCTURE_DIR="${TMP_STRUCTURE_DIR:-.db-structure}"

LOG_IS_VERBOSE="${LOG_IS_VERBOSE:-}"

# ------------------------------------------------------------------------------

# @formatter:off
info() { [ -z "${TERM_NO_COLOR:-}" ] && tput colors >/dev/null 2>&1 && printf "\n[\033[36mINFO\033[0m] %s\n\n" "${1}" || printf "\n[INFO] %s\n" "${1}"; }
task() { [ -z "${TERM_NO_COLOR:-}" ] && tput colors >/dev/null 2>&1 && printf "[\033[34mTASK\033[0m] %s\n" "${1}" || printf "[TASK] %s\n" "${1}"; }
pass() { [ -z "${TERM_NO_COLOR:-}" ] && tput colors >/dev/null 2>&1 && printf "[ \033[32mOK\033[0m ] %s\n" "${1}" || printf "[ OK ] %s\n" "${1}"; }
fail() { [ -z "${TERM_NO_COLOR:-}" ] && tput colors >/dev/null 2>&1 && printf "\033[31m[FAIL] %s\033[0m\n" "${1}" || printf "[FAIL] %s\n" "${1}"; }
note() { printf "       %s\n" "${1}"; }
# @formatter:on

[ -z "${DB_FILE}" ] && fail "Path to the database dump file must be provided as the first argument." && exit 1
[ -z "${DST_IMAGE}" ] && fail "Destination Docker image name must be provided as the second argument." && exit 1
[ ! -f "${DB_FILE}" ] && fail "Specified database dump file ${DB_FILE} does not exist." && exit 1
[ "${BASE_IMAGE##*/}" = "${BASE_IMAGE}" ] && fail "${BASE_IMAGE} should be in a format myorg/myimage." && exit 1
[ "${DST_IMAGE##*/}" = "${DST_IMAGE}" ] && fail "${DST_IMAGE} should be in a format myorg/myimage." && exit 1

restore_dockerignore() {
  [ ! -f ".dockerignore.bak" ] && return

  task "Restore .dockerignore from .dockerignore.bak"
  mv .dockerignore.bak .dockerignore

  if [ ! -f ".dockerignore" ]; then
    fail "Unable to restore .dockerignore from .dockerignore.bak"
    exit 1
  fi

  pass "Restored .dockerignore from .dockerignore.bak"
}

# Collect logs and display them on script exit.
cleanup() {
  if [ $? -ne 0 ]; then
    fail "Collecting logs after failure."
    if [ -d "${LOG_DIR}" ] && [ -z "${LOG_IS_VERBOSE}" ]; then
      for log_file in "${LOG_DIR}"/*.log; do
        echo
        note "--- Displaying ${log_file} ---"
        echo
        cat "${log_file}"
        echo
      done
    else
      note "No logs available to display."
    fi

    restore_dockerignore
  fi
}

trap cleanup EXIT

log_container() {
  name="${1?Missing log name}"
  prefix="${2-}"

  mkdir -p "${LOG_DIR}" >/dev/null
  log_file="${LOG_DIR}/${prefix}${name}.log"

  if [ -n "${LOG_IS_VERBOSE}" ]; then
    docker logs "${name}" | tee -a "${log_file}"
  else
    docker logs "${name}" &>>"${log_file}"
  fi
}

wait_for_db_service() {
  cid="${1}"

  user=()
  [ -n "${2-}" ] && user=("--user=${2}")

  echo -n "       Waiting for the service to become ready."
  if ! docker exec "${user[@]}" -i "${cid}" sh -c "until nc -z localhost 3306; do sleep 1; echo -n .; done; echo"; then
    fail "MySQL service did not start successfully."
    log_container "${cid}"
    exit 1
  fi
  log_container "${cid}"
  pass "MySQL is running."
}

assert_db_system_tables_present() {
  user=()
  [ -n "${2-}" ] && user=("--user=${2}")

  if docker exec "${user[@]}" "${1}" /usr/bin/mysql -e "SHOW TABLES FROM information_schema;" | grep -q user_variables; then
    pass "Database system tables present."
  else
    fail "Database system tables are not present in container ${1}"
    exit 1
  fi
}

assert_db_was_imported() {
  user=()
  [ -n "${2-}" ] && user=("--user=${2}")

  if docker exec "${user[@]}" "${1}" /usr/bin/mysql -e "SHOW TABLES;" | grep -q users; then
    pass "Imported database exists."
  else
    fail "Imported database does not exist in container ${1}"
    exit 1
  fi
}

# Sets 'cid' to the ID of the started container.
start_container() {
  task "Start container from the image ${1}"

  user=()
  [ -n "${2-}" ] && user=("--user=${2}")

  cid="$(docker run "${user[@]}" -d "${1}" 2>"${LOG_DIR}/container-start.log")"
  cat "${LOG_DIR}/container-start.log" >>"${LOG_DIR}/${cid}.log" && rm "${LOG_DIR}/container-start.log" || true

  wait_for_db_service "${cid}" "${2-}"
  assert_db_system_tables_present "${cid}" "${2-}"

  pass "Started container ${cid}"
}

stop_container() {
  task "Stop and remove container ${1}"
  log_container "${1}" "stopped-"
  docker stop "${1}" >/dev/null
  docker rm -v "${1}" >/dev/null
  pass "Stopped and removed container ${1}"
}

# ------------------------------------------------------------------------------

info "Started database seeding."

rm -Rf "${LOG_DIR}" >/dev/null
mkdir -p "${LOG_DIR}" >/dev/null

rm -Rf "${TMP_STRUCTURE_DIR}" >/dev/null
mkdir -p "${TMP_STRUCTURE_DIR}" >/dev/null

if [ -n "${DOCKER_DEFAULT_PLATFORM}" ]; then
  note "Source platform architecture: ${DOCKER_DEFAULT_PLATFORM}"
fi

# Normalize image - add ":latest" if tag was not provided.
[ -n "${DST_IMAGE##*:*}" ] && DST_IMAGE="${DST_IMAGE}:latest"
note "Host platform: ${HOST_PLATFORM}"
note "Destination image: ${DST_IMAGE}"
note "Destination platform(s): ${DESTINATION_PLATFORMS}"

if [ -f ".dockerignore" ]; then
  task "Move .dockerignore to .dockerignore.bak"
  mv .dockerignore .dockerignore.bak
  if [ ! -f ".dockerignore.bak" ]; then
    fail "Unable to move .dockerignore to .dockerignore.bak"
    exit 1
  fi
  pass "Moved .dockerignore to .dockerignore.bak"
fi

info "Stage 1: Produce database structure files from dump file"

task "Pull the base image ${BASE_IMAGE}."
docker pull "${BASE_IMAGE}"
pass "Pulled the base image ${BASE_IMAGE}."

start_container "${BASE_IMAGE}"

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
docker exec "${cid}" bash -c "chown -R mysql:mysql /home/db-data && /bin/fix-permissions /home/db-data" || true
pass "Updated permissions on the seeded database files."

task "Copy expanded database files to host"
docker cp "${cid}":/home/db-data/. "${TMP_STRUCTURE_DIR}/" >/dev/null
[ ! -d "${TMP_STRUCTURE_DIR}/mysql" ] && fail "Unable to copy expanded database files to host" && ls -al "${TMP_STRUCTURE_DIR}" && exit 1
pass "Copied expanded database files to host"

stop_container "${cid}"

info "Stage 2: Build image"

task "Build image ${DST_IMAGE} for ${DESTINATION_PLATFORMS} platform(s) from ${BASE_IMAGE}."
cat <<EOF | docker buildx build --no-cache --build-arg="BASE_IMAGE=${BASE_IMAGE}" --platform "${DESTINATION_PLATFORMS}" --tag "${DST_IMAGE}" --push -f - .
ARG BASE_IMAGE
FROM ${BASE_IMAGE}
COPY --chown=mysql:mysql ${TMP_STRUCTURE_DIR} /home/db-data/
USER root
RUN /bin/fix-permissions /home/db-data
USER mysql
EOF
pass "Built image ${DST_IMAGE} for ${DESTINATION_PLATFORMS} platform(s) from ${BASE_IMAGE}."

info "Stage 3: Test image"

start_container "${DST_IMAGE}" 1000
assert_db_was_imported "${cid}" 1000
stop_container "${cid}"

restore_dockerignore

info "Finished database seeding."
note "https://hub.docker.com/r/${DST_IMAGE%:*}/tags"
