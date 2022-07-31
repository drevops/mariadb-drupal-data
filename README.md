# MariaDB Database data container
Allows capturing database data as a Docker layer.

[![CircleCI](https://circleci.com/gh/drevops/mariadb-drupal-data.svg?style=shield)](https://circleci.com/gh/drevops/mariadb-drupal-data)
![GitHub release (latest by date)](https://img.shields.io/github/v/release/drevops/mariadb-drupal-data)
![LICENSE](https://img.shields.io/github/license/drevops/mariadb-drupal-data)

## How it works

Usually, MariaDB uses data directory specified as a Docker volume that is
mounted onto host: this allows retaining data after container restarts.

The MariaDB image in this project uses custom location `/usr/lib/db-data` (not 
a Docker volume) to store expanded database files. These files then can be
captured as a Docker layer and stored as an image to docker registry. 

Image consumers download the image and start containers with instantaneously 
available data (no time-consuming database imports required).

Technically, majority of the functionality is relying on upstream [`amazeeio/mariadb-drupal`](https://github.com/uselagoon/lagoon-images/blob/main/images/mariadb-drupal/10.4.Dockerfile) Docker image. 
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

    bats tests/bats/data.bats --tap
    # or  
    DOCKER_DEFAULT_PLATFORM=linux/amd64 bats --tap tests/bats/data.bats

### Publishing

This image is built and pushed automatically to DockerHub:
1. For all commits to `master` branch as `:latest` tag.
2. For releases as `:<version>` tag.
3. For `feature/*` branches as `:<branch>` tag.

Versions are following versions of the [upstream image](https://hub.docker.com/r/uselagoon/mariadb-drupal/tags) to ease maintenance.
