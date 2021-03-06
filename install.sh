#!/bin/bash
# Installation script for pgwasdb (i.e., GWAS database)
# Operating system: CentOS 7
# RDBMS: PostgreSQL 9.6
# NOTE: Make sure to run this under `root` user

set -e
set -x

if [ "$EUID" -ne 0 ]; then
  echo "Must be installed as root."
  exit
fi

yum -y update &&
  dnf -y install wget unzip gcc perl dos2unix epel-release &&
  dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-8-x86_64/pgdg-redhat-repo-latest.noarch.rpm &&
  dnf -qy module disable postgresql &&
  dnf install -y postgresql96-server postgresql96-devel &&
  /usr/pgsql-9.6/bin/postgresql96-setup initdb

systemctl enable postgresql-9.6.service &&
  systemctl start postgresql-9.6.service

database_types=("prod" "staging" "qa") &&
  pushd pgwasdb &&
  commit_hash="$(git rev-parse --short=7 HEAD)" &&
  echo 'PATH="/usr/pgsql-9.6/bin:$PATH"' >>~/.bashrc && source ~/.bashrc &&
  pg_libdir=$(pg_config --pkglibdir) &&
  popd

# For each database instance, (prod, staging, qa), create the database and
# install the TINYINT library
for dt in "${database_types[@]}"; do
  cp -r pgwasdb "$dt"
  database_name="pgwasdb_${commit_hash}_${dt}"
  pushd "$dt"
  echo -e "\e[104mChanging database reference name in each of the DDL files...\e[0m"
  for f in $(find ./ddl -type f); do
    sed -i "s/pgwasdb_commit_type/${database_name}/g" "$f"
    sed -i "s/pgwasdb_owner/pgwasdb_${dt}_owner/g" "$f"
  done
  echo "Done!"
  popd

  pg_installdir="$pg_libdir/${database_name}"
  echo "Installation directory: ${pg_installdir}"
  mkdir -vp -m 755 "$pg_installdir"

  pushd "./$dt/c"
  make
  echo "Copying the library files into ${pg_installdir}"
  cp -v array_multi_index.so imputed_genotype.so summarize_variant.so "$pg_installdir"
  chmod -R 755 "$pg_installdir"
  popd

  pushd "./$dt/lib/tinyint-0.1.1"
  make
  cp -v tinyint.so "$pg_installdir"
  chmod -R 755 "$pg_installdir"
  cp -v tinyint.sql "$pg_installdir"
  echo -e "\e[104mChanging database reference name in <tinyint.sql>\e[0m"
  sed -i -e "1i\\\\\connect ${database_name}" -e "s|$libdir\/tinyint|$libdir/$database_name/tinyint|g" "${pg_installdir}/tinyint.sql"
  popd

  # At this point, you will run these commands once for each instance of the database
  # If you want to create a qa, staging, and production, you'll need to modify
  # the credentials and name of the database in the following files. I suggest
  # using the `sed` command to swap out each of to reflect the commit version and
  # its username and password. I'm considering each of the users as a role
  cp -rv ./${dt}/ddl/ "$pg_installdir"
done

cp -v pgwasdb/initdb.sh /tmp/pgwasdb_initdb.sh
sudo -u postgres bash /tmp/pgwasdb_initdb.sh
rm -v /tmp/pgwasdb_initdb.sh

# Restart postgresql service to update listening addresses and host
# authentication
systemctl restart postgresql-9.6.service

# Open port 5432 (postgres)
firewall-cmd --permanent --add-port=5432/tcp
firewall-cmd --reload
# At this point, I was to be able to run
# pip ./dml/setup.py install
# It may be worth distributing the package once the project has come far enough along
#  Therefore, you'd be able to just run `pip install gwas_database` or something
# to that effect
