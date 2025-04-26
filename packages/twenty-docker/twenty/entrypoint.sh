#!/bin/sh
set -e

# Check if the initialization has already been done and that we enabled automatic migration
if [ "${DISABLE_DB_MIGRATIONS}" != "true" ] && [ ! -f /app/docker-data/db_status ]; then
    echo "Running database setup and migrations..."

    # Creating the database if it doesn't exist
    PGUSER=$(echo $PG_DATABASE_URL | awk -F '//' '{print $2}' | awk -F ':' '{print $1}')
    PGPASS=$(echo $PG_DATABASE_URL | awk -F ':' '{print $3}' | awk -F '@' '{print $1}')
    PGHOST=$(echo $PG_DATABASE_URL | awk -F '@' '{print $2}' | awk -F ':' '{print $1}')
    PGPORT=$(echo $PG_DATABASE_URL | awk -F ':' '{print $4}' | awk -F '/' '{print $1}')
    PGDATABASE=$(echo $PG_DATABASE_URL | awk -F ':' '{print $4}' | awk -F '/' '{print $2}')
    PGPASSWORD=${PGPASS} psql -h ${PGHOST} -p ${PGPORT} -U ${PGUSER} -d postgres -tc "SELECT 1 FROM pg_database WHERE datname = '${PGDATABASE}'" | grep -q 1 || \
    PGPASSWORD=${PGPASS} psql -h ${PGHOST} -p ${PGPORT} -U ${PGUSER} -d postgres -c "CREATE DATABASE \"${PGDATABASE}\""

    # Create twenty user if it doesn't exist
    if [ ${PGPASS} psql -h ${PGHOST} -p ${PGPORT} -U ${PGUSER} -d postgres -tc "SELECT 1 FROM pg_roles WHERE rolname='twenty'" | grep -q 0 ]; then
        echo "Creating basic "twenty" user..."
        TWENTYPASS=${PGPASS} psql -h ${PGHOST} -p ${PGPORT} -U ${PGUSER} -d postgres -c "CREATE ROLE twenty WITH LOGIN PASSWORD 'twenty'"

        # try to give the user all privileges
        if ! TWENTYPASS=${PGPASS} psql -h ${PGHOST} -p ${PGPORT} -U ${PGUSER} -d postgres -c "GRANT ALL PRIVILEGES ON DATABASE \"${PGDATABASE}\" TO twenty"; then
            echo "Failed to grant privileges to "twenty" user. Please consult Twenty documentation for assistance."
        fi
    fi

    # Run setup and migration scripts
    NODE_OPTIONS="--max-old-space-size=1500" tsx ./scripts/setup-db.ts
    yarn database:migrate:prod
    yarn command:prod upgrade

    # Mark initialization as done
    echo "Successfuly migrated DB!"
    touch /app/docker-data/db_status
fi

# Continue with the original Docker command
exec "$@"
