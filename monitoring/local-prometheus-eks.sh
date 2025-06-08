#!/bin/bash
# Simple script to monitor EKS from EC2 without complex connectivity

# Install AWS CLI if needed
if ! command -v aws &> /dev/null; then
    echo "Installing AWS CLI..."
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
fi

# Configure AWS CLI
echo "Configuring AWS CLI..."
read -p "Enter your AWS region (e.g., us-west-2): " AWS_REGION

# Use instance profile instead of access keys
mkdir -p ~/.aws
cat > ~/.aws/config << EOF
[default]
region = $AWS_REGION
output = json
EOF

# Create a simple Prometheus config that doesn't require direct EKS connectivity
read -p "Enter your EKS cluster name: " CLUSTER_NAME

# Create a simple prometheus.yml that works without direct EKS connectivity
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
  
  - job_name: 'cloudwatch-exporter'
    static_configs:
      - targets: ['localhost:9106']
EOF

# Install CloudWatch exporter to get EKS metrics via CloudWatch
echo "Installing CloudWatch exporter..."
wget https://github.com/prometheus/cloudwatch_exporter/releases/download/0.15.0/cloudwatch_exporter-0.15.0-jar-with-dependencies.jar -O cloudwatch_exporter.jar
sudo mv cloudwatch_exporter.jar /usr/local/bin/

# Create CloudWatch exporter config
sudo mkdir -p /etc/cloudwatch_exporter
sudo tee /etc/cloudwatch_exporter/config.yml << EOF
region: $AWS_REGION
metrics:
  - aws_namespace: AWS/EKS
    aws_metric_name: cluster_failed_node_count
    aws_dimensions: [ClusterName]
    aws_statistics: [Average]
    aws_dimensions_select:
      ClusterName: ["$CLUSTER_NAME"]
  - aws_namespace: AWS/EKS
    aws_metric_name: node_cpu_utilization
    aws_dimensions: [ClusterName]
    aws_statistics: [Average]
    aws_dimensions_select:
      ClusterName: ["$CLUSTER_NAME"]
  - aws_namespace: AWS/EKS
    aws_metric_name: node_memory_utilization
    aws_dimensions: [ClusterName]
    aws_statistics: [Average]
    aws_dimensions_select:
      ClusterName: ["$CLUSTER_NAME"]
  - aws_namespace: AWS/EKS
    aws_metric_name: pod_cpu_utilization
    aws_dimensions: [ClusterName]
    aws_statistics: [Average]
    aws_dimensions_select:
      ClusterName: ["$CLUSTER_NAME"]
  - aws_namespace: AWS/EKS
    aws_metric_name: pod_memory_utilization
    aws_dimensions: [ClusterName]
    aws_statistics: [Average]
    aws_dimensions_select:
      ClusterName: ["$CLUSTER_NAME"]
EOF

# Create CloudWatch exporter service
sudo tee /etc/systemd/system/cloudwatch_exporter.service << EOF
[Unit]
Description=CloudWatch Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=root
ExecStart=/usr/bin/java -jar /usr/local/bin/cloudwatch_exporter.jar 9106 /etc/cloudwatch_exporter/config.yml
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Start CloudWatch exporter
sudo systemctl daemon-reload
sudo systemctl enable cloudwatch_exporter
sudo systemctl start cloudwatch_exporter

# Restart Prometheus
sudo systemctl restart prometheus

echo "Setup complete! Your EKS cluster metrics will be available via CloudWatch in Prometheus."
echo "Access Prometheus at: http://localhost:9090"
echo "Access Grafana at: http://localhost:3000 (default login: admin/admin)"
echo ""
echo "To view EKS metrics in Grafana:"
echo "1. Add Prometheus as a data source (URL: http://localhost:9090)"
echo "2. Create a dashboard with metrics like:"
echo "   - cloudwatch_aws_eks_cluster_failed_node_count"
echo "   - cloudwatch_aws_eks_node_cpu_utilization"
echo "   - cloudwatch_aws_eks_node_memory_utilization"