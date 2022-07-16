#!/usr/bin/env bats
#
# Test functionality.
#
# bats --tap tests/bats/data.bats
#
# In some cases, a shell may report platform incorrectly. Run with forced platform:
# DOCKER_DEFAULT_PLATFORM=linux/amd64 bats --tap tests/bats/data.bats
#

load _helper

setup(){
  CUR_DIR="$(pwd)"
  export CUR_DIR
  export BUILD_DIR="${BUILD_DIR:-"${BATS_TEST_TMPDIR}/drevops-maria-drupal-data$(random_string)"}"

  export TEST_DOCKER_TAG_PREFIX="bats-test-"

  prepare_fixture_dir "${BUILD_DIR}"
  copy_code "${BUILD_DIR}"

  if [ "$(uname -m)" = "arm64" ]; then
    export DOCKER_DEFAULT_PLATFORM=linux/amd64
  fi

  if [ -n "${DOCKER_DEFAULT_PLATFORM}" ]; then
    step "Using ${DOCKER_DEFAULT_PLATFORM} platform architecture."
  fi

  # Force full debug output in scritps.
  export DREVOPS_DEBUG=1

  pushd "${BUILD_DIR}" > /dev/null || exit 1
}

teardown(){
  # Stop and remove all test containers.
  docker ps --all  --format "{{.ID}}\t{{.Image}}" | grep "${TEST_DOCKER_TAG_PREFIX}" | awk '{print $1}' | xargs docker rm -f -v

  # Remove all test images.
  docker images -a | grep "${TEST_DOCKER_TAG_PREFIX}" | awk '{print $3}' | xargs docker rmi -f || true

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
  user=1000
  tag="${TEST_DOCKER_TAG_PREFIX}$(random_string_lower)"

  step "Build default image tagged with $tag."
  docker build -t "${tag}" .

  step "Starting new detached container from the built image."
  run docker run --user ${user} -d "${tag}"
  assert_success
  cid="${output}"
  substep "Started container ${cid}"

  step "Assert that the database directory is present."
  docker exec --user ${user} "${cid}" test -d /var/lib/db-data

  step "Wait for mysql to start."
  sleep 5

  step "Assert that the database is present after start."
  run docker exec --user ${user} "${cid}" mysql -e "SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'drupal';"
  assert_success
  assert_contains "drupal" "${output}"

  step "Assert that the table is not present after start."
  run docker exec --user ${user} "${cid}" mysql -e "USE 'drupal'; show tables like 'mytesttable';"
  assert_success
  assert_not_contains "mytesttable" "${output}"

  step "Create a table in the database."
  docker exec --user ${user} "${cid}" mysql -e "USE 'drupal'; CREATE TABLE mytesttable(c CHAR(20) CHARACTER SET utf8 COLLATE utf8_bin);"

  step "Assert that the table is present after creation."
  run docker exec --user ${user} "${cid}" mysql -e "USE 'drupal'; show tables like 'mytesttable';"
  assert_success
  assert_contains "mytesttable" "${output}"

  step "Commit an image from the last container and get the image ID."
  run docker commit "${cid}"
  assert_success
  committed_image_id="${output}"
  substep "Created new committed image ${committed_image_id}."

  step "Create a new tag for committed image."
  new_tag="${tag}-latest"
  docker tag "${committed_image_id}" "${new_tag}"
  substep "Tagged committed image ${committed_image_id} with a tag ${new_tag}."

  step "Start new container from the committed image."
  run docker run --user ${user} -d "${new_tag}"
  assert_success
  new_cid="${output}"
  substep "Started new container ${new_cid}"

  step "Wait for mysql to start."
  sleep 5

  step "Assert that the database is present after restart."
  run docker exec --user ${user} "${new_cid}" mysql -e "SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'drupal';"
  assert_success
  assert_contains "drupal" "${output}"

  step "Assert that the table is present after restart."
  run docker exec --user ${user} "${new_cid}" mysql -e "USE 'drupal'; show tables like 'mytesttable';"
  assert_success
  assert_contains "mytesttable" "${output}"
}

@test "Seeding of the image works" {
  tag="${TEST_DOCKER_TAG_PREFIX}$(random_string_lower)"

  step "Build fresh image tagged with $tag."
  docker build --no-cache -t "${tag}" .

  step "Download fixture DB dump."
  file="${BUILD_DIR}/db.sql"
  CURL_DB_URL=https://raw.githubusercontent.com/wiki/drevops/drevops/db_d9.dist.sql.md
  curl -L "${CURL_DB_URL}" -o "${file}"

  export BASE_IMAGE="${tag}"
  export RUN_USER="1000"
  step "Run DB seeding script from base image tagged with ${BASE_IMAGE}"
  run ./seed-db.sh "${file}" testorgdst/tesimagedst:latest
  assert_success
  debug "${output}"

  step "Start container from the seeded image."
  # Start container with a non-root user to imitate limited host permissions.
  cid=$(docker run --user 1000 -d --rm "testorgdst/tesimagedst:latest")
  substep "Waiting for the service to become ready."
  docker exec -i "${cid}" sh -c "until nc -z localhost 3306; do sleep 1; echo -n .; done; echo"

  step "Assert that data was captured into the new image."
  run docker exec "${cid}" /usr/bin/mysql -e "use drupal;show tables;" drupal
  assert_output_contains "users"
}
