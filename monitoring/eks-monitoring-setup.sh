#!/bin/bash
# EKS Monitoring Setup Script
# This script configures Prometheus to monitor an EKS cluster

# Set variables
read -p "Enter your AWS region (e.g., us-west-2): " AWS_REGION
read -p "Enter your EKS cluster name: " CLUSTER_NAME

# Install kubectl if not already installed
if ! command -v kubectl &> /dev/null; then
    echo "Installing kubectl..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
fi

# Configure kubectl for EKS
echo "Configuring kubectl for EKS..."
aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME

# Create service account and get token
echo "Creating service account for Prometheus..."
kubectl apply -f - <<EOF
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

# Wait for token to be created
echo "Waiting for token to be created..."
sleep 5

# Get token and certificate
echo "Getting token and certificate..."
TOKEN=$(kubectl get secret prometheus-token -n kube-system -o jsonpath='{.data.token}' | base64 --decode)
CA_CERT=$(kubectl get secret prometheus-token -n kube-system -o jsonpath='{.data.ca\.crt}')
CLUSTER_ENDPOINT=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

# Save token and certificate
echo "$TOKEN" | sudo tee /etc/prometheus/k8s-token
echo "$CA_CERT" | base64 --decode | sudo tee /etc/prometheus/ca.crt

# Update Prometheus configuration
echo "Updating Prometheus configuration..."
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
      
  - job_name: 'kubernetes-api'
    scheme: https
    tls_config:
      ca_file: /etc/prometheus/ca.crt
      insecure_skip_verify: true
    bearer_token_file: /etc/prometheus/k8s-token
    static_configs:
      - targets: ['${CLUSTER_ENDPOINT#https://}']
  
  - job_name: 'kubernetes-nodes'
    scheme: https
    tls_config:
      ca_file: /etc/prometheus/ca.crt
      insecure_skip_verify: true
    bearer_token_file: /etc/prometheus/k8s-token
    kubernetes_sd_configs:
    - role: node
      api_server: ${CLUSTER_ENDPOINT}
      tls_config:
        ca_file: /etc/prometheus/ca.crt
        insecure_skip_verify: true
      bearer_token_file: /etc/prometheus/k8s-token
    relabel_configs:
    - action: labelmap
      regex: __meta_kubernetes_node_label_(.+)
    - target_label: __address__
      replacement: ${CLUSTER_ENDPOINT#https://}
    - source_labels: [__meta_kubernetes_node_name]
      regex: (.+)
      target_label: __metrics_path__
      replacement: /api/v1/nodes/\${1}/proxy/metrics
      
  - job_name: 'kubernetes-pods'
    scheme: https
    tls_config:
      ca_file: /etc/prometheus/ca.crt
      insecure_skip_verify: true
    bearer_token_file: /etc/prometheus/k8s-token
    kubernetes_sd_configs:
    - role: pod
      api_server: ${CLUSTER_ENDPOINT}
      tls_config:
        ca_file: /etc/prometheus/ca.crt
        insecure_skip_verify: true
      bearer_token_file: /etc/prometheus/k8s-token
    relabel_configs:
    - action: labelmap
      regex: __meta_kubernetes_pod_label_(.+)
    - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
      action: keep
      regex: true
    - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
      action: replace
      target_label: __metrics_path__
      regex: (.+)
    - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
      action: replace
      regex: ([^:]+)(?::\\d+)?;(\\d+)
      replacement: \$1:\$2
      target_label: __address__
EOF

# Restart Prometheus
echo "Restarting Prometheus..."
sudo systemctl restart prometheus

echo "EKS monitoring setup complete!"
echo "You should now see your EKS cluster in Prometheus at http://localhost:9090/targets"