#!/bin/bash

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}EKS Cluster Deployment Script${NC}"
echo "----------------------------------------"

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed. Please install it first.${NC}"
    exit 1
fi

# Check if Terraform is installed
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}Error: Terraform is not installed. Please install it first.${NC}"
    exit 1
fi

# Check if tfvars file exists
if [ ! -f "terraform.tfvars" ]; then
    echo -e "${YELLOW}terraform.tfvars file not found. Creating from example...${NC}"
    cp terraform.tfvars.example terraform.tfvars
    echo -e "${GREEN}Created terraform.tfvars. Please review and customize the variables.${NC}"
    echo -e "${YELLOW}Press Enter to continue or Ctrl+C to abort...${NC}"
    read
fi

# Initialize Terraform
echo -e "${YELLOW}Initializing Terraform...${NC}"
terraform init

# Validate Terraform configuration
echo -e "${YELLOW}Validating Terraform configuration...${NC}"
terraform validate

# Plan Terraform changes
echo -e "${YELLOW}Planning Terraform changes...${NC}"
terraform plan -out=tfplan

# Ask for confirmation
echo -e "${YELLOW}Do you want to apply these changes? (y/n)${NC}"
read -r response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    # Apply Terraform changes
    echo -e "${YELLOW}Applying Terraform changes...${NC}"
    terraform apply tfplan
    
    # Get cluster info
    CLUSTER_NAME=$(terraform output -raw cluster_name)
    REGION=$(terraform output -raw region)
    
    echo -e "${GREEN}EKS cluster ${CLUSTER_NAME} has been successfully deployed!${NC}"
    echo -e "${YELLOW}Configuring kubectl...${NC}"
    
    # Configure kubectl
    aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"
    
    echo -e "${GREEN}kubectl configured successfully!${NC}"
    echo -e "${YELLOW}Verifying deployment...${NC}"
    
    # Verify deployment
    echo -e "${YELLOW}Nodes:${NC}"
    kubectl get nodes
    
    echo -e "${YELLOW}Pods:${NC}"
    kubectl get pods -A | grep -E 'kube-system|amazon-cloudwatch'
    
    echo -e "${YELLOW}Add-ons:${NC}"
    kubectl get deployments -A | grep -E 'metrics-server|cloudwatch|cluster-autoscaler'
    
    echo -e "${GREEN}Deployment complete!${NC}"
else
    echo -e "${YELLOW}Deployment cancelled.${NC}"
    exit 0
fi