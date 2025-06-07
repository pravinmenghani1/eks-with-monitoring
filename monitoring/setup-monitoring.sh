#!/bin/bash
# This script sets up Prometheus and Grafana on an EC2 instance
# Run this script on the EC2 instance in the same VPC as your EKS cluster

set -e

echo "=== Installing required packages ==="
sudo yum update -y
sudo yum install -y wget git

echo "=== Installing Prometheus ==="
wget https://github.com/prometheus/prometheus/releases/download/v2.45.0/prometheus-2.45.0.linux-amd64.tar.gz
tar xvfz prometheus-2.45.0.linux-amd64.tar.gz
sudo mv prometheus-2.45.0.linux-amd64/prometheus /usr/local/bin/
sudo mv prometheus-2.45.0.linux-amd64/promtool /usr/local/bin/
sudo mkdir -p /etc/prometheus
sudo mkdir -p /var/lib/prometheus

echo "=== Installing Grafana ==="
sudo tee /etc/yum.repos.d/grafana.repo > /dev/null << EOF
[grafana]
name=grafana
baseurl=https://packages.grafana.com/oss/rpm
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://packages.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOF

sudo yum install -y grafana
sudo systemctl enable grafana-server
sudo systemctl start grafana-server

echo "=== Creating Prometheus service ==="
sudo tee /etc/systemd/system/prometheus.service > /dev/null << EOF
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=root
ExecStart=/usr/local/bin/prometheus --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/var/lib/prometheus/
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload

echo "=== Installing kubectl ==="
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

echo "=== Configuring kubectl ==="
read -p "Enter your AWS region (e.g., us-east-1): " AWS_REGION
read -p "Enter your EKS cluster name (e.g., eks-production): " CLUSTER_NAME

aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME

echo "=== Deploying Node Exporter ==="
kubectl apply -f node-exporter.yaml

echo "=== Creating Service Account for Prometheus ==="
kubectl apply -f prometheus-rbac.yaml

echo "=== Getting token and certificate ==="
TOKEN=$(kubectl get secret prometheus-token -n kube-system -o jsonpath='{.data.token}' | base64 --decode)
CA_CERT=$(kubectl get secret prometheus-token -n kube-system -o jsonpath='{.data.ca\.crt}')
CLUSTER_ENDPOINT=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

echo "$TOKEN" | sudo tee /etc/prometheus/k8s-token
echo "$CA_CERT" | base64 --decode | sudo tee /etc/prometheus/ca.crt

echo "=== Configuring Prometheus ==="
NODE_IPS=$(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')
NODE_IPS_FORMATTED=$(echo $NODE_IPS | sed 's/ /:9100,/g'):9100

sudo cp prometheus.yml /etc/prometheus/prometheus.yml
sudo sed -i "s|CLUSTER_ENDPOINT|$CLUSTER_ENDPOINT|g" /etc/prometheus/prometheus.yml
sudo sed -i "s|NODE_IPS_FORMATTED|$NODE_IPS_FORMATTED|g" /etc/prometheus/prometheus.yml

echo "=== Starting Prometheus ==="
sudo systemctl enable prometheus
sudo systemctl restart prometheus

echo "=== Setup Complete ==="
echo "Prometheus is running at: http://localhost:9090"
echo "Grafana is running at: http://localhost:3000 (default login: admin/admin)"
echo ""
echo "Next steps:"
echo "1. Access Grafana at http://<EC2-IP>:3000"
echo "2. Add Prometheus data source (URL: http://localhost:9090)"
echo "3. Import dashboards: 1860, 315, 7249, 6417"