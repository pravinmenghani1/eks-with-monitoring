#!/bin/bash
# Simple EKS Monitoring Setup Script
# This script sets up Prometheus and Grafana to monitor an EKS cluster
# Run this on an EC2 instance in the same VPC as your EKS cluster

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

echo "=== Installing node_exporter on EC2 ==="
wget https://github.com/prometheus/node_exporter/releases/download/v1.6.1/node_exporter-1.6.1.linux-amd64.tar.gz
tar xvfz node_exporter-1.6.1.linux-amd64.tar.gz
sudo cp node_exporter-1.6.1.linux-amd64/node_exporter /usr/local/bin/

echo "=== Creating node_exporter service ==="
sudo tee /etc/systemd/system/node_exporter.service << EOF
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=/usr/local/bin/node_exporter
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter

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
sudo tee /etc/systemd/system/prometheus.service << EOF
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

echo "=== Creating RBAC for Prometheus ==="
cat > prometheus-rbac.yaml << EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: prometheus-monitor
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus-role
rules:
- apiGroups: [""]
  resources: ["nodes", "nodes/proxy", "services", "endpoints", "pods"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["extensions", "apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["metrics.k8s.io"]
  resources: ["pods", "nodes"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: prometheus-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: prometheus-role
subjects:
- kind: ServiceAccount
  name: prometheus-monitor
  namespace: kube-system
---
apiVersion: v1
kind: Secret
metadata:
  name: prometheus-token
  namespace: kube-system
  annotations:
    kubernetes.io/service-account.name: prometheus-monitor
type: kubernetes.io/service-account-token
EOF

echo "=== Deploying node-exporter on EKS ==="
cat > node-exporter.yaml << EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-exporter
  namespace: kube-system
  labels:
    app: node-exporter
spec:
  selector:
    matchLabels:
      app: node-exporter
  template:
    metadata:
      labels:
        app: node-exporter
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "9100"
    spec:
      hostNetwork: true
      containers:
      - name: node-exporter
        image: prom/node-exporter:latest
        ports:
        - containerPort: 9100
          hostPort: 9100
          name: metrics
        resources:
          limits:
            cpu: 200m
            memory: 50Mi
          requests:
            cpu: 100m
            memory: 30Mi
        volumeMounts:
        - name: proc
          mountPath: /host/proc
          readOnly: true
        - name: sys
          mountPath: /host/sys
          readOnly: true
      volumes:
      - name: proc
        hostPath:
          path: /proc
      - name: sys
        hostPath:
          path: /sys
EOF

echo "=== Applying RBAC and node-exporter ==="
kubectl apply -f prometheus-rbac.yaml
kubectl apply -f node-exporter.yaml

echo "=== Getting token and certificate ==="
TOKEN=$(kubectl get secret prometheus-token -n kube-system -o jsonpath='{.data.token}' | base64 --decode)
CA_CERT=$(kubectl get secret prometheus-token -n kube-system -o jsonpath='{.data.ca\.crt}')
CLUSTER_ENDPOINT=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

echo "$TOKEN" | sudo tee /etc/prometheus/k8s-token
echo "$CA_CERT" | base64 --decode | sudo tee /etc/prometheus/ca.crt

echo "=== Creating minimal Prometheus configuration ==="
sudo tee /etc/prometheus/prometheus.yml << EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
  
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']
EOF

echo "=== Starting Prometheus ==="
sudo systemctl enable prometheus
sudo systemctl start prometheus

echo "=== Verifying Prometheus is collecting metrics ==="
sleep 5
curl -s http://localhost:9090/api/v1/query?query=up | grep -q '"value":\[.*,1\]' && echo "✅ Prometheus is collecting metrics" || echo "❌ No metrics collected"

echo "=== Setup Complete ==="
echo "Prometheus is running at: http://localhost:9090"
echo "Grafana is running at: http://localhost:3000 (default login: admin/admin)"
echo ""
echo "Next steps:"
echo "1. Access Grafana at http://<EC2-IP>:3000"
echo "2. Add Prometheus data source (URL: http://localhost:9090)"
echo "3. Import dashboard ID 1860 (Node Exporter Full)"
echo ""
echo "For full EKS monitoring, run:"
echo "sudo bash -c \"cat > /etc/prometheus/prometheus.yml << EOF"
echo "global:"
echo "  scrape_interval: 15s"
echo ""
echo "scrape_configs:"
echo "  - job_name: 'prometheus'"
echo "    static_configs:"
echo "      - targets: ['localhost:9090']"
echo "  "
echo "  - job_name: 'node'"
echo "    static_configs:"
echo "      - targets: ['localhost:9100']"
echo "      "
echo "  - job_name: 'kubernetes-api'"
echo "    scheme: https"
echo "    tls_config:"
echo "      ca_file: /etc/prometheus/ca.crt"
echo "      insecure_skip_verify: true"
echo "    bearer_token_file: /etc/prometheus/k8s-token"
echo "    static_configs:"
echo "      - targets: ['${CLUSTER_ENDPOINT#https://}']"
echo "EOF\""
echo ""
echo "sudo systemctl restart prometheus"