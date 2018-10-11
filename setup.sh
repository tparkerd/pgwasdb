#! /bin/sh

command -v pg_config > /dev/null 2>&1 || { printf "Command 'pg_config' is required but not found in path. Make sure PostgreSQL client tools are installed. Aborting.\n" 1>&2; exit 1; }

PG_LIBDIR=$(pg_config --pkglibdir)
PG_INSTALLDIR="$PG_LIBDIR/baxdb"

mkdir -p -m 755 "$PG_INSTALLDIR" || { printf "Unable to create directory '$pg_installdir' for installation into PostgreSQL. Aborting.
\n" 1>&2; exit 1; }

(
    cd ./c &&
    make &&
    cp array_multi_index.so imputed_genotype.so summarize_variant.so "$PG_INSTALLDIR" &&
    chmod -R 755 "$PG_INSTALLDIR"
)

(
    printf "=================================Libdir====================================\n"
    printf "$libdir and $PG_LIBDIR"
    cd ./lib/tinyint-0.1.1 &&
    make &&
    sed -i -e '1i\\\connect baxdb' -e 's|$libdir\/tinyint|$libdir/baxdb/tinyint|g' tinyint.sql &&
    cp tinyint.so "$PG_INSTALLDIR" &&
    chmod -R 755 "$PG_INSTALLDIR"
)

sudo -u postgres psql -q -U postgres -f ./ddl/setup.sql || { printf "Unable to perform setup for 'baxdb' database as user 'postgres'. Check UNIX account privileges and pg_hba.conf. Aborting.\n" 1>&2; exit 1; }
sudo -u postgres psql -q -U postgres -f ./lib/tinyint-0.1.1/tinyint.sql || { printf "Unable to add 'tinyint' type to database 'baxdb'. Aborting.\n" 1>&2; exit 1; }
sudo -u postgres psql -q -U postgres -f ./ddl/createtables.sql || { printf "Unable to perform setup for 'baxdb' database as user 'postgres'. Check UNIX account privileges and pg_hba.conf. Aborting.\n" 1>&2; exit 1; }
sed -i "1s/^/local baxdb baxdb_owner trust\n/" "$(sudo -u postgres psql -t -P "format=unaligned" -c "SHOW hba_file;")"
sudo -u postgres psql -t -P "format=unaligned" -c "SELECT pg_reload_conf();"

printf "Setup completed successfully.\n"
printf "Please consider checking your 'pg_hba.conf' file to alter permissions to access the database. Permissions are currently set as 'local pgsql_genomics pgsql_genomics_owner trust'.\n"