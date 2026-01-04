#!/usr/bin/env bash

if [ -f ~/.homestead-features/wsl_user_name ]; then
    WSL_USER_NAME="$(cat ~/.homestead-features/wsl_user_name)"
    WSL_USER_GROUP="$(cat ~/.homestead-features/wsl_user_group)"
else
    WSL_USER_NAME=vagrant
    WSL_USER_GROUP=vagrant
fi

export DEBIAN_FRONTEND=noninteractive

if [ -f /home/$WSL_USER_NAME/.homestead-features/minio ]
then
    echo "minio already installed."
    exit 0
fi

ARCH=$(arch)

echo "Downloading MinIO server..."
if [[ "$ARCH" == "aarch64" ]]; then
  wget --progress=bar:force -O minio https://dl.minio.io/server/minio/release/linux-arm64/minio
else
  wget --progress=bar:force -O minio https://dl.minio.io/server/minio/release/linux-amd64/minio
fi

# Verify download succeeded
if [[ ! -s minio ]]; then
    echo "ERROR: MinIO server download failed"
    rm -f minio
    exit 1
fi

sudo chmod +x minio
sudo mv minio /usr/local/bin
sudo useradd -r minio-user -s /sbin/nologin 2>/dev/null || true
sudo mkdir -p /usr/local/share/minio
sudo mkdir -p /etc/minio

cat <<EOT >> /etc/default/minio
# Local export path.
MINIO_VOLUMES="/usr/local/share/minio/"
# Use if you want to run Minio on a custom port.
MINIO_OPTS="--config-dir /etc/minio --address :9600 --console-address :9601"
MINIO_CONFIG_ENV_FILE=/etc/default/minio
MINIO_ROOT_USER=homestead
MINIO_ROOT_PASSWORD=secretkey

EOT

sudo chown minio-user:minio-user /usr/local/share/minio
sudo chown minio-user:minio-user /etc/minio

curl -#O https://raw.githubusercontent.com/minio/minio-service/master/linux-systemd/minio.service
sudo mv minio.service /etc/systemd/system
sudo systemctl daemon-reload
sudo systemctl enable minio
sudo systemctl start minio

sudo ufw allow 9600

echo "Downloading MinIO client..."
if [[ "$ARCH" == "aarch64" ]]; then
  wget --progress=bar:force -O mc https://dl.minio.io/client/mc/release/linux-arm64/mc
else
  wget --progress=bar:force -O mc https://dl.minio.io/client/mc/release/linux-amd64/mc
fi

# Verify download succeeded
if [[ ! -s mc ]]; then
    echo "ERROR: MinIO client download failed"
    rm -f mc
    exit 1
fi

chmod +x mc
sudo mv mc /usr/local/bin

# Wait for MinIO to be ready
echo "Waiting for MinIO to start..."
TIMEOUT=60
ELAPSED=0
until curl -sf http://127.0.0.1:9600/minio/health/live > /dev/null 2>&1; do
    sleep 1
    ELAPSED=$((ELAPSED + 1))
    if [[ $ELAPSED -ge $TIMEOUT ]]; then
        echo "ERROR: MinIO failed to start within ${TIMEOUT} seconds"
        sudo systemctl status minio --no-pager
        exit 1
    fi
done

mc alias set homestead http://127.0.0.1:9600 homestead secretkey

# Mark as installed only after success
touch /home/$WSL_USER_NAME/.homestead-features/minio
chown -Rf $WSL_USER_NAME:$WSL_USER_GROUP /home/$WSL_USER_NAME/.homestead-features

echo "MinIO installed successfully"
