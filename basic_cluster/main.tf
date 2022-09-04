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

resource "aws_launch_configuration" "example" {
  image_id = "ami-0c55b159cbfafe1f0"
  instance_type = "t2.micro"
  security_groups = [aws_security_group.instance.id]

  user_data = <<-EOF
              #!/bin/bash
              echo "Hello, World" > index.html
              nohup busybox httpd -f -p ${var.server_port} &
              EOF
  
  # This is for auto-scaling group
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "instance" {
  name = "terraform-example-instance"

  ingress {
    from_port = var.server_port
    to_port = var.server_port
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_vpc" "default" {
  default = true
}

# 2022.09.04 `aws_subnet_ids` has been deprecated. Use `aws_subnets` instead.
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnets
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# This name is used in:
# - aws_autoscaling_group.tag.vale with key = "Name"
# - aws_lb.name
# - aws_lb_target_group.name
variable alb_name {
  description = "The name of the security group for Application Load Balancer"
  type = string
  default = "terraform-asg-example"
}

resource "aws_autoscaling_group" "example" {
  launch_configuration = aws_launch_configuration.example.name
  vpc_zone_identifier = data.aws_subnets.default.ids

  target_group_arns = [aws_lb_target_group.asg.arn]
  health_check_type = "ELB"  # default is EC2.
  
  min_size = 2
  max_size = 10

  tag {
    key ="Name"
    value = var.alb_name
    propagate_at_launch = true
  }
}

variable "server_port" {
  description = "The port the server will use for HTTP response"
  default = 8080
  type = number
}

# Here are the resources for Elastic Load Balancer
resource "aws_lb" "example" {
  name = var.alb_name
  load_balancer_type = "application"  #ALB
  subnets = data.aws_subnets.default.ids
  security_groups = [aws_security_group.alb.id]
}

resource "aws_lb_listener" "http" {  # Interestingly, it's protocol name.
  load_balancer_arn = aws_lb.example.arn
  port = var.lb_port
  protocol = "HTTP"

  # By default, return a simple 404 page.

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code = 404
    }
  }
}

variable "lb_port" {
  description = "The port that Load Balancer uses to forward the requests from users to clusters"
  type = number
  default = 80
}

# Application Load Balancer specific Security setting.
resource "aws_security_group" "alb" {
  name = "terraform-example-alb"

  # Allow all inbound HTTP requests.
  ingress {
    from_port = var.lb_port
    to_port = var.lb_port
    cidr_blocks = ["0.0.0.0/0"]
    protocol = "tcp"
  }

  # Allow all inbound HTTP requests.
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1" # all?
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb_target_group" "asg" { # name is not example, but asg. why?
  name = var.alb_name
  port = var.server_port
  protocol = "HTTP"
  vpc_id = data.aws_vpc.default.id

  health_check {
    path = "/"
    protocol = "HTTP"    
    matcher = "200"
    interval = 15
    timeout = 3
    healthy_threshold = 2
    unhealthy_threshold = 2
  }
}

# Sends requests that match any path to the target group that contains my ASG.
resource "aws_lb_listener_rule" "asg" {
  listener_arn = aws_lb_listener.http.arn
  priority = 100

  condition {
    path_pattern {
      values = ["*"] # any path
    }
  }

  action {
    type = "forward"
    target_group_arn = aws_lb_target_group.asg.arn
  }
}

# The last thing for Autoscaling Group.
output "alb_dns_name" {
  value = aws_lb.example.dns_name
  description = "The domain name of the load balancer"
}