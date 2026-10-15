#!/bin/bash
# 1. Back up your old, failing configuration just in case
sudo mv /etc/containerd/config.toml /etc/containerd/config.toml.bak

# 2. Generate a fresh default configuration template (uses the correct version layout)
sudo containerd config default | sudo tee /etc/containerd/config.toml > /dev/null

# 3. Explicitly enable SystemdCgroup in the new config file
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

# 4. Restart containerd to apply the clean configuration
sudo systemctl daemon-reload
sudo systemctl restart containerd
