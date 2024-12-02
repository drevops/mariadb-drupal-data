#!/usr/bin/env bash
##
# @file
# Bats test helpers.
#
# shellcheck disable=SC2119,SC2120
#!/usr/bin/env bash
#
# Helpers related to common testing functionality.
#
# Run with "--verbose-run" to see debug output.
#

################################################################################
#                       BATS HOOK IMPLEMENTATIONS                              #
################################################################################

setup() {
  # For a list of available variables see:
  # @see https://bats-core.readthedocs.io/en/stable/writing-tests.html#special-variables

  # Register a path to libraries.
  export BATS_LIB_PATH="${BATS_TEST_DIRNAME}/node_modules"

  # Load 'bats-helpers' library.
  bats_load_library bats-helpers

  # Setup command mocking.
  setup_mock

  # Current directory where the test is run from.
  # shellcheck disable=SC2155
  export CUR_DIR="$(pwd)"

  # Directory where the init script will be running on.
  # As a part of test setup, the local copy of Scaffold at the last commit is
  # copied to this location. This means that during development of tests local
  # changes need to be committed.
  export BUILD_DIR="${BUILD_DIR:-"${BATS_TEST_TMPDIR//\/\//\/}/drevops-maria-drupal-data-$(date +%s)"}"
  fixture_prepare_dir "${BUILD_DIR}"

  # Copy code at the last commit.
  export BATS_FIXTURE_EXPORT_CODEBASE_ENABLED=1
  fixture_export_codebase "${BUILD_DIR}" "${CUR_DIR}"

  # Print debug information if "--verbose-run" is passed.
  # LCOV_EXCL_START
  if [ "${BATS_VERBOSE_RUN-}" = "1" ]; then
    echo "BUILD_DIR: ${BUILD_DIR}" >&3
  fi
  # LCOV_EXCL_END

  export DOCKER_DEFAULT_PLATFORM="${DOCKER_DEFAULT_PLATFORM:-linux/amd64}"
  step "Using ${DOCKER_DEFAULT_PLATFORM} platform architecture."

  # Due to a limitation in buildx driver to build multi-platform images in some
  # OSes (like MacOS), we are building for a single platform by default.
  export BUILDX_PLATFORMS="${DOCKER_DEFAULT_PLATFORM:-linux/amd64}"
  step "Building for ${BUILDX_PLATFORMS} platforms."
  export DOCKER_BUILDKIT=1

  export TEST_DOCKER_TAG_PREFIX="bats-test-"

  # Change directory to the current project directory for each test. Tests
  # requiring to operate outside of BUILD_DIR should change directory explicitly
  # within their tests.
  pushd "${BUILD_DIR}" >/dev/null || exit 1
}

teardown() {
  # Stop and remove all test containers.
  docker ps --all --format "{{.ID}}\t{{.Image}}" | grep testorg | awk '{print $1}' | xargs docker rm -f -v

  # Remove all test images.
  docker images -a | grep "testorg" | awk '{print $3}' | xargs docker rmi -f || true

  # Restore the original directory.
  popd >/dev/null || cd "${CUR_DIR}" || exit 1
}

# Print step.
step() {
  debug ""
  # Using prefix different from command prefix in SUT for easy debug.
  debug "**> STEP: $1"
}

# Print sub-step.
substep() {
  debug ""
  debug "  > $1"
}

# Run bats with `--tap` option to debug the output.
debug() {
  echo "${1}" >&3
}

random_string_lower() {
  local len="${1:-8}"
  local ret
  # shellcheck disable=SC2002
  ret=$(cat /dev/urandom | env LC_CTYPE=C tr -dc 'a-z0-9' | fold -w "${len}" | head -n 1)
  echo "${ret}"
}
