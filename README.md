# EKS with Monitoring

This project sets up an Amazon EKS cluster with integrated monitoring using Prometheus and Grafana.

## Features

- EKS cluster with Amazon Linux 2023 nodes
- Kubernetes version 1.33
- Prometheus and Grafana monitoring
- Automatic monitoring instance deployment
- Complete metrics collection from EKS cluster

## Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform installed (version >= 1.0.0)
- An EC2 key pair for SSH access to the monitoring instance

## Quick Start

1. Clone this repository:
   ```
   git clone https://github.com/pravinmenghani1/eks-with-monitoring.git
   cd eks-with-monitoring
   ```

2. Update `terraform.tfvars` with your settings:
   ```
   region         = "us-west-2"
   cluster_name   = "eks-production"
   key_name       = "your-key-pair-name"  # Add your EC2 key pair name
   ```

3. Initialize and apply Terraform:
   ```
   terraform init
   terraform apply
   ```

4. After deployment completes, access your monitoring tools:
   - Prometheus: http://[monitoring-instance-public-ip]:9090
   - Grafana: http://[monitoring-instance-public-ip]:3000 (default login: admin/admin)

## Architecture

- **EKS Cluster**: Runs with Kubernetes 1.33 on Amazon Linux 2023 nodes
- **Monitoring Instance**: t2.micro EC2 instance with Amazon Linux 2023
- **Prometheus**: Collects metrics from the EKS cluster
- **Grafana**: Visualizes the metrics with dashboards

## Networking

The monitoring instance is deployed in the same VPC and subnet as the EKS cluster to ensure proper connectivity. Security groups are automatically configured to allow traffic between the monitoring instance and the EKS cluster.

## Troubleshooting

If you encounter connectivity issues between the monitoring instance and the EKS cluster:

1. SSH into the monitoring instance:
   ```
   ssh -i your-key.pem ec2-user@[monitoring-instance-public-ip]
   ```

2. Test connectivity to the EKS API server:
   ```
   kubectl get nodes
   ```

3. Check Prometheus targets:
   ```
   curl http://localhost:9090/api/v1/targets
   ```

## Cleanup

To delete all resources:
```
terraform destroy
```