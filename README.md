<p align="center">
  <a href="" rel="noopener">
  <img width=200px height=200px src="https://placehold.jp/000000/ffffff/200x200.png?text=MariaDB+Drupal+Data&css=%7B%22border-radius%22%3A%22%20100px%22%7D" alt="Mariadb Drupal data logo"></a>
</p>

<h1 align="center">MariaDB data container for Drupal with database captured as Docker layers.</h1>

<div align="center">

[![GitHub Issues](https://img.shields.io/github/issues/drevops/mariadb-drupal-data.svg)](https://github.com/drevops/mariadb-drupal-data/issues)
[![GitHub Pull Requests](https://img.shields.io/github/issues-pr/drevops/mariadb-drupal-data.svg)](https://github.com/drevops/mariadb-drupal-data/pulls)
[![Test](https://github.com/drevops/mariadb-drupal-data/actions/workflows/test.yml/badge.svg)](https://github.com/drevops/mariadb-drupal-data/actions/workflows/test.yml)
[![codecov](https://codecov.io/gh/drevops/mariadb-drupal-data/graph/badge.svg?token=JYSIXUF6QX)](https://codecov.io/gh/drevops/mariadb-drupal-data)
![GitHub release (latest by date)](https://img.shields.io/github/v/release/drevops/mariadb-drupal-data)
![LICENSE](https://img.shields.io/github/license/drevops/mariadb-drupal-data)
![Renovate](https://img.shields.io/badge/renovate-enabled-green?logo=renovatebot)

[![Docker Pulls](https://img.shields.io/docker/pulls/drevops/mariadb-drupal-data?logo=docker)](https://hub.docker.com/r/drevops/mariadb-drupal-data)
![amd64](https://img.shields.io/badge/arch-linux%2Famd64-brightgreen)
![arm64](https://img.shields.io/badge/arch-linux%2Farm64-brightgreen)

[![Vortex Ecosystem](https://img.shields.io/badge/%F0%9F%8C%80-Vortex%20Ecosystem-2C5A68?style=for-the-badge&labelColor=65ACBC)](https://github.com/drevops/vortex)
</div>

## How it works

Usually, MariaDB uses data directory specified as a Docker volume that is
mounted onto host: this allows retaining data after container restarts.

The MariaDB image in this project uses custom location `/home/db-data` (not
a Docker volume) to store expanded database files. These files then can be
captured as a Docker layer and stored as an image to docker registry.

Image consumers download the image and start containers with instantaneously
available data (no time-consuming database imports required).

Technically, the majority of the functionality is relying on upstream [`uselagoon/mariadb-10.11-drupal`](https://github.com/uselagoon/lagoon-images/blob/main/images/mariadb-drupal/10.11.Dockerfile) Docker image.
[Entrypoint script](entrypoint.bash) had to be copied from [upstream script](https://github.com/uselagoon/lagoon-images/blob/main/images/mariadb/entrypoints/9999-mariadb-init.10.bash) and adjusted to support custom data directory.

## Use case

Drupal website with a large database.

1. CI process builds a website overnight.
2. CI process captures the latest database as a new Docker layer in the database image.
3. CI process tags and pushes image to the Docker registry.
4. Website developers pull the latest image from the registry and build site locally.
   OR
   Subsequent CI builds pull the latest image from the registry and build site.

When required, website developers restart docker stack locally with an already
imported database, which saves a significant amount of time for database
imports.

## Seeding image with your database

1. Download the `seed.sh` script from this repository:

```shell
curl -LO https://github.com/drevops/mariadb-drupal-data/releases/latest/download/seed.sh
chmod +x seed.sh
```
2. Run the script with the path to your database dump and the image name:

```shell
./seed.sh path/to/db.sql myorg/myimage:latest

# with the destination image from the environment
DESTINATION_IMAGE=myorg/myimage:latest ./seed.sh path/to/db.sql

# with database sanitization
SANITIZE_FILE=path/to/sanitize.sql ./seed.sh path/to/db.sql myorg/myimage:latest

# with forced source platform
DOCKER_DEFAULT_PLATFORM=linux/amd64 ./seed.sh path/to/db.sql myorg/myimage:latest

# for multi-platform image
DESTINATION_PLATFORMS=linux/amd64,linux/arm64 ./seed.sh path/to/db.sql myorg/myimage:latest

# with a custom base image (e.g., canary)
BASE_IMAGE=drevops/mariadb-drupal-data:canary ./seed.sh path/to/db.sql myorg/myimage:latest
```

By default, the script builds an image for the host platform (`linux/amd64` on Intel hosts, `linux/arm64` on Apple Silicon), so importing, building, and the final test stage all run natively on the machine that invokes it. Multi-platform builds are opt-in via `DESTINATION_PLATFORMS` and require a Docker buildx builder that supports them (Docker Desktop with the containerd image store, or a `docker-container` builder).

You can also set the destination image in `DESTINATION_IMAGE`, which takes precedence over the second argument. `DST_IMAGE` is a deprecated alias for it: the script accepts it with lower precedence than `DESTINATION_IMAGE` and prints a deprecation notice when it's set.

Note that you should already be logged in to the registry as `seed.sh` will be pushing an image as a part of `docker buildx` process.

## Sanitizing the database

Set `SANITIZE_FILE` to a file of SQL queries, and `seed.sh` runs them against the imported database before it captures the database into the image. It's the place to replace personal data and to empty the tables developers don't need, like logs, sessions and caches:

```shell
SANITIZE_FILE=path/to/sanitize.sql ./seed.sh path/to/db.sql myorg/myimage:latest
```

Sanitization is opt-in: without `SANITIZE_FILE`, the image holds the database exactly as it was in the dump. The script prints which of the 2 it's doing before any work starts, so the CI log always shows what kind of image it pushed:

```text
Sanitization: enabled; the queries from path/to/sanitize.sql run before the database is captured.
```

The queries run with the `mysql` client against the database the dump was imported into, so table names don't need a database prefix. The client uses `utf8mb4`, so text with emoji works without a `SET NAMES` line. If any query fails, seeding stops before the image is built, so a half-sanitized image never reaches the registry.

A file like Vortex's [`scripts/sanitize.sql`](https://github.com/drevops/vortex/blob/main/scripts/sanitize.sql) works as is. Keep in mind that Vortex runs that file after `drush sql:sanitize`, while `seed.sh` runs only your queries, so email addresses and passwords stay as they are unless the file changes them:

```sql
-- Replace email addresses, so no message can reach a real user.
UPDATE `users_field_data` SET `mail` = CONCAT('user+', `uid`, '@localhost'), `init` = CONCAT('user+', `uid`, '@localhost') WHERE `uid` > 0;

-- Remove sessions.
TRUNCATE TABLE `sessions`;
```

### Why sanitizing takes a second import

MariaDB keeps recent changes in its redo log, and the redo log is part of the data that `seed.sh` captures. Sanitizing the captured database in place would leave the original values readable in the image. So `seed.sh` imports the dump and runs your queries in a separate container, exports the result, and imports that export into the container it captures, which never holds the original values.

The cost is time: the database is imported twice. The export also takes up disk space in the working directory until it's imported.

`seed.sh` doesn't change the dump file itself. If the dump mustn't leave production in the first place, sanitize it as you export it, for example with [Drush GDPR Dumper](https://github.com/robiningelbrecht/drush-gdpr-dumper) or [MTK](https://github.com/skpr/mtk).

## Forcing a database upgrade on start

Containers skip `mariadb-upgrade` by default, so a container started from a seeded image doesn't check every table before the server comes up. Set `MARIADB_FORCE_UPGRADE=1` when you do need the upgrade, for example when the database files came from an older MariaDB server than the one in the image:

```shell
docker run -e MARIADB_FORCE_UPGRADE=1 myorg/myimage:latest
```

The entrypoint then runs `mariadb-upgrade --force` before the server starts accepting connections. It only does this when the data directory isn't empty, as in a seeded image, so the flag has no effect on a container that's initializing an empty data directory. Only the value `1` turns it on: `true` or `yes` leave it off.

`FORCE_MYSQL_UPGRADE` is a deprecated alias for `MARIADB_FORCE_UPGRADE`: the entrypoint falls back to it when `MARIADB_FORCE_UPGRADE` is unset or empty, and prints a deprecation notice whenever it has a value.

## Maintenance and releasing

### Running tests

Tests run for the host platform by default.

```shell
npm --prefix tests/bats ci

# All tests.
tests/bats/node_modules/.bin/bats tests/bats --tap

# Individual test files.
tests/bats/node_modules/.bin/bats tests/bats/image.bats --tap
tests/bats/node_modules/.bin/bats tests/bats/seed.bats --tap
```

### Versioning

This project uses _Year-Month-Patch_ versioning:

- `YY`: Last two digits of the year, e.g., `23` for 2023.
- `m`: Numeric month, e.g., April is `4`.
- `patch`: Patch number for the month, starting at `0`.

Example: `23.4.2` indicates the third patch in April 2023.

Versions are following versions of the [upstream image](https://hub.docker.com/r/uselagoon/mariadb-10.11-drupal/tags) to ease maintenance.

### Releasing

Releases are scheduled to occur at a minimum of once per month.

This image is built by GitHub Actions and tagged as follows:

- `YY.m.patch` tag - when release tag is published on GitHub.
- `latest` - when release tag is published on GitHub.
- `canary` - on every push to `main` branch

The `seed.sh` script is automatically uploaded as a release asset and can be downloaded from the latest release.

### Dependencies update

Renovate bot is used to update dependencies. It creates a PR with the changes
and automatically merges it if CI passes. These changes are then released as
a `canary` version.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for local development setup and the
linting and testing commands.

## Updating

To pull the latest infrastructure from the template into this project, ask
Claude Code to "update scaffold" - see [`AGENTS.md`](AGENTS.md) for details.

---
_This repository was created using the [Scaffold](https://getscaffold.dev/) project template_
