#!/bin/bash
# EC2 Monitoring Setup Script - User Data Ready
# This script sets up Prometheus and Grafana to monitor an EC2 instance
# Copy this entire script into the EC2 User Data field when launching an instance

# Log all output
exec > >(tee /var/log/user-data.log) 2>&1
echo "Starting monitoring setup: $(date)"

# Install required packages
yum update -y
yum install -y wget git

# Install Prometheus
echo "Installing Prometheus..."
wget https://github.com/prometheus/prometheus/releases/download/v2.45.0/prometheus-2.45.0.linux-amd64.tar.gz
tar xzf prometheus-2.45.0.linux-amd64.tar.gz
mv prometheus-2.45.0.linux-amd64/prometheus /usr/local/bin/
mv prometheus-2.45.0.linux-amd64/promtool /usr/local/bin/
mkdir -p /etc/prometheus
mkdir -p /var/lib/prometheus

# Install node_exporter
echo "Installing node_exporter..."
wget https://github.com/prometheus/node_exporter/releases/download/v1.6.1/node_exporter-1.6.1.linux-amd64.tar.gz
tar xzf node_exporter-1.6.1.linux-amd64.tar.gz
cp node_exporter-1.6.1.linux-amd64/node_exporter /usr/local/bin/

# Create node_exporter service
cat > /etc/systemd/system/node_exporter.service << 'EOF'
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

# Install Grafana
echo "Installing Grafana..."
cat > /etc/yum.repos.d/grafana.repo << 'EOF'
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

yum install -y grafana

# Create Prometheus configuration
cat > /etc/prometheus/prometheus.yml << 'EOF'
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

# Create Prometheus service
cat > /etc/systemd/system/prometheus.service << 'EOF'
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

# Start services
echo "Starting services..."
systemctl daemon-reload
systemctl enable node_exporter
systemctl start node_exporter
systemctl enable prometheus
systemctl start prometheus
systemctl enable grafana-server
systemctl start grafana-server

# Configure Grafana with Prometheus data source automatically
echo "Configuring Grafana..."
sleep 10 # Wait for Grafana to start

# Create API key for Grafana
GRAFANA_API_KEY=$(curl -s -X POST -H "Content-Type: application/json" -d '{"name":"apikeycurl", "role": "Admin"}' http://admin:admin@localhost:3000/api/auth/keys | grep -o '"key":"[^"]*' | grep -o '[^"]*$')

# Add Prometheus data source
curl -s -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $GRAFANA_API_KEY" -d '{"name":"Prometheus","type":"prometheus","url":"http://localhost:9090","access":"proxy","isDefault":true}' http://localhost:3000/api/datasources

# Import Node Exporter dashboard
curl -s -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $GRAFANA_API_KEY" -d '{"dashboard":{"id":1860},"overwrite":true,"inputs":[{"name":"DS_PROMETHEUS","type":"datasource","pluginId":"prometheus","value":"Prometheus"}]}' http://localhost:3000/api/dashboards/import

# Open required ports in security group
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

aws ec2 authorize-security-group-ingress --region $REGION --group-id $(aws ec2 describe-instances --region $REGION --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' --output text) --protocol tcp --port 9090 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --region $REGION --group-id $(aws ec2 describe-instances --region $REGION --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' --output text) --protocol tcp --port 3000 --cidr 0.0.0.0/0

# Get public IP for access instructions
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

echo "=== Setup Complete ==="
echo "Prometheus is running at: http://$PUBLIC_IP:9090"
echo "Grafana is running at: http://$PUBLIC_IP:3000 (default login: admin/admin)"
echo "Node Exporter dashboard has been automatically imported"
echo "Setup completed: $(date)"