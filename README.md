<p align="center">
  <a href="" rel="noopener">
  <img width=200px height=200px src="https://placehold.jp/000000/ffffff/200x200.png?text=MariaDB+Drupal+Data&css=%7B%22border-radius%22%3A%22%20100px%22%7D" alt="Mariadb Drupal data logo"></a>
</p>

<h1 align="center">MariaDB data container for Drupal with database captured as Docker layers.</h1>

<div align="center">

[![GitHub Issues](https://img.shields.io/github/issues/drevops/mariadb-drupal-data.svg)](https://github.com/drevops/mariadb-drupal-data/issues)
[![GitHub Pull Requests](https://img.shields.io/github/issues-pr/drevops/mariadb-drupal-data.svg)](https://github.com/drevops/mariadb-drupal-data/pulls)
[![Test and Build](https://github.com/drevops/mariadb-drupal-data/actions/workflows/test.yml/badge.svg)](https://github.com/drevops/mariadb-drupal-data/actions/workflows/test.yml)
[![codecov](https://codecov.io/gh/drevops/mariadb-drupal-data/graph/badge.svg?token=JYSIXUF6QX)](https://codecov.io/gh/drevops/mariadb-drupal-data)
![GitHub release (latest by date)](https://img.shields.io/github/v/release/drevops/mariadb-drupal-data)
![LICENSE](https://img.shields.io/github/license/drevops/mariadb-drupal-data)
![Renovate](https://img.shields.io/badge/renovate-enabled-green?logo=renovatebot)

[![Docker Pulls](https://img.shields.io/docker/pulls/drevops/mariadb-drupal-data?logo=docker)](https://hub.docker.com/r/drevops/mariadb-drupal-data)
![amd64](https://img.shields.io/badge/arch-linux%2Famd64-brightgreen)
![arm64](https://img.shields.io/badge/arch-linux%2Farm64-brightgreen)

</div>

## How it works

Usually, MariaDB uses data directory specified as a Docker volume that is
mounted onto host: this allows retaining data after container restarts.

The MariaDB image in this project uses custom location `/home/db-data` (not
a Docker volume) to store expanded database files. These files then can be
captured as a Docker layer and stored as an image to docker registry.

Image consumers download the image and start containers with instantaneously
available data (no time-consuming database imports required).

Technically, the majority of the functionality is relying on upstream [`uselagoon/mariadb-drupal`](https://github.com/uselagoon/lagoon-images/blob/main/images/mariadb-drupal/10.11.Dockerfile) Docker image.
[Entrypoint script](entrypoint.bash)) had to be copied from [upstream script](https://github.com/uselagoon/lagoon-images/blob/main/images/mariadb/entrypoints/9999-mariadb-init.bash) and adjusted to support custom data directory.

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

# with forced platform
DOCKER_DEFAULT_PLATFORM=linux/amd64 ./seed.sh path/to/db.sql myorg/myimage:latest

# for multi-platform image
DESTINATION_PLATFORMS=linux/amd64,linux/arm64 ./seed.sh path/to/db.sql myorg/myimage:latest

# with a custom base image (e.g., canary)
BASE_IMAGE=drevops/mariadb-drupal-data:canary ./seed.sh path/to/db.sql myorg/myimage:latest
```

Note that you should already be logged in to the registry as `seed.sh` will be pushing an image as a part of `docker buildx` process.

## Maintenance and releasing

### Running tests

```shell
npm --prefix tests/bats install
tests/bats/node_modules/.bin/bats tests/bats/image.bats --tap
tests/bats/node_modules/.bin/bats tests/bats/seed.bats --tap
```

### Versioning

This project uses _Year-Month-Patch_ versioning:

- `YY`: Last two digits of the year, e.g., `23` for 2023.
- `m`: Numeric month, e.g., April is `4`.
- `patch`: Patch number for the month, starting at `0`.

Example: `23.4.2` indicates the third patch in April 2023.

Versions are following versions of the [upstream image](https://hub.docker.com/r/uselagoon/mariadb-drupal/tags) to ease maintenance.

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

---
_This repository was created using the [Scaffold](https://getscaffold.dev/) project template_
