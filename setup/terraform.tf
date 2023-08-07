variable "bucket" {}
variable "key" {}
variable "region" {}
variable "access_key" {}
variable "secret_key" {}

# terraform init -backend-config=terraform.tfvars
terraform {
  required_version = "~> 1.5"
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
  backend "s3" {}
}

locals {
  app = var.key
}

provider "aws" {
  access_key = var.access_key
  secret_key = var.secret_key
  region = var.region
}

data "aws_ami" "web" {
  most_recent = true
  filter {
    name = "name"
    values = ["${local.app}-*"]
  }
  owners = ["self"]
}

resource "aws_vpc" "default" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = {
    Name = "${local.app}-vpc"
    Terraform = local.app
  }
}

resource "aws_internet_gateway" "default" {
  vpc_id = aws_vpc.default.id
  tags = {
    Name = "${local.app}-gateway"
    Terraform = local.app
  }
}

resource "aws_route" "internet_access" {
  route_table_id = aws_vpc.default.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.default.id
}

resource "aws_subnet" "a" {
  vpc_id = aws_vpc.default.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "${var.region}a"
  depends_on = [aws_route.internet_access]
  tags = {
    Name = "${local.app}-1"
    Terraform = local.app
  }
}

resource "aws_subnet" "c" {
  vpc_id = aws_vpc.default.id
  cidr_block = "10.0.3.0/24"
  availability_zone = "${var.region}a"
  tags = {
    Name = "${local.app}-3"
    Terraform = local.app
  }
}

resource "aws_security_group" "nfs" {
  name = "${local.app}-security-nfs"
  vpc_id = aws_vpc.default.id
  tags = {
    Terraform = local.app
  }
  
  ingress {
    from_port = 2049
    to_port = 2049
    protocol = "tcp"
    security_groups = [aws_security_group.web.id]
  }
  
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    security_groups = [aws_security_group.web.id]
  }
}

resource "aws_efs_file_system" "tls" {
  tags = {
    Name = "${local.app}-tls"
    Terraform = local.app
  }
}

resource "aws_efs_mount_target" "tls" {
  file_system_id = aws_efs_file_system.tls.id
  subnet_id = aws_subnet.c.id
  security_groups = [aws_security_group.nfs.id]
}

data "aws_ssm_parameter" "admin_cidr_blocks" {
  name = "/${var.bucket}/admin-cidr-blocks"
}

resource "aws_security_group" "web" {
  name = "${local.app}-security-web"
  vpc_id = aws_vpc.default.id
  tags = {
    Terraform = local.app
  }
  
  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = split(",", data.aws_ssm_parameter.admin_cidr_blocks.value)
  }
  
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_key_pair" "app" {
  key_name = local.app
  public_key = file("~/.ssh/aws_${local.app}.pub")
}

resource "aws_instance" "web" {
  instance_type = "t3a.micro"
  ami = data.aws_ami.web.id
  vpc_security_group_ids = [aws_security_group.web.id]
  subnet_id = aws_subnet.a.id
  associate_public_ip_address = true
  key_name = aws_key_pair.app.id
  root_block_device {
    volume_type = "gp2"
    delete_on_termination = false
  }
  iam_instance_profile = aws_iam_instance_profile.web.name
  user_data = data.template_cloudinit_config.config_web.rendered
  tags = {
    Name = local.app
    Terraform = local.app
  }
  volume_tags = {
    Name = local.app
    Terraform = local.app
  }
  connection {
    type = "ssh"
    host = self.public_ip
    user = "ec2-user"
    private_key = file("~/.ssh/aws_${local.app}")
  }
  provisioner "file" {
    source = "../config/"
    destination = "/var/${local.app}/config"
  }
  lifecycle {
    create_before_destroy = true
    ignore_changes = [tags]
  }
}

data "aws_iam_policy_document" "assume_role_ec2" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "web" {
  name = "${local.app}-web-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role_ec2.json
}

data "aws_iam_policy_document" "web_access" {
  statement {
    actions = ["ec2:CreateTags"]
    resources = ["arn:aws:ec2:${var.region}:*:instance/*"]
  }
  statement {
    actions = [
      "logs:PutLogEvents", "logs:DescribeLogStreams", "logs:DescribeLogGroups", "logs:CreateLogStream", "logs:CreateLogGroup"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "web" {
  name = "${local.app}-web-access"
  role = aws_iam_role.web.id
  policy = data.aws_iam_policy_document.web_access.json
}

resource "aws_iam_instance_profile" "web" {
  name = "${local.app}-web-profile"
  role = aws_iam_role.web.name
  depends_on = [aws_iam_role_policy.web]
}

resource "aws_eip_association" "web_address" {
  instance_id = aws_instance.web.id
  allocation_id = aws_eip.web.id
  lifecycle { create_before_destroy = true }
}

resource "aws_eip" "web" {
  domain = "vpc"
  tags = {
    Name = local.app
    Terraform = local.app
  }
}

data "template_cloudinit_config" "config_web" {
  part {
    content_type = "text/cloud-config"
    content = <<-EOF
      runcmd:
      - AWS_DEFAULT_REGION=${var.region}
        TLS_FS=${aws_efs_mount_target.tls.file_system_id}
        bash /var/${local.app}/setup/production-provision.sh
    EOF
  }
}

output "web-address" { value = aws_eip_association.web_address.public_ip }
