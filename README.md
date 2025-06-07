# EKS Cluster with Add-ons

This Terraform project deploys an Amazon EKS cluster with the following add-ons:

- VPC CNI
- CoreDNS
- kube-proxy
- Metrics Server
- CloudWatch Agent
- CloudWatch Observability
- EKS Pod Identity Agent
- AWS EBS CSI Driver
- Cluster Autoscaler

## Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.0.0
- kubectl
- helm

## Deployment Instructions

1. Clone this repository:
   ```
   git clone <repository-url>
   cd eks-cluster
   ```

2. Create a `terraform.tfvars` file based on the example:
   ```
   cp terraform.tfvars.example terraform.tfvars
   ```

3. Edit `terraform.tfvars` to customize your deployment.

4. Initialize Terraform:
   ```
   terraform init
   ```

5. Plan the deployment:
   ```
   terraform plan
   ```

6. Apply the configuration:
   ```
   terraform apply
   ```

7. Configure kubectl to connect to your cluster:
   ```
   aws eks update-kubeconfig --region $(terraform output -raw region) --name $(terraform output -raw cluster_name)
   ```

8. Verify the deployment:
   ```
   kubectl get nodes
   kubectl get pods -A
   ```

## Add-ons Included

- **VPC CNI**: Provides networking for pods
- **CoreDNS**: DNS server for Kubernetes
- **kube-proxy**: Maintains network rules on nodes
- **Metrics Server**: Collects resource metrics from Kubelets
- **CloudWatch Agent**: Sends logs and metrics to CloudWatch
- **CloudWatch Observability**: Enhanced monitoring for EKS
- **EKS Pod Identity Agent**: Simplifies IAM permissions for pods
- **AWS EBS CSI Driver**: Manages EBS volumes for persistent storage
- **Cluster Autoscaler**: Automatically adjusts node count based on demand

## Customization

Edit the `terraform.tfvars` file to customize:

- AWS region
- Cluster name and version
- VPC and subnet configuration
- Node group size and instance types
- Add-on versions

## Cleanup

To destroy all resources:

```
terraform destroy
```

## Security Considerations

- The cluster has public endpoint access enabled for easier management
- Consider restricting CIDR blocks for the public endpoint in production
- Review IAM permissions and implement least privilege access