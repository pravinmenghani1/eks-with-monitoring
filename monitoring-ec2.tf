provider "aws" {
  region = var.region
}

# Get latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Create IAM role for EC2 instance
resource "aws_iam_role" "monitoring_role" {
  name = "eks-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

# Attach policies to the role
resource "aws_iam_role_policy_attachment" "eks_read_only" {
  role       = aws_iam_role.monitoring_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.monitoring_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Create instance profile
resource "aws_iam_instance_profile" "monitoring_profile" {
  name = "eks-monitoring-profile"
  role = aws_iam_role.monitoring_role.name
}

# Create security group for monitoring instance
resource "aws_security_group" "monitoring_sg" {
  name        = "eks-monitoring-sg"
  description = "Security group for EKS monitoring instance"
  vpc_id      = module.vpc.vpc_id

  # Allow SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow Prometheus access
  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow Grafana access
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eks-monitoring-sg"
  }
}

# Create EC2 instance for monitoring
resource "aws_instance" "monitoring" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t2.micro"
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.monitoring_sg.id]
  subnet_id              = module.vpc.private_subnets[0]
  iam_instance_profile   = aws_iam_instance_profile.monitoring_profile.name

  user_data = <<-EOF
#!/bin/bash
# Update system
dnf update -y
dnf install -y wget git jq

# Install Prometheus
wget https://github.com/prometheus/prometheus/releases/download/v2.45.0/prometheus-2.45.0.linux-amd64.tar.gz
tar xzf prometheus-2.45.0.linux-amd64.tar.gz
mv prometheus-2.45.0.linux-amd64/prometheus /usr/local/bin/
mv prometheus-2.45.0.linux-amd64/promtool /usr/local/bin/
mkdir -p /etc/prometheus
mkdir -p /var/lib/prometheus

# Install node_exporter
wget https://github.com/prometheus/node_exporter/releases/download/v1.6.1/node_exporter-1.6.1.linux-amd64.tar.gz
tar xzf node_exporter-1.6.1.linux-amd64.tar.gz
mv node_exporter-1.6.1.linux-amd64/node_exporter /usr/local/bin/

# Create node_exporter service
cat > /etc/systemd/system/node_exporter.service << 'EOT'
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=/usr/local/bin/node_exporter
Restart=always

[Install]
WantedBy=multi-user.target
EOT

# Install Grafana
cat > /etc/yum.repos.d/grafana.repo << 'EOT'
[grafana]
name=grafana
baseurl=https://packages.grafana.com/oss/rpm
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://packages.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOT

dnf install -y grafana

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/

# Configure kubectl for EKS
aws eks update-kubeconfig --region ${var.region} --name ${var.cluster_name}

# Create RBAC for Prometheus
cat > prometheus-rbac.yaml << 'EOT'
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
EOT

kubectl apply -f prometheus-rbac.yaml --validate=false

# Wait for token to be created
sleep 10

# Get token and certificate
TOKEN=$(kubectl get secret prometheus-token -n kube-system -o jsonpath='{.data.token}' | base64 --decode)
CA_CERT=$(kubectl get secret prometheus-token -n kube-system -o jsonpath='{.data.ca\.crt}')
CLUSTER_ENDPOINT=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

# Save token and certificate
echo "$TOKEN" > /etc/prometheus/k8s-token
echo "$CA_CERT" | base64 --decode > /etc/prometheus/ca.crt

# Create Prometheus configuration
cat > /etc/prometheus/prometheus.yml << EOT
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
EOT

# Create Prometheus service
cat > /etc/systemd/system/prometheus.service << 'EOT'
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
EOT

# Start services
systemctl daemon-reload
systemctl enable node_exporter
systemctl start node_exporter
systemctl enable prometheus
systemctl start prometheus
systemctl enable grafana-server
systemctl start grafana-server

# Configure Grafana with Prometheus data source
sleep 10
curl -s -X POST -H "Content-Type: application/json" -d '{"name":"Prometheus","type":"prometheus","url":"http://localhost:9090","access":"proxy","isDefault":true}' http://admin:admin@localhost:3000/api/datasources
EOF

  tags = {
    Name = "eks-monitoring"
  }

  depends_on = [module.eks]
}

# Output monitoring instance details
output "monitoring_instance_id" {
  description = "ID of the monitoring EC2 instance"
  value       = aws_instance.monitoring.id
}

output "monitoring_instance_private_ip" {
  description = "Private IP of the monitoring EC2 instance"
  value       = aws_instance.monitoring.private_ip
}

output "monitoring_instance_public_ip" {
  description = "Public IP of the monitoring EC2 instance (if in public subnet)"
  value       = aws_instance.monitoring.public_ip
}

output "monitoring_urls" {
  description = "URLs for monitoring tools"
  value = {
    prometheus = "http://${aws_instance.monitoring.public_ip}:9090"
    grafana    = "http://${aws_instance.monitoring.public_ip}:3000 (default login: admin/admin)"
  }
}