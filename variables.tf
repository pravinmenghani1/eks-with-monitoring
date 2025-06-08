variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "eks-production"
}

variable "cluster_version" {
  description = "Kubernetes version to use for the EKS cluster"
  type        = string
  default     = "1.33"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

variable "private_subnets" {
  description = "List of private subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "public_subnets" {
  description = "List of public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
}

variable "instance_types" {
  description = "List of instance types for the EKS managed node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "min_size" {
  description = "Minimum size of the EKS managed node group"
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Maximum size of the EKS managed node group"
  type        = number
  default     = 5
}

variable "desired_size" {
  description = "Desired size of the EKS managed node group"
  type        = number
  default     = 3
}

variable "capacity_type" {
  description = "Capacity type for the EKS managed node group (ON_DEMAND or SPOT)"
  type        = string
  default     = "ON_DEMAND"
}

variable "disk_size" {
  description = "Disk size in GiB for worker nodes"
  type        = number
  default     = 50
}

variable "key_name" {
  description = "Name of the EC2 key pair to use for the monitoring instance"
  type        = string
  default     = ""
}

variable "metrics_server_version" {
  description = "Version of metrics-server Helm chart"
  type        = string
  default     = "3.11.0"
}

variable "cloudwatch_agent_version" {
  description = "Version of CloudWatch agent Helm chart"
  type        = string
  default     = "0.0.9"
}

variable "cluster_autoscaler_version" {
  description = "Version of cluster-autoscaler Helm chart"
  type        = string
  default     = "9.29.0"
}