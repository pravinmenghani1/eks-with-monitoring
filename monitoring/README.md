# EC2 Monitoring Setup with Prometheus and Grafana

This directory contains scripts to set up monitoring for EC2 instances using Prometheus and Grafana.

## Quick Start: EC2 User Data Setup

The `ec2-monitoring-userdata.sh` script is designed to be used as EC2 User Data when launching a new instance. This provides a zero-touch setup of monitoring.

### How to use as EC2 User Data:

1. Launch a new EC2 instance
2. In the "Advanced details" section, find "User data"
3. Copy the entire contents of `ec2-monitoring-userdata.sh` into the User data field
4. Launch the instance

The script will automatically:
- Install Prometheus, Node Exporter, and Grafana
- Configure all services to start automatically
- Set up Prometheus to monitor itself and the local Node Exporter
- Configure Grafana with Prometheus as a data source
- Import the Node Exporter dashboard
- Open the required ports in the security group
- Output access URLs when complete

### Access your monitoring:

- **Prometheus**: http://your-ec2-public-ip:9090
- **Grafana**: http://your-ec2-public-ip:3000 (default login: admin/admin)

## Manual Installation

If you prefer to install manually on an existing EC2 instance:

1. SSH into your EC2 instance
2. Download the script:
   ```
   wget https://raw.githubusercontent.com/pravinmenghani1/eks-with-monitoring/main/monitoring/ec2-monitoring-userdata.sh
   ```
3. Make it executable:
   ```
   chmod +x ec2-monitoring-userdata.sh
   ```
4. Run the script:
   ```
   sudo ./ec2-monitoring-userdata.sh
   ```

## Security Considerations

- The script opens ports 9090 (Prometheus) and 3000 (Grafana) to all IPs (0.0.0.0/0)
- For production use, restrict these ports to specific IP ranges
- Change the default Grafana admin password after installation

## Troubleshooting

Check the installation log:
```
cat /var/log/user-data.log
```

Check service status:
```
sudo systemctl status prometheus
sudo systemctl status node_exporter
sudo systemctl status grafana-server
```
