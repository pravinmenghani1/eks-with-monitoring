# Grafana Dashboards for EKS Monitoring

After setting up Prometheus and Grafana, import these dashboards for monitoring your EKS cluster.

## Recommended Dashboards (In Order of Reliability)

| Dashboard ID | Name | Description | Works With Limited Setup |
|-------------|------|-------------|-------------------------|
| 1860 | Node Exporter Full | Detailed metrics for your EC2 monitoring instance | ✅ Yes |
| 10856 | Node Exporter Full (Simplified) | Simplified version with better performance | ✅ Yes |
| 3662 | Prometheus 2.0 Overview | Basic Prometheus metrics | ✅ Yes |
| 8588 | Kubernetes API Server | Basic Kubernetes API metrics | ⚠️ Partial |
| 315 | Kubernetes Cluster Overview | High-level overview of your entire Kubernetes cluster | ❌ Requires additional setup |
| 7249 | Kubernetes Nodes | Focused view on node metrics | ❌ Requires additional setup |
| 6417 | Kubernetes Pod Resources | Detailed metrics for pods | ❌ Requires additional setup |

## How to Import Dashboards

1. Access your Grafana instance at http://<EC2-IP>:3000
2. Log in with your credentials (default: admin/admin)
3. Click on the "+" icon in the left sidebar
4. Select "Import"
5. Enter the dashboard ID in the "Import via grafana.com" field
6. Click "Load"
7. Select your Prometheus data source from the dropdown
8. Click "Import"

## For Complete EKS Monitoring

To get full EKS cluster monitoring (pods, nodes, etc.), you'll need to:

1. Deploy node-exporter as a DaemonSet on your EKS cluster:
   ```bash
   kubectl apply -f node-exporter.yaml
   ```

2. Configure security groups to allow traffic from your EC2 to EKS nodes on port 9100

3. Update your Prometheus configuration to include EKS node IPs:
   ```bash
   # Get node IPs
   NODE_IPS=$(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')
   NODE_IPS_FORMATTED=$(echo $NODE_IPS | sed 's/ /:9100,/g'):9100
   
   # Update Prometheus config
   cat > /etc/prometheus/prometheus.yml << EOF
   global:
     scrape_interval: 15s
   
   scrape_configs:
     - job_name: 'prometheus'
       static_configs:
         - targets: ['localhost:9090']
     
     - job_name: 'node'
       static_configs:
         - targets: ['localhost:9100']
         
     - job_name: 'kubernetes-nodes'
       static_configs:
         - targets: [${NODE_IPS_FORMATTED}]
   EOF
   
   sudo systemctl restart prometheus
   ```

4. For advanced monitoring, consider using Amazon Managed Service for Prometheus and Amazon Managed Grafana, which integrate seamlessly with EKS.

## Troubleshooting Dashboard Issues

If dashboards show "N/A" or no data:

1. Check if Prometheus is collecting metrics:
   ```bash
   curl -s http://localhost:9090/api/v1/query?query=up | grep -q '"value":\[.*,1\]' && echo "Prometheus is collecting metrics" || echo "No metrics collected"
   ```

2. Verify which metrics are available:
   ```bash
   curl -s http://localhost:9090/api/v1/label/__name__/values | grep -o '"[^"]*"' | sort
   ```

3. Try creating a simple custom dashboard with metrics you know exist