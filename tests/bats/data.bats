#!/usr/bin/env bats
#
# Test for clean functionality.
#

load _helper

setup(){
  export CUR_DIR="$(pwd)"
  export BUILD_DIR="${BUILD_DIR:-"${BATS_TEST_TMPDIR}/drevops-maria-drupal-data$(random_string)"}"

  export DOCKER_TAG_PREFIX="bats-test-"

  prepare_fixture_dir "${BUILD_DIR}"
  copy_code "${BUILD_DIR}"

  pushd "${BUILD_DIR}" > /dev/null || exit 1
}

teardown(){
  # Stop and remove all test containers.
  docker ps --all  --format "{{.ID}}\t{{.Image}}" | grep "${DOCKER_TAG_PREFIX}" | awk '{print $1}' | xargs docker rm -f -v

  # Remove all test images.
  docker images -a | grep "${DOCKER_TAG_PREFIX}" | awk '{print $3}' | xargs docker rmi -f

  popd > /dev/null || cd "${CUR_DIR}" || exit 1
}

# Print step.
step(){
  debug ""
  # Using prefix different from command prefix in SUT for easy debug.
  debug "**> STEP: $1"
}

# Print sub-step.
substep(){
  debug ""
  debug "  > $1"
}

# Copy source code at the latest commit to the destination directory.
copy_code(){
  local dst="${1:-${BUILD_DIR}}"
  assert_dir_exists "${dst}"
  assert_git_repo "${CUR_DIR}"
  pushd "${CUR_DIR}" > /dev/null || exit 1
  # Copy latest commit to the build directory.
  git archive --format=tar HEAD | (cd "${dst}" && tar -xf -)
  popd > /dev/null || exit 1
}

@test "Data added to the image is captured and preserved" {
  tag="${DOCKER_TAG_PREFIX}$(random_string_lower)"

  step "Build default image from tag $tag."
  docker build -t "${tag}" .

  step "Starting new detached container from the built image."
  run docker run -d "${tag}"
  assert_success
  cid="${output}"
  substep "Started container ${cid}"

  step "Assert that the database directory is present."
  docker exec "${cid}" test -d /var/lib/db-data

  step "Wait for mysql to start."
  sleep 5

  step "Assert that the database is present."
  run docker exec "${cid}" mysql -e "SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'drupal';"
  assert_success
  assert_contains "drupal" "${output}"

  step "Assert that the table is not present."
  run docker exec "${cid}" mysql -e "USE 'drupal'; show tables like 'mytesttable';"
  assert_success
  assert_not_contains "mytesttable" "${output}"

  step "Create a table in the database."
  docker exec "${cid}" mysql -e "USE 'drupal'; CREATE TABLE mytesttable(c CHAR(20) CHARACTER SET utf8 COLLATE utf8_bin);"

  step "Assert that the table is present."
  run docker exec "${cid}" mysql -e "USE 'drupal'; show tables like 'mytesttable';"
  assert_success
  assert_contains "mytesttable" "${output}"

  step "Commit an image from the last container and get image id."
  run docker commit "${cid}"
  assert_success
  committed_image_id="${output}"
  substep "Created new committed image ${committed_image_id}."

  step "Create a new tag for committed image."
  new_tag="${tag}-latest"
  docker tag "${committed_image_id}" "${new_tag}"
  substep "Tagged committed image ${committed_image_id} with tag ${new_tag}."

  step "Start new container from the committed image."
  run docker run -d "${new_tag}"
  assert_success
  new_cid="${output}"
  substep "Started new container ${new_cid}"

  step "Wait for mysql to start."
  sleep 5

  step "Assert that the database is present."
  run docker exec "${new_cid}" mysql -e "SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'drupal';"
  assert_success
  assert_contains "drupal" "${output}"

  step "Assert that the table is present."
  run docker exec "${new_cid}" mysql -e "USE 'drupal'; show tables like 'mytesttable';"
  assert_success
  assert_contains "mytesttable" "${output}"
}
