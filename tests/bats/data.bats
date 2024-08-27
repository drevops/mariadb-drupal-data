#!/usr/bin/env bats
#
# Test functionality.
#
# tests/bats/node_modules/.bin/bats --tap tests/bats/data.bats
#
# Note that these tests will always run only for the linux/amd64 platform by
# default. To run the tests for other platforms, set the BUILDX_PLATFORMS and
# DOCKER_DEFAULT_PLATFORM environment variables to the desired platform(s). But
# make sure that the platform is supported by the Docker buildx driver.
#
# BUILDX_PLATFORMS=linux/arm64 DOCKER_DEFAULT_PLATFORM=linux/arm64 tests/bats/node_modules/.bin/bats --tap tests/bats/data.bats
#
# Make sure to commit the source code change before running the tests as it
# copies the source code at the last commit to the test directory.

load _helper

@test "Data is preserved in an image captured from the running container" {
  tag="${TEST_DOCKER_TAG_PREFIX}$(random_string_lower)"
  # Using a local image for this test. The image will be loaded into the Docker
  # engine from the buildx cache below.
  base_image="testorg/tesimagebase:${tag}"

  step "Prepare base image."

  substep "Build base image ${base_image} and load into 'docker images'."
  docker buildx build --platform "${BUILDX_PLATFORMS}" --load -t "${base_image}" .

  substep "Starting new detached container from the built base image."
  run docker run --user 1000 -d "${base_image}" 2>/dev/null
  assert_success
  cid="${output}"
  substep "Started container ${cid}"

  substep "Assert that the database directory is present in the base image."
  docker exec --user 1000 "${cid}" test -d /home/db-data

  # The entrypoint script should have created the initial database structure
  # and the 'drupal' database directory, but not the database tables.
  substep "Assert that the database directory is present, but the database directory is empty in the base image."
  docker exec --user 1000 "${cid}" bash -c '[ -d /home/db-data ] && [ -z "$(ls -A /home/db-data/drupal/users*)" ]'

  wait_mysql "${cid}"

  substep "Assert that the database is present in the container."
  run docker exec --user 1000 "${cid}" mysql -e "SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'drupal';"
  assert_success
  assert_contains "drupal" "${output}"

  substep "Assert that the created table is not present in the container."
  run docker exec --user 1000 "${cid}" mysql -e "USE 'drupal'; show tables like 'mytesttable';"
  assert_success
  assert_not_contains "mytesttable" "${output}"

  step "Assert capturing of the data into the image."

  substep "Create a table in the database."
  docker exec --user 1000 "${cid}" mysql -e "USE 'drupal'; CREATE TABLE mytesttable(c CHAR(20) CHARACTER SET utf8 COLLATE utf8_bin);"

  substep "Assert that the table is present after creation."
  run docker exec --user 1000 "${cid}" mysql -e "USE 'drupal'; show tables like 'mytesttable';"
  assert_success
  assert_contains "mytesttable" "${output}"

  substep "Commit an image from the last container and get the image ID."
  run docker commit "${cid}"
  assert_success
  committed_image_id="${output}"
  substep "Created new committed image ${committed_image_id}."

  substep "Create a new tag for committed image."
  new_image="${base_image}-latest"
  docker tag "${committed_image_id}" "${new_image}"
  substep "Tagged committed image ${committed_image_id} as ${new_image}."

  substep "Start a new container from the tagged committed image ${new_image}."
  run docker run --user 1000 -d "${new_image}"
  assert_success
  new_cid="${output}"
  substep "Started new container ${new_cid}"

  wait_mysql "${new_cid}"

  substep "Assert that the database is present after restart."
  run docker exec --user 1000 "${new_cid}" mysql -e "SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'drupal';"
  assert_success
  assert_contains "drupal" "${output}"

  substep "Assert that the table is present after restart."
  run docker exec --user 1000 "${new_cid}" mysql -e "USE 'drupal'; show tables like 'mytesttable';"
  assert_success
  assert_contains "mytesttable" "${output}"
}

@test "Seeding of the data works" {
  tag="${TEST_DOCKER_TAG_PREFIX}$(random_string_lower)"
  export BASE_IMAGE="drevops/mariadb-drupal-data-test:${tag}-base"
  dst_image="drevops/mariadb-drupal-data-test:${tag}-dst"

  step "Prepare base image."

  substep "Copying fixture DB dump."
  file="${BUILD_DIR}/db.sql"
  cp "${BATS_TEST_DIRNAME}/fixtures/db.sql" "${file}"

  substep "Build and push a fresh base image tagged with ${BASE_IMAGE}."
  docker buildx build --platform "${BUILDX_PLATFORMS}" --load --push --no-cache -t "${BASE_IMAGE}" .

  step "Assert seeding without mysql upgrade works."

  # Pass the destination platform to the seeding script.
  # Note that the name for the variable `BUILDX_PLATFORMS` in the test was
  # chosen to be different from the `DESTINATION_PLATFORMS` in the seeding
  # script to separate building images when preparing the test environment
  # from the seeding process.
  export DESTINATION_PLATFORMS="${BUILDX_PLATFORMS}"
  substep "Run DB seeding script for ${dst_image} from the base image ${BASE_IMAGE} for destination platform(s) ${DESTINATION_PLATFORMS}."
  ./seed-db.sh "${file}" "${dst_image}" >&3

  substep "Start container from the seeded image ${dst_image}."
  # Start container with a non-root user to imitate limited host permissions.
  cid=$(docker run --user 1000 -d "${dst_image}" 2>&3)

  wait_mysql "${cid}"

  substep "Assert that data was captured into the new image."
  run docker exec --user 1000 "${cid}" /usr/bin/mysql -e "use drupal;show tables;" drupal
  assert_output_contains "users"

  substep "Assert that the mysql upgrade was skipped by default."
  run docker logs "${cid}"
  assert_output_not_contains "starting mysql upgrade"

  step "Assert mysql upgrade works in container started from already seeded image."

  substep "Start container from the seeded image ${dst_image} and request an upgrade."
  # Start container with a non-root user to imitate limited host permissions.
  cid=$(docker run --user 1000 -d -e FORCE_MYSQL_UPGRADE=1 "${dst_image}")

  wait_mysql "${cid}"

  substep "Assert that the mysql upgrade was performed."
  run docker logs "${cid}"
  assert_output_contains "starting mysql upgrade"

  substep "Assert that data is present in the new image after the upgrade."
  run docker exec --user 1000 "${cid}" /usr/bin/mysql -e "use drupal;show tables;" drupal
  assert_output_contains "users"
}
