#!/usr/bin/env bash

if [ -f ~/.homestead-features/wsl_user_name ]; then
    WSL_USER_NAME="$(cat ~/.homestead-features/wsl_user_name)"
    WSL_USER_GROUP="$(cat ~/.homestead-features/wsl_user_group)"
else
    WSL_USER_NAME=vagrant
    WSL_USER_GROUP=vagrant
fi

export DEBIAN_FRONTEND=noninteractive

if [ -f /home/$WSL_USER_NAME/.homestead-features/postgresql18 ]; then
    echo "PostgreSQL 18 already installed."
    exit 0
fi

touch /home/$WSL_USER_NAME/.homestead-features/postgresql18
chown -Rf $WSL_USER_NAME:$WSL_USER_GROUP /home/$WSL_USER_NAME/.homestead-features

# Stop and disable existing PostgreSQL clusters
systemctl stop postgresql 2>/dev/null || true
systemctl disable postgresql 2>/dev/null || true

for cluster in /etc/postgresql/*/main; do
    if [ -d "$cluster" ]; then
        version=$(echo "$cluster" | grep -oP '\d+')
        pg_dropcluster "$version" main --stop 2>/dev/null || true
        echo "Removed PostgreSQL ${version} cluster"
    fi
done

# Add official PostgreSQL apt repository if not present
if [ ! -f /etc/apt/sources.list.d/pgdg.list ]; then
    apt-get install -y curl ca-certificates
    install -d /usr/share/postgresql-common/pgdg
    curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc
    echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
fi

apt-get update

# Install PostgreSQL 18
apt-get install -y postgresql-18 postgresql-client-18 postgresql-server-dev-18

# Create PostgreSQL 18 cluster on port 5432
pg_createcluster 18 main --port=5432 --start

# Configure pg_hba.conf for password authentication
PG_HBA="/etc/postgresql/18/main/pg_hba.conf"
cat > "$PG_HBA" << 'EOF'
local   all             postgres                                peer
local   all             all                                     md5
host    all             all             127.0.0.1/32            md5
host    all             all             ::1/128                 md5
host    all             all             10.0.0.0/8              md5
host    all             all             192.168.0.0/16          md5
EOF

# Configure postgresql.conf to listen on all interfaces
PG_CONF="/etc/postgresql/18/main/postgresql.conf"
sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" "$PG_CONF"
sed -i "s/listen_addresses = 'localhost'/listen_addresses = '*'/" "$PG_CONF"

# Restart PostgreSQL 18
systemctl restart postgresql@18-main

# Wait for PostgreSQL to be ready
until sudo -u postgres pg_isready -q; do
    sleep 1
done

# Create homestead user with full privileges
sudo -u postgres psql -c "CREATE ROLE homestead WITH LOGIN PASSWORD 'secret' SUPERUSER CREATEDB CREATEROLE;"

# Install PostGIS for PostgreSQL 18
apt-get install -y postgresql-18-postgis-3 postgresql-18-postgis-3-scripts 2>/dev/null || echo "PostGIS for PostgreSQL 18 not available, skipping..."

# Enable service
systemctl enable postgresql@18-main

echo "==========================================="
echo "PostgreSQL 18 installed and configured"
echo "==========================================="
pg_lsclusters
sudo -u postgres psql -c "SELECT version();"
echo "==========================================="
