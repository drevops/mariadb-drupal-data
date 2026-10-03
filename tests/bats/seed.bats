#!/usr/bin/env bats
#
# tests/bats/node_modules/.bin/bats --tap tests/bats/seed.bats
#
# These tests run for the host platform by default. To run them for another
# platform, set DOCKER_DEFAULT_PLATFORM to that platform; the Docker buildx
# driver must support it.
#
# DOCKER_DEFAULT_PLATFORM=linux/arm64 tests/bats/node_modules/.bin/bats --tap tests/bats/seed.bats
#
# The tests copy the source code at the last commit into the test directory,
# so uncommitted changes are not tested.
#
# shellcheck disable=SC2030,SC2031

load _helper

@test "Seeding of the data works" {
  tag="${TEST_DOCKER_TAG}"
  export BASE_IMAGE="drevops/mariadb-drupal-data-test:${tag}-base"
  destination_image="drevops/mariadb-drupal-data-test:${tag}-destination"

  step "Prepare base image."

  substep "Copy fixture database dump."
  file="${BUILD_DIR}/db.sql"
  cp "${BATS_TEST_DIRNAME}/fixtures/db.sql" "${file}"

  substep "Build and push a fresh base image tagged with ${BASE_IMAGE}."
  docker buildx build --platform "${BUILDX_PLATFORMS}" --load --push --no-cache -t "${BASE_IMAGE}" .

  step "Assert seeding without mysql upgrade works."

  # The test's `BUILDX_PLATFORMS` is named differently from the seeding
  # script's `DESTINATION_PLATFORMS` to keep test-environment image builds
  # separate from the seeding process.
  export DESTINATION_PLATFORMS="${BUILDX_PLATFORMS}"
  substep "Run database seeding script for ${destination_image} from the base image ${BASE_IMAGE} for destination platform(s) ${DESTINATION_PLATFORMS}."
  ./seed.sh "${file}" "${destination_image}" >&3

  substep "Start container from the seeded image ${destination_image}."
  # The container runs as a non-root user to imitate limited host permissions.
  cid="$(docker run --user 1000 -d "${destination_image}" 2>&3)"

  wait_mysql "${cid}"

  substep "Assert that data was captured into the new image."
  run docker exec --user 1000 "${cid}" /usr/bin/mysql -e "USE drupal; SHOW TABLES;" drupal
  assert_success
  assert_output_contains "users"

  substep "Assert that the data was captured as imported without sanitization."
  run docker exec --user 1000 "${cid}" /usr/bin/mysql -e "SELECT mail FROM users_field_data WHERE uid = 1;" drupal
  assert_success
  assert_output_contains "admin@example.com"

  # Control for the sanitization test, where the same search must find nothing.
  run docker run --rm --entrypoint grep "${destination_image}" -rl "admin@example.com" /home/db-data
  assert_success

  substep "Assert that the mysql upgrade was skipped by default."
  run docker logs "${cid}"
  assert_success
  assert_output_not_contains "starting mysql upgrade"

  step "Assert mysql upgrade works in container started from already seeded image."

  substep "Start container from the seeded image ${destination_image} and request an upgrade."
  # The container runs as a non-root user to imitate limited host permissions.
  cid="$(docker run --user 1000 -d -e MARIADB_FORCE_UPGRADE=1 "${destination_image}" 2>&3)"

  wait_mysql "${cid}"

  substep "Assert that the mysql upgrade was performed."
  run docker logs "${cid}"
  assert_success
  assert_output_contains "starting mysql upgrade"

  substep "Assert that data is present in the new image after the upgrade."
  run docker exec --user 1000 "${cid}" /usr/bin/mysql -e "USE drupal; SHOW TABLES;" drupal
  assert_success
  assert_output_contains "users"
}

@test "Seeding of the data works with .dockerignore" {
  tag="${TEST_DOCKER_TAG}"
  export BASE_IMAGE="drevops/mariadb-drupal-data-test:${tag}-base"
  destination_image="drevops/mariadb-drupal-data-test:${tag}-destination"

  step "Prepare .dockerignore file."
  echo ".db-structure" >.dockerignore
  assert_file_not_exists .dockerignore.bak

  step "Prepare base image."

  substep "Copy fixture database dump."
  file="${BUILD_DIR}/db.sql"
  cp "${BATS_TEST_DIRNAME}/fixtures/db.sql" "${file}"

  substep "Build and push a fresh base image tagged with ${BASE_IMAGE}."
  docker buildx build --platform "${BUILDX_PLATFORMS}" --load --push --no-cache -t "${BASE_IMAGE}" .

  step "Assert seeding without mysql upgrade works."

  # The test's `BUILDX_PLATFORMS` is named differently from the seeding
  # script's `DESTINATION_PLATFORMS` to keep test-environment image builds
  # separate from the seeding process.
  export DESTINATION_PLATFORMS="${BUILDX_PLATFORMS}"
  substep "Run database seeding script for ${destination_image} from the base image ${BASE_IMAGE} for destination platform(s) ${DESTINATION_PLATFORMS}."
  ./seed.sh "${file}" "${destination_image}" >&3
  assert_file_not_exists .dockerignore.bak

  substep "Start container from the seeded image ${destination_image}."
  # The container runs as a non-root user to imitate limited host permissions.
  cid="$(docker run --user 1000 -d "${destination_image}" 2>&3)"

  wait_mysql "${cid}"

  substep "Assert that data was captured into the new image."
  run docker exec --user 1000 "${cid}" /usr/bin/mysql -e "USE drupal; SHOW TABLES;" drupal
  assert_success
  assert_output_contains "users"

  substep "Assert that the mysql upgrade was skipped by default."
  run docker logs "${cid}"
  assert_success
  assert_output_not_contains "starting mysql upgrade"

  step "Assert mysql upgrade works in container started from already seeded image."

  substep "Start container from the seeded image ${destination_image} and request an upgrade."
  # The container runs as a non-root user to imitate limited host permissions.
  cid="$(docker run --user 1000 -d -e MARIADB_FORCE_UPGRADE=1 "${destination_image}" 2>&3)"

  wait_mysql "${cid}"

  substep "Assert that the mysql upgrade was performed."
  run docker logs "${cid}"
  assert_success
  assert_output_contains "starting mysql upgrade"

  substep "Assert that data is present in the new image after the upgrade."
  run docker exec --user 1000 "${cid}" /usr/bin/mysql -e "USE drupal; SHOW TABLES;" drupal
  assert_success
  assert_output_contains "users"
}

@test "Seeding sanitizes the data when SANITIZE_PROCEED is 1" {
  tag="${TEST_DOCKER_TAG}"
  export BASE_IMAGE="drevops/mariadb-drupal-data-test:${tag}-base"
  destination_image="drevops/mariadb-drupal-data-test:${tag}-destination"

  step "Prepare base image."

  substep "Copy fixture database dump and sanitization file to the default SANITIZE_FILE location."
  file="${BUILD_DIR}/db.sql"
  cp "${BATS_TEST_DIRNAME}/fixtures/db.sql" "${file}"
  mkdir -p scripts
  cp "${BATS_TEST_DIRNAME}/fixtures/sanitize.sql" scripts/sanitize.sql

  substep "Build and push a fresh base image tagged with ${BASE_IMAGE}."
  docker buildx build --platform "${BUILDX_PLATFORMS}" --load --push --no-cache -t "${BASE_IMAGE}" .

  export DESTINATION_PLATFORMS="${BUILDX_PLATFORMS}"
  export SANITIZE_PROCEED=1

  step "Assert seeding stops before building the image when a sanitization query fails."

  echo "UPDATE missing_table SET mail = NULL;" >"${BUILD_DIR}/broken.sql"
  run env SANITIZE_FILE="${BUILD_DIR}/broken.sql" ./seed.sh "${file}" "${destination_image}"
  assert_failure
  assert_output_contains "Unable to sanitize database with queries from the ${BUILD_DIR}/broken.sql file."
  assert_output_not_contains "Stage 2: Build image"

  substep "Assert that the container holding the unsanitized database was removed."
  run docker ps --all --quiet --filter "ancestor=${BASE_IMAGE}"
  assert_success
  assert_output ""

  step "Assert seeding stops before building the image when the dump changes database accounts."

  cp "${file}" "${BUILD_DIR}/db-accounts.sql"
  echo "CREATE USER 'extra'@'%' IDENTIFIED BY 'extra';" >>"${BUILD_DIR}/db-accounts.sql"
  run ./seed.sh "${BUILD_DIR}/db-accounts.sql" "${destination_image}"
  assert_failure
  assert_output_contains "The database dump creates or changes database accounts, which the sanitized export does not carry into the image; remove those statements from the dump."
  assert_output_not_contains "Stage 2: Build image"

  step "Assert seeding with sanitization works."

  run ./seed.sh "${file}" "${destination_image}"
  assert_success
  assert_output_contains "Sanitization: enabled; the queries from ./scripts/sanitize.sql run before the database is captured."
  assert_output_contains "Sanitized database with queries from the ./scripts/sanitize.sql file."
  assert_file_not_exists .db-sanitized.sql

  substep "Start container from the seeded image ${destination_image}."
  # The container runs as a non-root user to imitate limited host permissions.
  cid="$(docker run --user 1000 -d "${destination_image}" 2>&3)"

  wait_mysql "${cid}"

  substep "Assert that the personal data was replaced and the 4-byte character survived the export."
  run docker exec --user 1000 "${cid}" /usr/bin/mysql --default-character-set=utf8mb4 -e "SELECT name, mail, init FROM users_field_data WHERE uid = 1;" drupal
  assert_success
  assert_output_contains "user 1 🧹"
  assert_output_contains "user+1@localhost"
  assert_output_not_contains "admin@example.com"

  substep "Assert that the truncated table is empty."
  run docker exec --user 1000 "${cid}" /usr/bin/mysql --skip-column-names -e "SELECT COUNT(*) FROM watchdog;" drupal
  assert_success
  assert_output "0"

  substep "Assert that the export carried over the other database, whose name has a space."
  run docker exec --user 1000 "${cid}" /usr/bin/mysql --skip-column-names -e 'SELECT id FROM `drupal extra`.extra;' drupal
  assert_success
  assert_output "1"

  substep "Assert that no data file in the image holds the original value."
  # The default seeding test finds this value with the same search.
  run docker run --rm --entrypoint grep "${destination_image}" -rl "admin@example.com" /home/db-data
  assert_output ""
  assert_equal "1" "${status}"
}

@test "Seeding restores .dockerignore when it fails before a container starts" {
  # Every Docker call fails, so seeding stops at the base image pull.
  mock_docker="$(mock_command "docker")"
  mock_set_status "${mock_docker}" 1

  cp "${BATS_TEST_DIRNAME}/fixtures/db.sql" "${BUILD_DIR}/db.sql"
  echo ".db-structure" >.dockerignore

  run ./seed.sh "${BUILD_DIR}/db.sql" "myorg/myimage"
  assert_failure
  assert_output_contains "No logs available to display."
  assert_output_contains "Restored .dockerignore from .dockerignore.bak"
  assert_file_exists .dockerignore
  assert_file_not_exists .dockerignore.bak
}

@test "Destination image is resolved from the environment and the argument" {
  # Every Docker call fails, so seeding stops after printing its settings.
  mock_docker="$(mock_command "docker")"
  mock_set_status "${mock_docker}" 1

  cp "${BATS_TEST_DIRNAME}/fixtures/db.sql" "${BUILD_DIR}/db.sql"

  # Columns: DESTINATION_IMAGE, DST_IMAGE, the second argument and the
  # expected output. An empty value leaves that source unset.
  # shellcheck disable=SC2034
  TEST_CASES=(
    "" "" "myorg/argument" "Destination image: myorg/argument:latest"
    "myorg/destination:1.0" "" "" "Destination image: myorg/destination:1.0"
    "" "myorg/alias" "" "Destination image: myorg/alias:latest"
    "" "myorg/alias" "" "DST_IMAGE is deprecated; use DESTINATION_IMAGE instead."
    "myorg/destination" "myorg/alias" "myorg/argument" "Destination image: myorg/destination:latest"
    "" "myorg/alias" "myorg/argument" "Destination image: myorg/alias:latest"
    "" "" "" "Destination Docker image name must be provided as the second argument."
    "destination" "" "" "destination should be in a format myorg/myimage."
  )
  dataprovider_run "seed_with_destination" 4

  substep "Assert that the deprecation notice is not printed without DST_IMAGE."
  run seed_with_destination "myorg/destination" "" ""
  assert_failure
  assert_output_not_contains "DST_IMAGE is deprecated"
}

seed_with_destination() {
  local args=("${BUILD_DIR}/db.sql")

  if [ -n "${3}" ]; then
    args+=("${3}")
  fi

  DESTINATION_IMAGE="${1}" DST_IMAGE="${2}" ./seed.sh "${args[@]}"
}

@test "Sanitization is validated and announced before seeding starts" {
  # Every Docker call fails, so seeding stops after printing its settings.
  mock_docker="$(mock_command "docker")"
  mock_set_status "${mock_docker}" 1

  cp "${BATS_TEST_DIRNAME}/fixtures/db.sql" "${BUILD_DIR}/db.sql"
  cp "${BATS_TEST_DIRNAME}/fixtures/sanitize.sql" "${BUILD_DIR}/sanitize.sql"
  echo "unrelated" >"${BUILD_DIR}/unrelated.sql"

  substep "Assert that a missing sanitization file stops seeding before any Docker call."
  run seed_with_sanitization "1" "${BUILD_DIR}/missing.sql" ""
  assert_failure
  assert_output_contains "Specified sanitization file ${BUILD_DIR}/missing.sql does not exist."
  assert_equal "0" "$(mock_get_call_num "${mock_docker}")"

  # Columns: the SANITIZE_PROCEED, SANITIZE_FILE and TMP_SANITIZED_DB_FILE
  # values and the expected output. An empty value leaves the default.
  # shellcheck disable=SC2034
  TEST_CASES=(
    "" "" "" "Sanitization: disabled; set SANITIZE_PROCEED=1 to sanitize the database before it is captured."
    "0" "${BUILD_DIR}/sanitize.sql" "" "Sanitization: disabled; set SANITIZE_PROCEED=1 to sanitize the database before it is captured."
    "true" "${BUILD_DIR}/sanitize.sql" "" "Sanitization: disabled; set SANITIZE_PROCEED=1 to sanitize the database before it is captured."
    "1" "${BUILD_DIR}/sanitize.sql" "" "Sanitization: enabled; the queries from ${BUILD_DIR}/sanitize.sql run before the database is captured."
    "1" "" "" "Specified sanitization file ./scripts/sanitize.sql does not exist."
    "1" "${BUILD_DIR}/missing.sql" "" "Specified sanitization file ${BUILD_DIR}/missing.sql does not exist."
    "1" "${BUILD_DIR}" "" "Specified sanitization file ${BUILD_DIR} does not exist."
    "0" "${BUILD_DIR}/missing.sql" "" "Sanitization: disabled; set SANITIZE_PROCEED=1 to sanitize the database before it is captured."
    "1" "${BUILD_DIR}/sanitize.sql" "db.sql" "Sanitized database export file db.sql already exists; remove it or set TMP_SANITIZED_DB_FILE to another path."
    "1" "${BUILD_DIR}/sanitize.sql" "${BUILD_DIR}/sanitize.sql" "Sanitized database export file ${BUILD_DIR}/sanitize.sql already exists; remove it or set TMP_SANITIZED_DB_FILE to another path."
    "1" "${BUILD_DIR}/sanitize.sql" "${BUILD_DIR}/unrelated.sql" "Sanitized database export file ${BUILD_DIR}/unrelated.sql already exists; remove it or set TMP_SANITIZED_DB_FILE to another path."
    "0" "${BUILD_DIR}/sanitize.sql" "${BUILD_DIR}/unrelated.sql" "Sanitization: disabled; set SANITIZE_PROCEED=1 to sanitize the database before it is captured."
  )
  dataprovider_run "seed_with_sanitization" 4

  substep "Assert that existing files at the export path were kept."
  assert_file_exists "${BUILD_DIR}/db.sql"
  assert_file_exists "${BUILD_DIR}/sanitize.sql"
  assert_file_contains "${BUILD_DIR}/unrelated.sql" "unrelated"
}

seed_with_sanitization() {
  SANITIZE_PROCEED="${1}" SANITIZE_FILE="${2}" TMP_SANITIZED_DB_FILE="${3}" ./seed.sh "${BUILD_DIR}/db.sql" "myorg/myimage"
}

@test "Seeding removes the sanitized export and the running container when it fails" {
  mock_docker="$(mock_command "docker")"
  # The output passes the system tables and import checks.
  mock_set_output "${mock_docker}" "user_variables users"
  # The dump call records the mode of the export it writes to. The call that
  # matches TEST_FAILING_CALL fails once the export exists.
  mock_set_side_effect "${mock_docker}" - <<'EOF'
if [[ "$*" == *mysqldump* ]]; then ls -l .db-sanitized.sql >export-mode.txt; fi
if [[ "$*" == *"${TEST_FAILING_CALL}"* ]] && [ -f .db-sanitized.sql ]; then exit 1; fi
EOF

  cp "${BATS_TEST_DIRNAME}/fixtures/db.sql" "${BUILD_DIR}/db.sql"
  cp "${BATS_TEST_DIRNAME}/fixtures/sanitize.sql" "${BUILD_DIR}/sanitize.sql"

  # Columns: the failing Docker call and the expected outcome.
  # shellcheck disable=SC2034
  TEST_CASES=(
    "mysqldump" "failure=export export=absent mode=owner-only container=removed"
    "until nc" "failure=service export=absent mode=owner-only container=removed"
  )
  dataprovider_run "seed_failing_at" 2
}

# Runs seeding with sanitization while the Docker call matching the argument
# fails, then prints which step failed and what the cleanup left behind.
seed_failing_at() {
  rm -f export-mode.txt

  local seed_output
  seed_output="$(SANITIZE_PROCEED=1 SANITIZE_FILE="${BUILD_DIR}/sanitize.sql" TEST_FAILING_CALL="${1}" ./seed.sh "${BUILD_DIR}/db.sql" "myorg/myimage" 2>&1)"

  local failure="none"
  if [[ ${seed_output} == *"Unable to export sanitized database to the .db-sanitized.sql file."* ]]; then
    failure="export"
  elif [[ ${seed_output} == *"MySQL service did not start successfully."* ]]; then
    failure="service"
  fi

  local export_state="absent"
  if [ -e .db-sanitized.sql ]; then
    export_state="present"
  fi

  local mode="unknown"
  if grep -q -- "^-rw-------" export-mode.txt 2>/dev/null; then
    mode="owner-only"
  fi

  local container="kept"
  if [[ "$(mock_get_call_args "${mock_docker}")" == "rm -f -v "* ]]; then
    container="removed"
  fi

  echo "failure=${failure} export=${export_state} mode=${mode} container=${container}"
}
