##
# Database data captured inside of the container.
#
# Use existing upstream image, but override DB storage directory listed as
# a VOLUME (as Docker does not export volumes) with a different location.
# This requires altering entrypoint script (current entrypoint script does not
# support setting data directory as an environment variable) to support new
# location and overriding default CMD to include our custom data directory.
#
FROM amazeeio/mariadb-drupal:v1.2.0

ENV DATA_DIR=/var/lib/db-data

COPY entrypoint.bash /lagoon/entrypoints/9999-mariadb-entrypoint

USER root

RUN mkdir -p /var/lib/db-data \
    && chown mysql /var/lib/db-data \
    && /bin/fix-permissions /var/lib/db-data

USER mysql

CMD ["mysqld", "--datadir=/var/lib/db-data"]
