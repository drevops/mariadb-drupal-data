<p align="center">
  <a href="" rel="noopener">
  <img width=200px height=200px src="https://placehold.jp/000000/ffffff/200x200.png?text=MariaDB+Drupal+Data&css=%7B%22border-radius%22%3A%22%20100px%22%7D" alt="Mariadb Drupal data logo"></a>
</p>

<h1 align="center">MariaDB data container for Drupal with database captured as Docker layers.</h1>

<div align="center">

[![GitHub Issues](https://img.shields.io/github/issues/drevops/mariadb-drupal-data.svg)](https://github.com/drevops/mariadb-drupal-data/issues)
[![GitHub Pull Requests](https://img.shields.io/github/issues-pr/drevops/mariadb-drupal-data.svg)](https://github.com/drevops/mariadb-drupal-data/pulls)
[![CircleCI](https://circleci.com/gh/drevops/mariadb-drupal-data.svg?style=shield)](https://circleci.com/gh/drevops/mariadb-drupal-data)
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

The MariaDB image in this project uses custom location `/usr/lib/db-data` (not
a Docker volume) to store expanded database files. These files then can be
captured as a Docker layer and stored as an image to docker registry.

Image consumers download the image and start containers with instantaneously
available data (no time-consuming database imports required).

Technically, majority of the functionality is relying on upstream [`uselagoon/mariadb-drupal`](https://github.com/uselagoon/lagoon-images/blob/main/images/mariadb-drupal/10.11.Dockerfile) Docker image.
[Entrypoint script](entrypoint.bash) had to be copied from [upstream script](https://github.com/uselagoon/lagoon-images/blob/main/images/mariadb/entrypoints/9999-mariadb-init.bash) and adjusted to support custom data directory.

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

`./seed-db.sh` allows to easily create your own image with "seeded" database.

1. `./seed-db.sh path/to/db.sql myorg/myimage:latest`
2. `docker push myorg/myimage:latest`

In some cases, shell may report platform incorrectly. Run with forced platform:

    DOCKER_DEFAULT_PLATFORM=linux/amd64 ./seed-db.sh path/to/db.sql myorg/myimage:latest

## Maintenance

### Running tests

    tests/bats/node_modules/.bin/bats tests/bats/image.bats --tap
    tests/bats/node_modules/.bin/bats tests/bats/seed.bats --tap

### Publishing

This image is built and pushed automatically to DockerHub:
1. For all commits to `main` branch as `canary` tag.
2. For releases as `:<version>` and `latest` tag.
3. For `feature/my-branch` branches as `feature-my-branch` tag.

Versions are following versions of the [upstream image](https://hub.docker.com/r/uselagoon/mariadb-drupal/tags) to ease maintenance.

---
_This repository was created using the [Scaffold](https://getscaffold.dev/) project template_
