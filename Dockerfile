##
# Database data captured inside of the container.
#
# The upstream image declares the data directory as a VOLUME, which Docker
# does not export, so a different data directory is used.
#
# The upstream entrypoint does not support setting the data directory through
# an environment variable, so a modified entrypoint is installed. The default
# CMD is also overridden to include the custom data directory.
#
FROM uselagoon/mariadb-10.11-drupal:26.9.0@sha256:12de8f70404103bd12ef555c43db36add1852258d36203e9c58953db927f41bc

ENV MARIADB_DATA_DIR=/home/db-data

COPY entrypoint.bash /lagoon/entrypoints/9999-mariadb-init.bash

USER root

RUN mkdir -p /home/db-data \
    && chown -R mysql:mysql /home/db-data \
    && /bin/fix-permissions /home/db-data

USER mysql

# @todo Try removing the CMD override.
CMD ["mysqld", "--datadir=/home/db-data"]
