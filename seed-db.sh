#!/usr/bin/env bash
##
# Seed image with a database from file.
#
# Usage:
# ./seed-db.sh path/to/db.sql myorg/myimage:latest
#
# DOCKER_DEFAULT_PLATFORM=linux/amd64 ./seed-db.sh path/to/db.sql myorg/myimage:latest
#
# shellcheck disable=SC2002

set -e
[ -n "${DREVOPS_DEBUG}" ] && set -x

# Database dump file as a first argument to the script.
DB_FILE="${DB_FILE:-$1}"

# Destination image as a second argument to the script.
DST_IMAGE="${DST_IMAGE:-$2}"

# Base image to start with.
BASE_IMAGE="${BASE_IMAGE:-drevops/mariadb-drupal-data}"

# User ID to run the container with.
RUN_USER="${RUN_USER:-1000}"

# Docker target platform architecture.
# Note that some shells report platform incorrectly. In such cases, run
# as `DOCKER_DEFAULT_PLATFORM=linux/amd64 ./seed-db.sh path/to/db.sql myorg/myimage:latest`
DOCKER_DEFAULT_PLATFORM="${DOCKER_DEFAULT_PLATFORM:-}"

# ------------------------------------------------------------------------------

[ -z "${DB_FILE}" ] && echo "ERROR: Path to the database dump file must be provided as a first argument." && exit 1
[ -z "${DST_IMAGE}" ] && echo "ERROR: Destination docker image name must be provided as a second argument." && exit 1
[ ! -f "${DB_FILE}" ] && echo "ERROR: Specified database dump file ${DB_FILE} does not exist." && exit 1

if [ "$(uname -m)" = "arm64" ]; then
  export DOCKER_DEFAULT_PLATFORM=linux/amd64
fi

if [ -n "${DOCKER_DEFAULT_PLATFORM}" ]; then
  echo "==> Using ${DOCKER_DEFAULT_PLATFORM} platform architecture."
fi

# Normalise image - add ":latest" if tag was not provided.
image="${DST_IMAGE}"
[ -n "${image##*:*}" ] && image="${image}:latest"

user_opts=()
if [ -n "${RUN_USER}" ]; then
  user_opts=(--user "${RUN_USER}")
fi

# Run container using the base image in the background.
cid=$(docker run "${user_opts[@]}" -d --rm "${BASE_IMAGE}")
echo "==> Started container with ID ${cid} from the base image ${BASE_IMAGE}."

echo -n "==> Waiting for the service to become ready."
docker exec "${user_opts[@]}" -i "${cid}" sh -c "until nc -z localhost 3306; do sleep 1; echo -n .; done; echo"

echo "==> Importing database from the file."
cat "${DB_FILE}" | docker exec "${user_opts[@]}" -i "${cid}" /usr/bin/mysql

# Testing that the data was successfully imported.
if docker exec "${user_opts[@]}" "${cid}" /usr/bin/mysql -e "show tables;" | grep -q users; then
  echo "==> Successfully imported data.";
else
  echo "ERROR: failed to import data."
  exit 1
fi

# Update permissions on the seeded DB files.
docker exec --user root "${cid}" bash -c "chown -R mysql /var/lib/db-data && /bin/fix-permissions /var/lib/db-data"

echo "==> Committing image with name \"${image}\"."
iid=$(docker commit "${cid}" "${image}")
iid="${iid#sha256:}"
echo "    Committed image with id \"${iid}\"."

echo "==> Stopping and removing container"
docker stop "${cid}" > /dev/null

echo "==> Image seeding complete."
echo "    Login to the Docker registry from your CLI and run:"
echo "    docker push ${image}"
