# Project Forest Infrastructure

This directory contains Terraform configurations for deploying Project Forest to AWS.

## Architecture Overview

The infrastructure includes:
- **VPC** with public and private subnets across multiple AZs
- **Application Load Balancer** for traffic distribution
- **Auto Scaling Group** for EC2 instances running the application
- **RDS MySQL** database for data persistence
- **CloudFront** CDN for content delivery
- **S3** bucket for static assets
- **Security Groups** for network access control

## Prerequisites

1. **AWS CLI** configured with appropriate credentials
2. **Terraform** v1.0 or higher installed
3. **EC2 Key Pair** created in your target AWS region

## Quick Start

### 1. Configure Variables

```bash
# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your actual values
vim terraform.tfvars
```

Required variables:
- `key_pair_name`: Your EC2 key pair name
- `db_password`: Strong password for RDS database
- `jwt_secret`: Secure secret for JWT tokens
- `ssh_cidr_block`: Your IP address for SSH access

### 2. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the infrastructure
terraform apply
```

### 3. Access Your Application

After deployment, Terraform will output:
- **Application URL**: CloudFront distribution URL
- **Load Balancer DNS**: Direct ALB access
- **Database Endpoint**: RDS instance endpoint

## Directory Structure

```
infrastructure/terraform/
├── main.tf                 # Main Terraform configuration
├── variables.tf            # Variable definitions
├── outputs.tf              # Output definitions
├── terraform.tfvars.example # Example variables file
├── user_data.sh            # EC2 initialization script
├── modules/                # Reusable Terraform modules
│   ├── networking/         # VPC and networking resources
│   └── security/           # Security groups and IAM
└── README.md               # This file
```

## Modules

### Networking Module
- Creates VPC with configurable CIDR
- Public and private subnets across AZs
- Internet Gateway and NAT Gateway
- Route tables and associations

### Security Module
- Security groups for ALB, EC2, and RDS
- Configurable SSH access
- Application port access controls

## Configuration Options

### Environment Sizing

**Development:**
```hcl
instance_type = "t3.nano"
db_instance_class = "db.t3.micro"
min_size = 1
max_size = 1
desired_capacity = 1
```

**Production:**
```hcl
instance_type = "t3.medium"
db_instance_class = "db.t3.small"
min_size = 2
max_size = 5
desired_capacity = 2
```

### Security Configuration

- **SSH Access**: Configure `ssh_cidr_block` to your specific IP
- **Database Access**: Only from EC2 instances in the application security group
- **Load Balancer**: Open to internet (0.0.0.0/0) for HTTP/HTTPS

## Outputs

Key outputs after deployment:

```bash
# Application access
application_url = "https://d1234567890.cloudfront.net"

# Infrastructure details
alb_dns_name = "project-forest-alb-1234567890.ap-northeast-1.elb.amazonaws.com"
vpc_id = "vpc-1234567890abcdef0"
rds_endpoint = "project-forest-db.cluster-xyz.ap-northeast-1.rds.amazonaws.com"

# S3 bucket for assets
s3_bucket_name = "project-forest-assets-12345678"
```

## Management Commands

### Scaling the Application

```bash
# Update desired capacity
terraform apply -var="desired_capacity=3"
```

### Updating the Application

1. Build new AMI with updated application code
2. Update `ami_id` variable
3. Apply changes: `terraform apply`

### Database Management

- Access via EC2 bastion host or VPN
- Use RDS endpoint from Terraform outputs
- Backup retention: 7 days (configurable)

## Monitoring and Logs

### CloudWatch Integration
- EC2 metrics automatically collected
- Application logs sent to CloudWatch Logs
- Custom metrics namespace: `ProjectForest/EC2`

### Log Locations
- Application logs: `/var/log/project-forest/`
- System logs: CloudWatch Logs group `/aws/ec2/project-forest`

## Security Best Practices

1. **Network Security**
   - Private subnets for application and database
   - Security groups with minimal required access
   - VPC endpoints for AWS services (recommended)

2. **Database Security**
   - Encryption at rest enabled
   - Automated backups configured
   - No public access

3. **Application Security**
   - SSL/TLS termination at CloudFront
   - Security headers configured
   - Environment variables for secrets

## Cost Optimization

### Cost-Saving Options
- Use t3.micro instances for development
- Single AZ deployment for non-production
- Spot instances for non-critical workloads
- S3 lifecycle policies for old assets

### Estimated Monthly Costs (us-east-1)
- **Development**: ~$50-80/month
- **Production**: ~$200-400/month

## Troubleshooting

### Common Issues

1. **Deployment Fails**
   - Check AWS credentials and permissions
   - Verify key pair exists in target region
   - Ensure unique S3 bucket names

2. **Application Not Accessible**
   - Check security group rules
   - Verify auto scaling group instances are healthy
   - Review CloudWatch logs for application errors

3. **Database Connection Issues**
   - Confirm RDS security group allows EC2 access
   - Check database credentials in user data script
   - Verify database is in available state

### Useful Commands

```bash
# Check infrastructure status
terraform show

# View specific resource
terraform state show aws_instance.example

# Force recreation of launch template
terraform taint aws_launch_template.main

# Import existing resources
terraform import aws_instance.example i-1234567890abcdef0
```

## Cleanup

To destroy the infrastructure:

```bash
# Plan destruction
terraform plan -destroy

# Destroy infrastructure
terraform destroy
```

**Warning**: This will permanently delete all resources and data. Ensure you have backups if needed.

## Support

For infrastructure issues:
1. Check Terraform documentation
2. Review AWS service status
3. Consult CloudWatch logs and metrics
4. Contact AWS support if needed