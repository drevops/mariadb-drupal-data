#!/usr/bin/env bash
##
# @file
# Bats test helpers.
#
# shellcheck disable=SC2119,SC2120
#
# Run with "--verbose-run" to see debug output.
#

################################################################################
#                       BATS HOOK IMPLEMENTATIONS                              #
################################################################################

setup() {
  # For a list of available variables see:
  # @see https://bats-core.readthedocs.io/en/stable/writing-tests.html#special-variables

  export BATS_LIB_PATH="${BATS_TEST_DIRNAME}/node_modules"

  bats_load_library bats-helpers

  setup_mock

  CUR_DIR="$(pwd)"
  export CUR_DIR

  # Directory where the init script will be running on.
  # As a part of test setup, the local copy of Scaffold at the last commit is
  # copied to this location. This means that during development of tests local
  # changes need to be committed.
  export BUILD_DIR="${BUILD_DIR:-"${BATS_TEST_TMPDIR//\/\//\/}/drevops-mariadb-drupal-data-$(date +%s)"}"
  fixture_prepare_dir "${BUILD_DIR}"

  # Copy code at the last commit.
  export BATS_FIXTURE_EXPORT_CODEBASE_ENABLED=1
  fixture_export_codebase "${BUILD_DIR}" "${CUR_DIR}"

  # LCOV_EXCL_START
  if [ "${BATS_VERBOSE_RUN-}" = "1" ]; then
    debug "BUILD_DIR: ${BUILD_DIR}"
  fi
  # LCOV_EXCL_END

  DOCKER_DEFAULT_PLATFORM="${DOCKER_DEFAULT_PLATFORM:-$(host_platform)}"
  export DOCKER_DEFAULT_PLATFORM
  step "Using ${DOCKER_DEFAULT_PLATFORM} platform architecture."

  # The buildx driver cannot build multi-platform images on some OSes (like
  # macOS), so the default is a single platform.
  export BUILDX_PLATFORMS="${DOCKER_DEFAULT_PLATFORM}"
  step "Building for ${BUILDX_PLATFORMS} platforms."
  export DOCKER_BUILDKIT=1

  export TEST_DOCKER_TAG_PREFIX="bats-test-"

  # A test that must operate outside BUILD_DIR changes directory explicitly.
  pushd "${BUILD_DIR}" >/dev/null || exit 1
}

teardown() {
  docker ps --all --format "{{.ID}}\t{{.Image}}" | grep "${TEST_DOCKER_TAG_PREFIX}" | awk '{print $1}' | xargs docker rm -f -v || true

  docker images --format "{{.Repository}}:{{.Tag}}" | grep "${TEST_DOCKER_TAG_PREFIX}" | xargs docker rmi -f || true

  popd >/dev/null || cd "${CUR_DIR}" || exit 1
}

step() {
  debug ""
  # The prefix differs from the command prefix in the SUT to ease debugging.
  debug "**> STEP: ${1}"
}

substep() {
  debug ""
  debug "  > ${1}"
}

# Run bats with `--tap` option to debug the output.
debug() {
  echo "${1}" >&3
}

random_string_lower() {
  local len="${1:-8}"
  local ret=""

  # Each chunk is bounded so the pipeline terminates on EOF. An unbounded
  # stream stops only on SIGPIPE, and hangs forever where SIGPIPE is ignored.
  while [ "${#ret}" -lt "${len}" ]; do
    ret="${ret}$(head -c 1024 /dev/urandom | env LC_ALL=C tr -dc 'a-z0-9')"
  done

  echo "${ret:0:len}"
}

wait_mysql() {
  local cid="${1?Missing container ID}"
  substep "Wait for mysql to start in container ${cid}."
  if ! docker exec --user 1000 -i "${cid}" sh -c "until nc -z localhost 3306; do sleep 1; echo -n .; done; echo" >&3; then
    docker logs "${cid}"
    exit 1
  fi
}

host_platform() {
  case "$(uname -m)" in
    x86_64) echo "linux/amd64" ;;
    arm64 | aarch64) echo "linux/arm64" ;;
    *) echo "linux/$(uname -m)" ;;
  esac
}
