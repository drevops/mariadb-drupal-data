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

  # Due to a limitation in buildx, we are building for a single platform for these tests.
  export BUILDX_PLATFORMS="${DOCKER_DEFAULT_PLATFORM:-linux/amd64}"
  export DOCKER_BUILDKIT=1

  # Force full debug output in scripts.
  export DREVOPS_DEBUG=1

  pushd "${BUILD_DIR}" > /dev/null || exit 1
}

teardown(){
  # Stop and remove all test containers.
  docker ps --all  --format "{{.ID}}\t{{.Image}}" | grep testorg | awk '{print $1}' | xargs docker rm -f -v

  # Remove all test images.
  docker images -a | grep "testorg" | awk '{print $3}' | xargs docker rmi -f || true

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
  # Copy the latest commit to the build directory.
  git archive --format=tar HEAD | (cd "${dst}" && tar -xf -)
  popd > /dev/null || exit 1
}

@test "Data added to the image is captured and preserved" {
  user=1000

  tag="${TEST_DOCKER_TAG_PREFIX}$(random_string_lower)"
  image="testorg/tesimagebase:${tag}"

  step "Build default image ${image}."
  docker buildx build --platform "${BUILDX_PLATFORMS}" --load -t "${image}" .

  step "Starting new detached container from the built image."
  run docker run --user ${user} -d "${image}" 2>/dev/null
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
  new_image="${image}-latest"
  docker tag "${committed_image_id}" "${new_image}"
  substep "Tagged committed image ${committed_image_id} as ${new_image}."

  step "Start new container from the tagged committed image ${new_image}."
  run docker run --user ${user} -d "${new_image}"
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
  export BASE_IMAGE="testorg/tesimagebase:${tag}"

  step "Build fresh image tagged with $tag."
  docker buildx build --platform "${BUILDX_PLATFORMS}" --load --no-cache -t "${BASE_IMAGE}" .

  step "Download fixture DB dump."
  file="${BUILD_DIR}/db.sql"
  CURL_DB_URL=https://raw.githubusercontent.com/wiki/drevops/drevops/db.demo.sql.md
  curl -L "${CURL_DB_URL}" -o "${file}"

  export RUN_USER="1000"
  step "Run DB seeding script from base image ${BASE_IMAGE}"
  run ./seed-db.sh "${file}" testorg/tesimagedst:latest
  assert_success
  debug "${output}"

  step "Start container from the seeded image."
  # Start container with a non-root user to imitate limited host permissions.
  cid=$(docker run --user 1000 -d --rm "testorg/tesimagedst:latest")
  substep "Waiting for the service to become ready."
  docker exec -i "${cid}" sh -c "until nc -z localhost 3306; do sleep 1; echo -n .; done; echo"

  step "Assert that data was captured into the new image."
  run docker exec "${cid}" /usr/bin/mysql -e "use drupal;show tables;" drupal
  assert_output_contains "users"
}
