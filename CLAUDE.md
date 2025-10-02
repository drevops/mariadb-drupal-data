# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This project provides a MariaDB Docker image for Drupal that captures database data as Docker layers. Unlike traditional MariaDB containers that use volumes, this image stores database files in a non-volume location (`/home/db-data`) allowing the entire database to be captured, stored, and distributed as a Docker image.

**Key Innovation**: Database files are stored as Docker layers rather than volumes, enabling instant database availability without time-consuming imports.

## Architecture

### Core Components

1. **Dockerfile** - Extends `uselagoon/mariadb-10.11-drupal` base image:
   - Sets custom data directory via `MARIADB_DATA_DIR=/home/db-data` (not a volume)
   - Replaces entrypoint script to support custom data directory
   - Overrides CMD to use `--datadir=/home/db-data`

2. **entrypoint.bash** - Modified from [upstream](https://github.com/uselagoon/lagoon-images/blob/main/images/mariadb/entrypoints/9999-mariadb-init.bash):
   - Supports `MARIADB_DATA_DIR` environment variable
   - Handles database initialization in custom location
   - Supports `MARIADB_COPY_DATA_DIR_SOURCE` for pre-filling data
   - Includes `FORCE_MYSQL_UPGRADE` flag for forcing upgrades

3. **seed.sh** - Three-phase database seeding script:
   - **Phase 1**: Import SQL dump into temporary container and extract database files
   - **Phase 2**: Build new image with extracted database files using `docker buildx`
   - **Phase 3**: Verify database exists in the new image
   - Supports multi-platform builds (linux/amd64, linux/arm64)
   - Uses `docker buildx` to push directly to registry during build

### Important Patterns

- Database files must be in `/home/db-data` (not `/var/lib/mysql`)
- Upstream base image version follows [uselagoon/mariadb-drupal tags](https://hub.docker.com/r/uselagoon/mariadb-drupal/tags)
- The entrypoint script is minimally modified for easy upstream updates
- Containers typically run as user `1000` (not `mysql`) in production

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

Run Goss tests (structural tests):
```bash
docker build -t testorg/testimage:test-tag .
GOSS_FILES_PATH=tests/dgoss dgoss run -i testorg/testimage:test-tag
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

Seed image with database (single platform):
```bash
./seed.sh path/to/db.sql myorg/myimage:latest
```

Seed image with database (multi-platform):
```bash
DESTINATION_PLATFORMS=linux/amd64,linux/arm64 ./seed.sh path/to/db.sql myorg/myimage:latest
```

Use custom base image:
```bash
BASE_IMAGE=drevops/mariadb-drupal-data:canary ./seed.sh path/to/db.sql myorg/myimage:latest
```

### Platform-specific Testing

Test for ARM64:
```bash
BUILDX_PLATFORMS=linux/arm64 DOCKER_DEFAULT_PLATFORM=linux/arm64 tests/bats/node_modules/.bin/bats tests/bats/image.bats
```

## CI/CD

- Uses CircleCI with `drevops/ci-runner:25.9.0` image
- Publishes to DockerHub:
  - `main` branch → `canary` tag
  - Git tags → versioned tag + `latest`
  - Feature branches → `feature-branch-name` tag (but renovate branches are skipped)
- Multi-platform builds: `linux/amd64,linux/arm64`
- Code coverage uploaded to Codecov via kcov

## Important Notes

- Always test changes by committing first (BATS tests copy code from last commit)
- The entrypoint script should remain minimally modified for easy upstream syncing
- When updating base image version, follow upstream versioning
- seed.sh requires being logged into Docker registry (it pushes during buildx)
- Tests always run for linux/amd64 unless explicitly configured otherwise
