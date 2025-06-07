# Simple EKS Monitoring Setup

This guide provides a simplified approach to monitoring your EKS cluster using Prometheus and Grafana, based on our troubleshooting experience.

## Quick Start

1. Launch an EC2 instance in the same VPC as your EKS cluster
2. Copy the `simple-eks-monitoring.sh` script to the EC2 instance
3. Run the script:
   ```bash
   chmod +x simple-eks-monitoring.sh
   ./simple-eks-monitoring.sh
   ```
4. Access Grafana at http://<EC2-IP>:3000 (default login: admin/admin)
5. Add Prometheus as a data source (URL: http://localhost:9090)
6. Import dashboard ID 1860 (Node Exporter Full)

## What This Setup Provides

- Monitoring of the EC2 instance itself (CPU, memory, disk, network)
- Basic Prometheus metrics
- Foundation for EKS monitoring

## Expanding to Full EKS Monitoring

After the basic setup is working, you can expand to full EKS monitoring:

1. Make sure security groups allow traffic from your EC2 to EKS nodes on port 9100

2. Update your Prometheus configuration:
   ```bash
   sudo bash -c "cat > /etc/prometheus/prometheus.yml << EOF
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
   EOF"
   
   sudo systemctl restart prometheus
   ```

3. Import additional dashboards in Grafana:
   - Dashboard ID 10856 (Node Exporter Full - Simplified)
   - Dashboard ID 8588 (Kubernetes API Server)

## Troubleshooting

If you encounter issues:

1. Check if Prometheus is running:
   ```bash
   sudo systemctl status prometheus
   ```

2. Verify Prometheus is collecting metrics:
   ```bash
   curl -s http://localhost:9090/api/v1/query?query=up | grep -q '"value":\[.*,1\]' && echo "Prometheus is collecting metrics" || echo "No metrics collected"
   ```

3. Check which metrics are available:
   ```bash
   curl -s http://localhost:9090/api/v1/label/__name__/values | grep -o '"[^"]*"' | sort
   ```

4. If dashboards show "N/A", try creating a simple custom dashboard with metrics you know exist

## Security Considerations

- The EC2 instance should be in the same VPC as your EKS cluster
- Configure security groups to allow only necessary traffic
- Consider using IAM roles instead of direct AWS credentials
- For production environments, consider Amazon Managed Service for Prometheus and Amazon Managed Grafana

## Alternative: Using AWS Managed Services

For a fully managed solution:

1. Set up Amazon Managed Service for Prometheus
2. Configure Amazon Managed Grafana
3. Use the AWS-provided integration for EKS monitoring

This approach requires less maintenance and provides better integration with AWS services.