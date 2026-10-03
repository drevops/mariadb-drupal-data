# AGENTS.md

This file provides guidance to AI agents when working with code in this repository.

## Project Overview

This project provides a MariaDB Docker image for Drupal that captures database data as Docker layers. Unlike traditional MariaDB containers that use volumes, this image stores database files in a non-volume location (`/home/db-data`) allowing the entire database to be captured, stored, and distributed as a Docker image.

**Key Innovation**: Database files are stored as Docker layers rather than volumes, enabling instant database availability without time-consuming imports.

## Architecture

### Core Components

1. **Dockerfile** - Extends `uselagoon/mariadb-10.11-drupal` base image:
   - Sets custom data directory via `MARIADB_DATA_DIR=/home/db-data` (not a volume)
   - Replaces entrypoint script to support custom data directory
   - Overrides CMD to use `--datadir=/home/db-data`

2. **entrypoint.bash** - Modified from [upstream](https://github.com/uselagoon/lagoon-images/blob/main/images/mariadb/entrypoints/9999-mariadb-init.10.bash):
   - Supports `MARIADB_DATA_DIR` environment variable
   - Handles database initialization in custom location
   - Supports `MARIADB_COPY_DATA_DIR_SOURCE` for pre-filling data
   - Includes `MARIADB_FORCE_UPGRADE` flag for forcing upgrades, with `FORCE_MYSQL_UPGRADE` as a deprecated alias

3. **seed.sh** - 3-stage database seeding script:
   - **Stage 1**: Import SQL dump into temporary container and extract database files
   - **Stage 2**: Build new image with extracted database files using `docker buildx`
   - **Stage 3**: Verify database exists in the new image
   - Takes the destination image from `DESTINATION_IMAGE`, then the deprecated `DST_IMAGE` alias, then the second argument
   - When `SANITIZE_PROCEED` is `1` (default `0`; `true` leaves it off), runs the SQL queries from `SANITIZE_FILE` (default `./scripts/sanitize.sql`) in a separate container and imports that container's export into the captured one; a failing query stops seeding before Stage 2
   - Builds images for the host platform by default; multi-platform builds (linux/amd64, linux/arm64) are opt-in via `DESTINATION_PLATFORMS`
   - Uses `docker buildx` to push directly to registry during build

### Important Patterns

- Database files must be in `/home/db-data` (not `/var/lib/mysql`)
- Upstream base image version follows [uselagoon/mariadb-10.11-drupal tags](https://hub.docker.com/r/uselagoon/mariadb-10.11-drupal/tags)
- The entrypoint script is minimally modified for easy upstream updates
- Containers typically run as user `1000` (not `mysql`) in production
- Sanitization must not run in the captured container: InnoDB's redo log keeps the replaced values, and the redo log is captured with the data files

## Development Commands

### Testing

Run all BATS tests:

```bash
npm --prefix tests/bats ci
tests/bats/node_modules/.bin/bats tests/bats
```

Run specific BATS test file:

```bash
tests/bats/node_modules/.bin/bats tests/bats/image.bats --tap
tests/bats/node_modules/.bin/bats tests/bats/seed.bats --tap
```

BATS test conventions:

- Tests in `tests/bats/` with `.bats` extension
- Helper functions in `tests/bats/_helper.bash`
- Coverage exclusions: `# LCOV_EXCL_START` / `# LCOV_EXCL_STOP` (the region markers kcov recognizes)

Run Goss tests (structural tests):

```bash
docker build -t gosstestorg/gosstestimage:goss-test-tag .
GOSS_FILES_PATH=tests/dgoss dgoss run -i gosstestorg/gosstestimage:goss-test-tag
```

### Linting

Lint shell scripts:

```bash
shfmt -i 2 -ci -s -d seed.sh tests/bats/*.bash tests/bats/*.bats
shellcheck seed.sh tests/bats/*.bash tests/bats/*.bats
```

### Building and Seeding

Build image locally:

```bash
docker build -t drevops/mariadb-drupal-data:local .
```

Seed image with database (host platform by default):

```bash
./seed.sh path/to/db.sql myorg/myimage:latest
```

Seed image with database (multi-platform):

```bash
DESTINATION_PLATFORMS=linux/amd64,linux/arm64 ./seed.sh path/to/db.sql myorg/myimage:latest
```

Seed image with a sanitized database:

```bash
SANITIZE_PROCEED=1 SANITIZE_FILE=path/to/sanitize.sql ./seed.sh path/to/db.sql myorg/myimage:latest
```

Use custom base image:

```bash
BASE_IMAGE=drevops/mariadb-drupal-data:canary ./seed.sh path/to/db.sql myorg/myimage:latest
```

### Platform-specific Testing

Tests run for the host platform by default. To force a specific platform, set `DOCKER_DEFAULT_PLATFORM` (the tests derive `BUILDX_PLATFORMS` from it); forcing a foreign platform requires emulation, under which MariaDB does not start reliably:

```bash
DOCKER_DEFAULT_PLATFORM=linux/arm64 tests/bats/node_modules/.bin/bats tests/bats/image.bats
```

## CI/CD

### Workflows

**test.yml** - Runs on PRs and pushes to main:
- Runs the test job on a matrix: native amd64 (`ubuntu-latest`), native arm64 (`ubuntu-24.04-arm`), and amd64 inside the `drevops/ci-runner` container (the "custom runner" job)
- Lints shell scripts with `shfmt` and `shellcheck` (custom runner job only)
- Runs Goss structural tests
- Runs BATS tests with code coverage (kcov; coverage collected on the custom runner job only)
- Uploads coverage to Codecov
- Pushes `canary` tag to DockerHub on main branch

**release-docker.yml** - Runs on Git tags:
- Builds and pushes versioned + `latest` tags to DockerHub
- Uploads `seed.sh` as a release asset

**draft-release-notes.yml** - Runs on pushes to main and on Git tags:
- Drafts release notes using release-drafter with CalVer version when the `RELEASE_VERSION_SCHEME` variable is `calver`

**assign-author.yml** - Runs when a PR is opened or reopened:
- Assigns the PR author to the PR

### Configuration

- Multi-platform builds: `linux/amd64,linux/arm64`
- Required secrets: `DOCKER_USER` (Docker Hub username) and `DOCKER_PASS` (Docker Hub access token)
- Optional secrets: `CODECOV_TOKEN` (the Codecov upload is skipped without it)
- Required vars: `RELEASE_VERSION_SCHEME` set to `calver`
- Optional vars: `CI_LINT_IGNORE_FAILURE`, `CI_TEST_IGNORE_FAILURE` (set to '1' to ignore failures), `DOCKER_IMAGE` (published image name for releases and canary, defaults to `drevops/mariadb-drupal-data`)

## Important Notes

- Always test changes by committing first (BATS tests copy code from last commit)
- The entrypoint script should remain minimally modified for easy upstream syncing
- When updating base image version, follow upstream versioning
- seed.sh requires being logged into Docker registry (it pushes during buildx)
- Tests run for the host platform unless explicitly configured otherwise
- Renovate's `github-actions` manager doesn't read workflow matrix values, so a custom regex manager in `renovate.json` tracks the `drevops/ci-runner` image in the `test.yml` matrix; it only matches the `container: <image>:<tag>@<digest>` form, so keep that form when editing the matrix

## Updating from the template

This project was generated from a template and can pull the template's latest
infrastructure (CI workflows, linting and test configuration, Docker, and docs)
at any time. When you are asked to "update scaffold", fetch the updater skill
from the template repository into the local `.claude/skills/` directory, then
invoke it:

1. Create the target directory if it does not exist:

   ```bash
   mkdir -p .claude/skills/update-consumer-scaffold
   ```

2. Download the skill:

   ```bash
   curl -sSL https://raw.githubusercontent.com/AlexSkrypnyk/scaffold/main/.scaffold/skills/update-consumer-scaffold/SKILL.md -o .claude/skills/update-consumer-scaffold/SKILL.md
   ```

3. Invoke the `update-consumer-scaffold` skill and follow its steps.

The skill directory is fetched on demand and is git-ignored - it is not
committed to the project.
