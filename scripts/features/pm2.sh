#!/usr/bin/env bash

if [ -f ~/.homestead-features/wsl_user_name ]; then
    WSL_USER_NAME="$(cat ~/.homestead-features/wsl_user_name)"
    WSL_USER_GROUP="$(cat ~/.homestead-features/wsl_user_group)"
else
    WSL_USER_NAME=vagrant
    WSL_USER_GROUP=vagrant
fi

export DEBIAN_FRONTEND=noninteractive

if [ -f /home/$WSL_USER_NAME/.homestead-features/pm2 ]
then
    echo "pm2 already installed."
    exit 0
fi

# Install pm2 with retries
MAX_RETRIES=3
RETRY_DELAY=5

for i in $(seq 1 $MAX_RETRIES); do
    echo "Installing pm2 (attempt $i of $MAX_RETRIES)..."
    if npm install -g pm2; then
        echo "pm2 installed successfully"

        # Mark as installed only after success
        touch /home/$WSL_USER_NAME/.homestead-features/pm2
        chown -Rf $WSL_USER_NAME:$WSL_USER_GROUP /home/$WSL_USER_NAME/.homestead-features
        exit 0
    fi

    if [ $i -lt $MAX_RETRIES ]; then
        echo "Attempt $i failed, waiting ${RETRY_DELAY}s before retry..."
        sleep $RETRY_DELAY
    fi
done

echo "ERROR: pm2 installation failed after $MAX_RETRIES attempts"
exit 1
