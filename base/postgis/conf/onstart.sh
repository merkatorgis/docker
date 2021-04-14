#!/bin/bash

pg.sh -c "alter database ${POSTGRES_DB} set app.ddl_done to false"

# cf ./dump_restore
if ! restore; then
    # we didn't restore an existing dump in an unconfigured database, so we're
    # either configuring a new database from its own DDL, or (possibly) updating
    # an existing database with any new DDL

    # maybe this image contains an newer (minor) version of PostGIS than the
    # last image that served this database
    update-postgis.sh

    echo "Next CREATE EXTENSION command will fail for PostGIS < 3."
    echo "It's OK to ignore that error."
    pg.sh -c "create extension if not exists postgis_raster"

    pg.sh -c "create extension if not exists ogr_fdw"
    pg.sh -c "create extension if not exists odbc_fdw"
    pg.sh -c "create extension if not exists plsh"
    pg.sh -c "create extension if not exists pgcrypto"
    pg.sh -c "create extension if not exists pgjwt"
    pg.sh -c "create extension if not exists mongo_fdw"

    # clear the "last" file (see last.sh)
    echo '' >/last

    /subconf.sh /tmp/mail/conf.sh
    /subconf.sh /tmp/web/conf.sh

    # This corresponds to the Dockerfile's ONBUILD COPY conf /tmp/conf
    find /tmp/conf -name "conf.sh" -exec /subconf.sh {} \;

    # see last.sh
    # shellcheck disable=SC1091
    source /last
fi

# enable the safeupdate extension
# https://github.com/eradman/pg-safeupdate
# http://postgrest.org/en/v7.0.0/admin.html?highlight=safeupdate#block-full-table-operations
pg.sh -c "alter database ${POSTGRES_DB} set session_preload_libraries = 'safeupdate'"

pg.sh -c "alter database ${POSTGRES_DB} set app.ddl_done to true"
