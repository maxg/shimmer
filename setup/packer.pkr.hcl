variable "aws_access_key" { type = string }
variable "aws_secret_key" { type = string }
variable "aws_instance_type" { type = string }
variable "rev" { type = string }
variable "tar" { type = string }
variable "app" { type = string }

packer {
  required_plugins {
    amazon = {
      source = "github.com/hashicorp/amazon"
      version = "~> 1"
    }
  }
}

source "amazon-ebs" "web" {
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  region = "us-east-1"
  ami_name = "${var.app}-${formatdate("YYMMDDhhmm", timestamp())}-${var.rev}"
  tags = {
    Name = "${var.app} ${formatdate("YYMMDDhhmm", timestamp())} ${var.rev}"
    Packer = var.app
    Packer_Source = "{{ .SourceAMI }}"
  }
  source_ami_filter {
    filters = {
      name = "al2023-ami-2023.*"
      architecture = "x86_64"
    }
    owners = [ "amazon" ]
    most_recent = true
  }
  instance_type = var.aws_instance_type
  ssh_username = "ec2-user"
}

build {
  sources = [ "sources.amazon-ebs.web" ]
  provisioner "file" {
    source = var.tar
    destination = "/tmp/${var.app}.tar"
  }
  provisioner "file" {
    source = "config/config.sh"
    destination = "/tmp/config.sh"
  }
  provisioner "shell" {
    script = "setup/production-pack.sh"
    env = {
      APP = var.app
    }
    execute_command = "{{ .Vars }} ADMIN=`whoami` sudo -E sh -c {{ .Path }}"
  }
}
