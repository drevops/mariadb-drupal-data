# MariaDB Database data container
Allows to capture data as a Docker layer.

[![CircleCI](https://circleci.com/gh/drevops/mariadb-drupal-data.svg?style=svg)](https://circleci.com/gh/drevops/mariadb-drupal-data)

## How it works
Usually, MariaDB uses data directory specified as a Docker volume that is
mounted onto host: this allows to retain data after container restarts.

The MariaDB image in this project uses custom location `/usr/lib/db-data` (not 
a Docker volume) to store expanded database files. These files then can be
captured as a Docker layer and stored as an image to docker registry. 

Image consumers download the image and start containers with instantaneously 
available data (no time-consuming database imports required).

Technically, majority of the functionality is relying on upstream [`amazeeio/mariadb-drupal`](https://github.com/amazeeio/lagoon/blob/master/images/mariadb-drupal/Dockerfile) Docker image. 
[Entrypoint script](entrypoint.bash) had to be copied from [upstream script](https://github.com/amazeeio/lagoon/blob/master/images/mariadb/entrypoints/9999-mariadb-init.bash) and adjusted to support custom data directory.  

## Use case

Drupal website with large database.

1. CI process builds a website overnight.
2. CI process captures latest database as a new Docker layer in the database image.
3. CI process tags and pushes image to the Docker registry.
4. Website developers pull latest image from the registry and build site locally.
   OR
   Subsequent CI builds pull latest image from the registry and build site. 

When required, website developers restart docker stack locally with already 
imported database, which saves significant amount of time for database imports.

## Maintenance
This image is built and pushed manually to DockerHub once parent image
is updated.

Versions are following versions of the upstream image to ease maintenance.

See the [CI configuration](.circleci/config.yml) for running tests locally.
