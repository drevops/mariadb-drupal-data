#!/usr/bin/env bash
##
# Entrypoint to start mysql service with custom data directory.
#
# This file is minimally modified to be easily updatable from the upstream.
# @see https://github.com/amazeeio/lagoon/blob/master/images/mariadb/entrypoints/9999-mariadb-init.bash

set -eo pipefail

set -x

# Locations
CONTAINER_SCRIPTS_DIR="/usr/share/container-scripts/mysql"

# @note: Added "${DATA_DIR}".
DATA_DIR="${DATA_DIR:-/var/lib/db-data}"

if [ "$(ls -A /etc/mysql/conf.d/)" ]; then
   ep /etc/mysql/conf.d/*
fi

if [ "${1:0:1}" = '-' ]; then
  set -- mysqld "$@"
fi

wantHelp=
for arg; do
  case "$arg" in
    -'?'|--help|--print-defaults|-V|--version)
      wantHelp=1
      break
      ;;
  esac
done



if [ "$1" = 'mysqld' -a -z "$wantHelp" ]; then
  if [ ! -d "/run/mysqld" ]; then
    mkdir -p /run/mysqld
    chown -R mysql:mysql /run/mysqld
  fi

  # @note: Updated to "${DATA_DIR}" and condition.
  # If data dir exists and is not empty - most likely the DB has already been initialised.
  if [ -d "${DATA_DIR}" ] && [ "$(ls -A "${DATA_DIR}")" ]; then
    echo "MySQL directory already present, skipping creation"

    # @note: Added re-creation of the config for descendant images to have
    # the same password-less client login experience as for the parent image.
    if [ ! -f /var/lib/mysql/.my.cnf ]; then
      echo "[client]" >> /var/lib/mysql/.my.cnf
      echo "user=root" >> /var/lib/mysql/.my.cnf
      echo "password=${MARIADB_ROOT_PASSWORD}"  >> /var/lib/mysql/.my.cnf
    fi
  else
    echo "MySQL data directory not found, creating initial DBs"

    # @note: Updated to "${DATA_DIR}".
    mysql_install_db --skip-name-resolve --skip-auth-anonymous-user --datadir="${DATA_DIR}"

    echo "starting mysql for initdb.d import."
    # @note: Updated to "${DATA_DIR}".
    /usr/bin/mysqld --skip-networking --wsrep_on=OFF --datadir="${DATA_DIR}" &
    pid="$!"
    echo "pid is $pid"

    for i in {30..0}; do
      if echo 'SELECT 1' | mysql -u root; then
        break
      fi
      echo 'MySQL init process in progress...'
      sleep 1
    done

    if [ "$MARIADB_ROOT_PASSWORD" = "" ]; then
      MARIADB_ROOT_PASSWORD=`pwgen 16 1`
      echo "[i] MySQL root Password: $MARIADB_ROOT_PASSWORD"
    fi

    MARIADB_DATABASE=${MARIADB_DATABASE:-""}
    MARIADB_USER=${MARIADB_USER:-""}
    MARIADB_PASSWORD=${MARIADB_PASSWORD:-""}

    tfile=`mktemp`
    if [ ! -f "$tfile" ]; then
        return 1
    fi

    cat << EOF > $tfile
DROP DATABASE IF EXISTS test;
USE mysql;
UPDATE mysql.user SET PASSWORD=PASSWORD("$MARIADB_ROOT_PASSWORD") WHERE user="root";
FLUSH PRIVILEGES;

EOF

    if [ "$MARIADB_DATABASE" != "" ]; then
      echo "[i] Creating database: $MARIADB_DATABASE"
      echo "CREATE DATABASE IF NOT EXISTS \`$MARIADB_DATABASE\` ;" >> $tfile
      if [ "$MARIADB_USER" != "" ]; then
        echo "[i] Creating user: $MARIADB_USER with password $MARIADB_PASSWORD"
        echo "GRANT ALL ON \`$MARIADB_DATABASE\`.* to '$MARIADB_USER'@'%' IDENTIFIED BY '$MARIADB_PASSWORD';" >> $tfile
      fi
    fi


    cat $tfile
    cat $tfile | mysql -v -u root
    rm -v -f $tfile

    echo "[client]" >> /var/lib/mysql/.my.cnf
    echo "user=root" >> /var/lib/mysql/.my.cnf
    echo "password=${MARIADB_ROOT_PASSWORD}"  >> /var/lib/mysql/.my.cnf
    echo "[mysql]" >> /var/lib/mysql/.my.cnf
    echo "database=${MARIADB_DATABASE}" >> /var/lib/mysql/.my.cnf

    for f in `ls /docker-entrypoint-initdb.d/*`; do
      case "$f" in
        *.sh)     echo "$0: running $f"; . "$f" ;;
        *.sql)    echo "$0: running $f"; cat $f| tee | mysql -u root -p${MARIADB_ROOT_PASSWORD}; echo ;;
        *)        echo "$0: ignoring $f" ;;
      esac
    echo
    done

    if ! kill -s TERM "$pid" || ! wait "$pid"; then
      echo >&2 'MySQL init process failed.'
      exit 1
    fi

  fi

echo "done, now starting daemon"

fi

exec $@
