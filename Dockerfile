##
# Database data captured inside of the container.
#
# Use existing upstream image, but override DB storage directory listed as
# a VOLUME (as Docker does not export volumes) with a different location.
# This requires altering entrypoint script (current entrypoint script does not
# support setting data directory as an environment variable) to support new
# location and overriding default CMD to include our custom data directory.
#
FROM uselagoon/mariadb-10.11-drupal:26.6.0@sha256:83a80790dd01f6809415f7af2992b27498e78cd1ce73bb0acb952516173cca32

# Set the data directory to a different location that a mounted volume.
ENV MARIADB_DATA_DIR=/home/db-data

# Add customised entrypoint script.
COPY entrypoint.bash /lagoon/entrypoints/9999-mariadb-init.bash

# Create the custom data directory and set permissions.
USER root

RUN mkdir -p /home/db-data \
    && chown -R mysql:mysql /home/db-data \
    && /bin/fix-permissions /home/db-data

USER mysql

# @todo Try removing the CMD override.
CMD ["mysqld", "--datadir=/home/db-data"]
