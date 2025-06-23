terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
}

# Use default VPC for simplicity
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Get the latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# Security group for bastion server (MySQL client only)
resource "aws_security_group" "bastion" {
  name_prefix = "bastion-mysql-client-"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name = "bastion-mysql-client-sg"
  }
}

# Key pair for SSH access
resource "aws_key_pair" "bastion" {
  key_name   = "bastion-mysql-client-key"
  public_key = file("~/.ssh/id_rsa.pub")
}

# Bastion server EC2 instance
resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  key_name              = aws_key_pair.bastion.key_name
  subnet_id             = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.bastion.id]

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    db_host     = "project-forest-demo-db.cfmgmv0kqxfd.ap-northeast-1.rds.amazonaws.com"
    db_user     = "admin"
    db_password = "BrSUaPbcXbLW4sB"
    db_name     = "projectforest"
  }))

  tags = {
    Name = "bastion-mysql-client"
    Purpose = "Database initialization for Project Forest"
  }
}

# Output the connection information
output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}

output "ssh_command" {
  value = "ssh -i ~/.ssh/id_rsa ec2-user@${aws_instance.bastion.public_ip}"
}

output "database_init_command" {
  value = "Run './init-database.sh' on the bastion server"
}