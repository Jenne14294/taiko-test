#!/bin/bash
set -euo pipefail

sudo apt update
sudo apt install -y git python3-pip python3-virtualenv python3-venv nginx ffmpeg redis supervisor

if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    if [[ $ID = ubuntu ]]; then
        if [[ $VERSION_CODENAME = impish ]]; then
            VERSION_CODENAME=focal # MongoDB does not provide packages for Ubuntu 21.10
        fi
        REPO="https://repo.mongodb.org/apt/ubuntu $VERSION_CODENAME/mongodb-org/5.0 multiverse"
    elif [[ $ID = debian ]]; then
        if [[ $VERSION_CODENAME = bullseye ]]; then
            VERSION_CODENAME=buster # MongoDB does not provide packages for Debian 11 yet
        fi
        REPO="https://repo.mongodb.org/apt/debian $VERSION_CODENAME/mongodb-org/5.0 main"
    else
        echo "Unsupported distribution $ID"
        exit 1
    fi
else
    echo "Not running a distribution with /etc/os-release available"
    exit 1
fi

curl -fsSL https://pgp.mongodb.com/server-6.0.asc | sudo gpg --dearmor -o /usr/share/keyrings/mongodb-server-6.0.gpg
echo "deb [signed-by=/usr/share/keyrings/mongodb-server-6.0.gpg] https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs)/mongodb-org/6.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-6.0.list

sudo apt update
sudo apt install -y mongodb-org

sudo mkdir -p /srv/taiko-web
sudo chown $USER /srv/taiko-web
git clone https://github.com/Shuai-Xin/taiko-bui-backup.git /srv/taiko-web

cd /srv/taiko-web

tools/get_version.sh
cp tools/hooks/* .git/hooks/
cp config.example.py config.py
sudo cp tools/nginx.conf /etc/nginx/conf.d/taiko-web.conf

sudo sed -i 's/^\(\s\{0,\}\)\(include \/etc\/nginx\/sites-enabled\/\*;\)$/\1#\2/g' /etc/nginx/nginx.conf
sudo sed -i 's/}/    application\/wasm wasm;\n}/g' /etc/nginx/mime.types
sudo nginx -s reload

python3 -m venv .venv

.venv/bin/pip install --upgrade pip wheel setuptools
.venv/bin/pip install -r requirements.txt

sudo mkdir -p /var/log/taiko-web
sudo cp tools/supervisor.conf /etc/supervisor/conf.d/taiko-web.conf
sudo service supervisor restart

sudo systemctl enable mongod.service
sudo service mongod start

mongoimport --db taiko --collection categories --file /srv/taiko-web/tools/categories.json --jsonArray

IP=$(dig +short txt ch whoami.cloudflare @1.0.0.1 | tr -d '"')
echo
echo "Setup complete! You should be able to access your taiko-web instance at http://$IP"
echo
