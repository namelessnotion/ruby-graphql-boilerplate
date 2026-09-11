#!/bin/sh
set -eu

# Provisions the role and database for each app environment, reading
# connection details straight out of the mounted .env files so this script
# and `rake db:init` (ruby/Rakefile) share the same source of truth.
create_from_env_file() {
  env_file="$1"
  [ -f "$env_file" ] || return 0

  database_url=$(grep -E '^DATABASE_URL=' "$env_file" | tail -n1 | cut -d= -f2-)
  [ -n "$database_url" ] || return 0

  # postgres://user:password@host:port/dbname?query
  rest=${database_url#postgres://}
  creds=${rest%%@*}
  user=${creds%%:*}
  password=${creds#*:}
  after_at=${rest#*@}
  db_with_query=${after_at#*/}
  db=${db_with_query%%\?*}

  psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --set ON_ERROR_STOP=1 <<-SQL
    DO \$\$
    BEGIN
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$user') THEN
        CREATE ROLE "$user" WITH LOGIN PASSWORD '$password';
      END IF;
    END
    \$\$;
SQL

  db_exists=$(psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --tuples-only --no-align \
    --set ON_ERROR_STOP=1 --command "SELECT 1 FROM pg_database WHERE datname = '$db'")
  if [ "$db_exists" != "1" ]; then
    psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --set ON_ERROR_STOP=1 \
      --command "CREATE DATABASE \"$db\" OWNER \"$user\";"
  fi
}

create_from_env_file /env/.env.development
create_from_env_file /env/.env.test
