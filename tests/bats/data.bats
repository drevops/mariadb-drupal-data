#!/usr/bin/env bats
#
# Test functionality.
#
# bats --tap tests/bats/data.bats
#
# In some cases, shell may report platform incorrectly. Run with forced platform:
# DOCKER_DEFAULT_PLATFORM=linux/amd64 bats --tap tests/bats/data.bats
#

load _helper

@test "Data is preserved in an image captured from running container" {
  tag="${TEST_DOCKER_TAG_PREFIX}$(random_string_lower)"
  # Using a local image for this test.
  image="testorg/tesimagebase:${tag}"

  step "Build default image ${image} and load into 'docker images'."
  docker buildx build --platform "${BUILDX_PLATFORMS}" --load -t "${image}" .

  step "Starting new detached container from the built image."
  run docker run --user 1000 -d "${image}" 2>/dev/null
  assert_success
  cid="${output}"
  substep "Started container ${cid}"

  step "Assert that the database directory is present."
  docker exec --user 1000 "${cid}" test -d /var/lib/db-data

  step "Wait for mysql to start."
  sleep 5

  step "Assert that the database is present after start."
  run docker exec --user 1000 "${cid}" mysql -e "SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'drupal';"
  assert_success
  assert_contains "drupal" "${output}"

  step "Assert that the table is not present after start."
  run docker exec --user 1000 "${cid}" mysql -e "USE 'drupal'; show tables like 'mytesttable';"
  assert_success
  assert_not_contains "mytesttable" "${output}"

  step "Create a table in the database."
  docker exec --user 1000 "${cid}" mysql -e "USE 'drupal'; CREATE TABLE mytesttable(c CHAR(20) CHARACTER SET utf8 COLLATE utf8_bin);"

  step "Assert that the table is present after creation."
  run docker exec --user 1000 "${cid}" mysql -e "USE 'drupal'; show tables like 'mytesttable';"
  assert_success
  assert_contains "mytesttable" "${output}"

  step "Commit an image from the last container and get the image ID."
  run docker commit "${cid}"
  assert_success
  committed_image_id="${output}"
  substep "Created new committed image ${committed_image_id}."

  step "Create a new tag for committed image."
  new_image="${image}-latest"
  docker tag "${committed_image_id}" "${new_image}"
  substep "Tagged committed image ${committed_image_id} as ${new_image}."

  step "Start new container from the tagged committed image ${new_image}."
  run docker run --user 1000 -d "${new_image}"
  assert_success
  new_cid="${output}"
  substep "Started new container ${new_cid}"

  step "Wait for mysql to start."
  sleep 5

  step "Assert that the database is present after restart."
  run docker exec --user 1000 "${new_cid}" mysql -e "SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'drupal';"
  assert_success
  assert_contains "drupal" "${output}"

  step "Assert that the table is present after restart."
  run docker exec --user 1000 "${new_cid}" mysql -e "USE 'drupal'; show tables like 'mytesttable';"
  assert_success
  assert_contains "mytesttable" "${output}"
}

@test "Seeding of the data works" {
  tag="${TEST_DOCKER_TAG_PREFIX}$(random_string_lower)"
  export BASE_IMAGE="testorg/tesimagebase:${tag}"

  step "Build fresh image tagged with ${BASE_IMAGE}."
  docker buildx build --platform "${BUILDX_PLATFORMS}" --load --no-cache -t "${BASE_IMAGE}" .

  step "Download fixture DB dump."
  file="${BUILD_DIR}/db.sql"
  CURL_DB_URL=https://raw.githubusercontent.com/wiki/drevops/drevops/db.demo.sql.md
  curl -L "${CURL_DB_URL}" -o "${file}"

  step "Run DB seeding script from base image ${BASE_IMAGE}"
  dst_image="drevops/mariadb-drupal-data-test:${tag}"
  run ./seed-db.sh "${file}" "${dst_image}"
  assert_success
}
