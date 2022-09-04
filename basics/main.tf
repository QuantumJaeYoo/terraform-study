# After change `terraform`, please run `terraform init -uprade`
terraform {
  required_version = ">= 1.0.0, < 2.0.0"
  required_providers {
    # Version 4.0.0 of the AWS Provider will be the last major version to
    # support EC2-Classic resources as AWS plans to fully retire
    # EC2-Classic Networking. See the AWS News Blog for additional details.
    # https://aws.amazon.com/blogs/aws/ec2-classic-is-retiring-heres-how-to-prepare/
    aws = {
      source  = "hashicorp/aws"
      version = "4.0.0"
    }
  }
}

# 2022.09.03 `terraform plan` behavior changes:
# `1 to add, 1 to update, 0 to destory` hashicorp/aws version ">4.0.0"
# `2 to add, 0 to update, 1 to destory` hashicorp/aws version "<=4.0.0"

provider "aws" {
  region = "us-east-2"
}

resource "aws_instance" "example" {
  ami = "ami-0c55b159cbfafe1f0"
  instance_type = "t2.micro"
  
  vpc_security_group_ids = [aws_security_group.instance.id]

  user_data = <<-EOF
              #!/bin/bash
              echo "Hello, World" > index.html
              nohup busybox httpd -f -p 8080 &
              EOF
  tags = {
    Name = "terraform-example"
  }
}

resource "aws_security_group" "instance" {
  name = "terraform-example-instance"

  ingress {
    from_port = 8080
    to_port = 8080
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}