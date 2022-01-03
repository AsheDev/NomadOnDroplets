#!/bin/bash
shopt -s xpg_echo # ensures `\n` is parsed correctly

SERVER_ADDR=$1 # Command line argument for the Server address
CLIENT_ADDR=$2 # Command line argument for the Client address

# A basic regex check against the provided IP addresses
if ! [[ $SERVER_ADDR =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
  echo "The provided server address is invalid. The script will exit."
  exit
fi
if ! [[ $CLIENT_ADDR =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
  echo "The provided client address is invalid. The script will exit."
  exit
fi

echo "\n**********************"
echo ">>> Configuring server's initial state..."
echo "**********************\n"

ssh -o StrictHostKeyChecking=no root@$SERVER_ADDR SERVER_ADDR=$SERVER_ADDR /bin/bash <<'EOF'
shopt -s xpg_echo

echo "\n**********************"
echo ">>> Adding the HashiCorp GPG key"
echo "**********************"
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -

echo "\n\n**********************"
echo ">>> Adding HashiCorp linux repository"
echo "**********************"
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"

echo "\n\n**********************"
echo ">>> Installing Nomad"
echo "**********************"
sudo apt-get update && sudo apt-get install nomad

echo "\n\n**********************"
echo ">>> Installing Consul"
echo "**********************"
sudo apt-get update && sudo apt-get install consul

echo "\n\n**********************"
echo ">>> Generating certificates and tokens"
echo "**********************"

# Server certs
sudo consul tls ca create
# Note, "-dc dc1 -domain consul" can be whatever matches the setup
sudo consul tls cert create -server -dc dc1 -domain consul

# Client certs
# These will be moved to the client later
consul tls cert create -client

# Save the encryption token
consul keygen > consul.token
export CONSUL_ENCRYPT_TOKEN=`cat consul.token`

echo "\n\n**********************"
echo "Installing extras..."
echo "**********************"
sudo apt install -y vim net-tools

echo "\n\n**********************"
echo "Creating Nomad config files..."
echo "**********************"
cat << EOT > /etc/nomad.d/nomad.hcl
data_dir = "/opt/nomad/data"
bind_addr = "0.0.0.0"

server {
  enabled = true
  bootstrap_expect = 1
}

advertise {
  rpc = "$SERVER_ADDR"
}
EOT
cat << EOT > /etc/systemd/system/nomad.service
[Unit]
Description=Nomad
Documentation=https://www.nomadproject.io/docs
Wants=network-online.target
After=network-online.target

[Service]
ExecReload=/bin/kill -HUP $MAINPID
ExecStart=/usr/bin/nomad agent -config /etc/nomad.d
KillMode=process
KillSignal=SIGINT
LimitNOFILE=infinity
LimitNPROC=infinity
Restart=on-failure
RestartSec=2
StartLimitBurst=3
TasksMax=infinity

[Install]
WantedBy=multi-user.target
EOT

echo "\n\n**********************"
echo "Creating Consul config files..."
echo "**********************"
cat << EOT > /etc/consul.d/consul.hcl
node_name = "consul-server"
datacenter = "dc1"
data_dir = "/opt/consul"
encrypt = "$CONSUL_ENCRYPT_TOKEN"
verify_incoming = true
verify_outgoing = true
verify_server_hostname = true
bind_addr = "$SERVER_ADDR"

ca_file = "/root/consul-agent-ca.pem"
cert_file = "/root/dc1-server-consul-0.pem"
key_file = "/root/dc1-server-consul-0-key.pem"

auto_encrypt {
  allow_tls = true
}

acl {
  enabled = true
  default_policy = "allow"
  enable_token_persistence = true
}

performance {
  raft_multiplier = 1
}
EOT
### Can I combine these two files?.. ###
cat << EOT > /etc/consul.d/server.hcl
server = true
bootstrap_expect = 1
bind_addr = "$SERVER_ADDR"
client_addr = "0.0.0.0"

connect {
  enabled = true
}

addresses {
  grpc = "127.0.0.1"
}

ports {
  grpc = 8502
}

ui_config {
  enabled = true
}
EOT

cat << EOT > /etc/systemd/system/consul.service
[Unit]
Description=Consul by HashiCorp
Documentation=https://www.consul.io/docs/
Wants=network-online.target
After=network.target network-online.target

[Service]
EnvironmentFile=/etc/consul.d/consul.env
ExecReload=/bin/kill -HUP $MAINPID
ExecStart=/usr/bin/consul agent -config-dir=/etc/consul.d/
Group=root
KillMode=process
KillSignal=SIGINT
LimitNOFILE=65536
LimitNPROC=infinity
Restart=on-failure
RestartSec=5
StartLimitBurst=3
TasksMax=infinity
Type=simple
User=root
WorkingDirectory=/

[Install]
WantedBy=multi-user.target
EOT

# Start the services
sudo systemctl enable nomad
sudo systemctl enable consul
sudo systemctl start nomad
sudo systemctl start consul

# FOR REASONS
sudo systemctl daemon-reload
sudo systemctl start consul
EOF
echo "\n**********************"
echo ">>> Configuration of server's initial state complete"
echo "**********************\n"

echo "\n\n**********************"
echo ">>> Downloading necessary config files from server..."
echo "**********************"

# Download client cert and key locally from the server for Nomad
# Download only the client cert for Consul
# We'll upload these to the client a bit later
# https://learn.hashicorp.com/tutorials/consul/tls-encryption-secure#setup-the-clients
scp root@$SERVER_ADDR:/root/dc1-client-consul-0.pem .
scp root@$SERVER_ADDR:/root/dc1-client-consul-0-key.pem .
scp root@$SERVER_ADDR:/root/consul-agent-ca.pem .

# Not the most secure thing in the world but no big deal for this script
scp root@$SERVER_ADDR:/root/consul.token .
export CONSUL_ENCRYPT_TOKEN=`cat consul.token`
rm consul.token

# Download package list
# For some reason, the client server trips on its own list...
scp root@$SERVER_ADDR:/etc/apt/sources.list .

echo "\n\n**********************"
echo ">>> Uploading pre-configured Nomad job specs..."
echo "**********************"

scp http-echo.nomad traefik.nomad root@$SERVER_ADDR:/root # basic jobs

echo "\n\n**********************"
echo ">>> Uploading server-generated config files to client..."
echo "**********************"
# Upload client cert and key to client
scp dc1-client-consul-0.pem dc1-client-consul-0-key.pem root@$CLIENT_ADDR:/root/

# Upload the consul client cert file
scp consul-agent-ca.pem root@$CLIENT_ADDR:/root/

# Upload package list
# For some reason, the client server trips on its own list...
scp sources.list root@$CLIENT_ADDR:/etc/apt/

echo "\n**********************"
echo ">>> Configuring client's initial state..."
echo "**********************\n"

# Configure the client and enable services
ssh -o StrictHostKeyChecking=no root@$CLIENT_ADDR SERVER_ADDR=$SERVER_ADDR CLIENT_ADDR=$CLIENT_ADDR CONSUL_ENCRYPT_TOKEN=$CONSUL_ENCRYPT_TOKEN /bin/bash <<'EOF'
shopt -s xpg_echo

echo "\n**********************"
echo ">>> Adding the HashiCorp GPG key"
echo "**********************"
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -

echo "\n\n**********************"
echo ">>> Adding HashiCorp linux repository"
echo "**********************"
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"

echo "\n\n**********************"
echo ">>> Installing Nomad"
echo "**********************"
sudo apt-get update && sudo apt-get install nomad

echo "\n\n**********************"
echo ">>> Installing Consul"
echo "**********************"
sudo apt-get update && sudo apt-get install consul

echo "\n\n**********************"
echo ">>> Installing CNI networking plugin"
echo "**********************"
curl -L -o cni-plugins.tgz https://github.com/containernetworking/plugins/releases/download/v0.8.1/cni-plugins-linux-amd64-v0.8.1.tgz
sudo mkdir -p /opt/cni/bin
sudo tar -C /opt/cni/bin -xzf cni-plugins.tgz

echo "\n\n**********************"
echo "Installing extras..."
echo "**********************"
sudo apt install -y docker.io vim net-tools

echo "\n\n**********************"
echo "Creating Consul config files..."
echo "**********************"

# Overwrite the keyring file, ensuring the correct token is present
mkdir -p /opt/consul/serf
cat << EOT > /opt/consul/serf/local.keyring
["$CONSUL_ENCRYPT_TOKEN"]
EOT

cat << EOT > /etc/consul.d/consul.hcl
node_name = "consul-client"
server = false
datacenter = "dc1"
encrypt = "$CONSUL_ENCRYPT_TOKEN"
data_dir = "/opt/consul"
log_level = "INFO"
bind_addr = "$CLIENT_ADDR" # This is the Droplet's public IP address
retry_join = ["$SERVER_ADDR"] # This is the server we need to join to
ports {
  gRPC = 8502
}
verify_incoming = true
verify_outgoing = true
verify_server_hostname = true
ca_file = "/root/consul-agent-ca.pem"
cert_file = "/root/dc1-client-consul-0.pem"
key_file = "/root/dc1-client-consul-0-key.pem"
EOT

cat << EOT > /etc/systemd/system/consul.service
[Unit]
Description=Consul by HashiCorp
Documentation=https://www.consul.io/docs/
Wants=network-online.target
After=network.target network-online.target

[Service]
EnvironmentFile=/etc/consul.d/consul.env
ExecReload=/bin/kill -HUP $MAINPID
ExecStart=/usr/bin/consul agent -config-dir=/etc/consul.d/
Group=root
KillMode=process
KillSignal=SIGINT
LimitNOFILE=65536
LimitNPROC=infinity
Restart=on-failure
RestartSec=5
StartLimitBurst=3
TasksMax=infinity
Type=simple
User=root
WorkingDirectory=/

[Install]
WantedBy=multi-user.target
EOT

# Copy this file for initial start
cp /etc/systemd/system/consul.service /lib/systemd/system/consul.service

echo "\n\n**********************"
echo "Creating Nomad config files..."
echo "**********************"

cat << EOT > /etc/nomad.d/nomad.hcl
data_dir = "/opt/nomad/data"
bind_addr = "$CLIENT_ADDR"

client {
  enabled = true
  servers = ["$SERVER_ADDR"]
}
EOT

# Start the services
sudo systemctl enable nomad
sudo systemctl enable consul
sudo systemctl start nomad
sudo systemctl start consul
EOF
echo "\n**********************"
echo ">>> Configuration of client's initial state complete"
echo "**********************\n"

echo "\n\n**********************"
echo "Finalizing services and jobs on server node..."
echo "**********************\n"
ssh root@$SERVER_ADDR CLIENT_ADDR=$CLIENT_ADDR /bin/bash <<'EOF'
shopt -s xpg_echo

# Start the services
sudo systemctl daemon-reload # required due to Consul quirk
sudo systemctl start nomad
sudo systemctl start consul

# Spin up Traefik for load balancing
nomad job run traefik.nomad
EOF
