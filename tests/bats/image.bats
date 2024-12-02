#!/usr/bin/env bats
#
# Test functionality.
#
# tests/bats/node_modules/.bin/bats --tap tests/bats/image.bats
#
# Note that these tests will always run only for the linux/amd64 platform by
# default. To run the tests for other platforms, set the BUILDX_PLATFORMS and
# DOCKER_DEFAULT_PLATFORM environment variables to the desired platform(s). But
# make sure that the platform is supported by the Docker buildx driver.
#
# BUILDX_PLATFORMS=linux/arm64 DOCKER_DEFAULT_PLATFORM=linux/arm64 tests/bats/node_modules/.bin/bats --tap tests/bats/image.bats
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
