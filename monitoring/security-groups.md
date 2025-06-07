# Security Group Configuration for EKS Monitoring

To ensure proper communication between your monitoring EC2 instance and the EKS cluster, you need to configure security groups correctly.

## Monitoring EC2 Instance Security Group

Create a security group for your monitoring EC2 instance with these rules:

### Inbound Rules

| Type | Protocol | Port Range | Source | Description |
|------|----------|------------|--------|-------------|
| SSH | TCP | 22 | Your IP | SSH access |
| Custom TCP | TCP | 9090 | Your IP | Prometheus UI access |
| Custom TCP | TCP | 3000 | Your IP | Grafana UI access |

### Outbound Rules

| Type | Protocol | Port Range | Destination | Description |
|------|----------|------------|-------------|-------------|
| All traffic | All | All | 0.0.0.0/0 | Allow all outbound traffic |

## EKS Cluster Security Group Modifications

Modify the EKS cluster security group to allow traffic from the monitoring EC2 instance:

### Inbound Rules to Add

| Type | Protocol | Port Range | Source | Description |
|------|----------|------------|--------|-------------|
| Custom TCP | TCP | 9100 | Monitoring EC2 Security Group | Node Exporter metrics |
| Custom TCP | TCP | 443 | Monitoring EC2 Security Group | Kubernetes API access |

## How to Configure Security Groups

### Using AWS Console

1. Go to EC2 > Security Groups
2. Create a new security group for the monitoring instance
3. Add the inbound and outbound rules as specified above
4. Find the EKS cluster security group (check the EKS console for the security group ID)
5. Add the necessary inbound rules to the EKS security group

### Using AWS CLI

For the monitoring EC2 instance:

```bash
# Create security group for monitoring instance
aws ec2 create-security-group \
  --group-name eks-monitoring-sg \
  --description "Security group for EKS monitoring" \
  --vpc-id YOUR_VPC_ID

# Add inbound rules
aws ec2 authorize-security-group-ingress \
  --group-id MONITORING_SG_ID \
  --protocol tcp \
  --port 22 \
  --cidr YOUR_IP/32

aws ec2 authorize-security-group-ingress \
  --group-id MONITORING_SG_ID \
  --protocol tcp \
  --port 9090 \
  --cidr YOUR_IP/32

aws ec2 authorize-security-group-ingress \
  --group-id MONITORING_SG_ID \
  --protocol tcp \
  --port 3000 \
  --cidr YOUR_IP/32
```

For the EKS cluster security group:

```bash
# Add inbound rules to EKS security group
aws ec2 authorize-security-group-ingress \
  --group-id EKS_SG_ID \
  --protocol tcp \
  --port 9100 \
  --source-group MONITORING_SG_ID

aws ec2 authorize-security-group-ingress \
  --group-id EKS_SG_ID \
  --protocol tcp \
  --port 443 \
  --source-group MONITORING_SG_ID
```

## Verifying Connectivity

After configuring security groups, verify connectivity:

```bash
# From the monitoring EC2 instance
# Test connection to Kubernetes API
curl -k https://EKS_API_ENDPOINT

# Test connection to node-exporter on one of the nodes
curl http://NODE_IP:9100/metrics
```

If these commands return data, your security group configuration is correct.