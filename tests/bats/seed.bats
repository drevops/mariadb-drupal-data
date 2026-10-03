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

  substep "Assert that the mysql upgrade was skipped by default."
  run docker logs "${cid}"
  assert_success
  assert_output_not_contains "starting mysql upgrade"

  step "Assert mysql upgrade works in container started from already seeded image."

  substep "Start container from the seeded image ${destination_image} and request an upgrade."
  # The container runs as a non-root user to imitate limited host permissions.
  cid="$(docker run --user 1000 -d -e FORCE_MYSQL_UPGRADE=1 "${destination_image}" 2>&3)"

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
  cid="$(docker run --user 1000 -d -e FORCE_MYSQL_UPGRADE=1 "${destination_image}" 2>&3)"

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

@test "Destination image is resolved from the environment and the argument" {
  # Every Docker call fails, so seeding stops after printing its settings.
  mock_docker="$(mock_command "docker")"
  mock_set_status "${mock_docker}" 1

  cp "${BATS_TEST_DIRNAME}/fixtures/db.sql" "${BUILD_DIR}/db.sql"

  # Columns: DESTINATION_IMAGE, DST_IMAGE, the second argument and the
  # expected output. An empty value leaves that source unset.
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
