##
# Database data captured inside of the container.
#
# Use existing upstream image, but override DB storage directory listed as
# a VOLUME (as Docker does not export volumes) with a different location.
# This requires altering entrypoint script (current entrypoint script does not
# support setting data directory as an environment variable) to support new
# location and overriding default CMD to include our custom data directory.
#
FROM uselagoon/mariadb-drupal:24.8.0

# Set the data directory to a different location that a mounted volume.
ENV MARIADB_DATA_DIR=/var/lib/db-data

# Add customised entrypoint script.
COPY 9999-mariadb-init.bash /lagoon/entrypoints/

USER root

RUN mkdir -p /var/lib/db-data \
    && chown -R mysql /var/lib/db-data \
    && chgrp -R mysql /var/lib/db-data \
    && /bin/fix-permissions /var/lib/db-data

USER mysql

# @todo Try removing the CMD override.
CMD ["mysqld", "--datadir=/var/lib/db-data"]
