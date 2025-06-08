#!/bin/bash
# Script to fix connectivity between EC2 and EKS cluster

# Get EC2 instance details
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
VPC_ID=$(aws ec2 describe-instances --region $REGION --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].VpcId' --output text)
EC2_SG_ID=$(aws ec2 describe-instances --region $REGION --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' --output text)

# Get EKS cluster details
read -p "Enter your EKS cluster name: " CLUSTER_NAME
EKS_SG_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query 'cluster.resourcesVpcConfig.securityGroupIds[0]' --output text)
CLUSTER_SG_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)

echo "EC2 Instance ID: $INSTANCE_ID"
echo "EC2 Security Group: $EC2_SG_ID"
echo "EKS Security Group: $EKS_SG_ID"
echo "EKS Cluster Security Group: $CLUSTER_SG_ID"

# Allow EC2 to access EKS cluster
echo "Adding rules to allow EC2 to access EKS cluster..."

# Allow EC2 security group to access EKS cluster security group
aws ec2 authorize-security-group-ingress --group-id $CLUSTER_SG_ID --protocol tcp --port 443 --source-group $EC2_SG_ID --region $REGION
aws ec2 authorize-security-group-ingress --group-id $EKS_SG_ID --protocol tcp --port 443 --source-group $EC2_SG_ID --region $REGION

# Allow EC2 security group to access node ports
aws ec2 authorize-security-group-ingress --group-id $CLUSTER_SG_ID --protocol tcp --port 10250 --source-group $EC2_SG_ID --region $REGION
aws ec2 authorize-security-group-ingress --group-id $EKS_SG_ID --protocol tcp --port 10250 --source-group $EC2_SG_ID --region $REGION

echo "Security group rules added. Testing connectivity..."

# Test connectivity to EKS API server
CLUSTER_ENDPOINT=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query 'cluster.endpoint' --output text)
echo "Testing connection to $CLUSTER_ENDPOINT"
curl -k $CLUSTER_ENDPOINT

echo "If you see a response above (even if it's 'Unauthorized'), connectivity is working."
echo "Now run the eks-monitoring-setup.sh script again."