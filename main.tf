# launch an ec2 instance
# Which cloud provider - aws
# terraform downloads required dependencies
# terraform init

# provider name
provider "aws"{
       # which part of the aws: Ireland
       region = "eu-west-1"  
}

# create vpc
resource "aws_vpc" "tech241-parichat-vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "tech241-parichat-vpc"
  }  
}

# internet gateway
resource "aws_internet_gateway" "tech241-parichat-igw" {
  vpc_id = aws_vpc.tech241-parichat-vpc.id

  tags = {
    Name = "tech241-parichat-igw"
  }  
}

# create a public subnet
resource "aws_subnet" "public-subnet" {
  vpc_id = aws_vpc.tech241-parichat-vpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "eu-west-1a"
  tags = {
    Name = "public-subnet"
  }  
}

# create a private subnet
resource "aws_subnet" "private-subnet" {
  vpc_id = aws_vpc.tech241-parichat-vpc.id
  cidr_block = "10.0.3.0/24"
  availability_zone = "eu-west-1b"
  tags = {
    Name = "private-subnet"
  }  
}

# create route table
resource "aws_route_table" "tech241-parichat-public-rt" {
  vpc_id = aws_vpc.tech241-parichat-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.tech241-parichat-igw.id
  }

  tags = {
    Name: "tech241-parichat-public-rt"
  }  
}

resource "aws_route_table_association" "my_route_table_association" {
  subnet_id = aws_subnet.public-subnet.id
  route_table_id = aws_route_table.tech241-parichat-public-rt.id
}


# create security groups
resource "aws_security_group" "tech241-parichat-sg-ssh-http-3000" {
  vpc_id = aws_vpc.tech241-parichat-vpc.id

  # allow ssh
  ingress {
    description = "SSH access"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  } 

  # allow http
  ingress {
    description = "HTTP access"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  } 

  # allow 3000
  ingress {
    description = "Port 3000 access"
    from_port = 3000
    to_port = 3000
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port = 0
    to_port = 0
    # all protocol
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"] 
  }
}


# Launch an ec2 in ireland
resource "aws_instance" "app_instance" {

# key pair
  key_name = var.aws_key_name

# which machine/os version etc..: AMI-id
  ami = var.webapp_ami_id

# security group
  vpc_security_group_ids = [aws_security_group.tech241-parichat-sg-ssh-http-3000.id]
  subnet_id = aws_subnet.public-subnet.id

# what type of instance: t2 micro
  instance_type = var.ec2_type

# is the public id required
  associate_public_ip_address = true  

# what would you like to name it? tech241-parichat-terraform-app
  tags = {
       Name = "tech241-parichat-terraform-app"
  }

}

# Template for autoscaling Group
resource "aws_launch_template" "tech241-parichat-temp-asg" {
  name_prefix = "tech241-parichat-temp-asg"
  image_id = var.webapp_ami_id
  instance_type = var.ec2_type
  vpc_security_group_ids = [aws_security_group.tech241-parichat-sg-ssh-http-3000.id]
  key_name = var.aws_key_name

  user_data = base64encode(<<-EOT
              #!/bin/bash

              # env variable
              # export DB_HOST=mongodb://172.31.34.136:27017/posts

              # go into the app folder
              cd app/app

              # install npm - install the nodejs code/ downloads required dependencies for nodejs, also check for DB_HOST, if it exists itll try to connect, it non exists, it wont set up posts page  
              npm install

              # seed database
              echo "Clearing and seeding database.."
              node seeds/seed.js
              echo " --> Done!"

              # run sparta node app in the background
              pm2 start app.js
              EOT
  )
}


# Autoscaling group
resource "aws_autoscaling_group" "tech241-parichat-asg" {
  name = "tech241-parichat-asg"

  launch_template {
    id      = aws_launch_template.tech241-parichat-temp-asg.id
    version = "$Latest"
  }

  vpc_zone_identifier     = [aws_subnet.public-subnet.id]
  min_size                = 2
  max_size                = 3
  desired_capacity        = 2
  health_check_grace_period = 300
  health_check_type       = "EC2"

}


# Create NSG for application load balancer
resource "aws_security_group" "tech241-parichat-alb-sg" {
  name = "tech241-parichat-alb-sg"

  # Inbound rules
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 433
    to_port     = 433
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound rule
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # Associate the sg with vpc
  vpc_id = aws_vpc.tech241-parichat-vpc.id

  tags = {
    Name = "tech241-parichat-alb-sg"
  }  
}

# Create Application Load balancer
resource "aws_lb" "tech241-parichat-lb" {
  name = "tech241-parichat-lb"
  internal = false
  load_balancer_type = "application"
  subnets = [
    aws_subnet.public-subnet.id,    # eu-west-a1
    aws_subnet.private-subnet.id,   # eu-west-b1
  ]

  security_groups = [aws_security_group.tech241-parichat-alb-sg.id]

  tags = {
    Name = "tech241-parichat-lb"
  }
}

# create target group for application load balancer
resource "aws_lb_target_group" "tech241-parichat-target-group" {
  name = "tech241-parichat-tg"
  port = 80
  protocol = "HTTP"
  vpc_id = aws_vpc.tech241-parichat-vpc.id
}

# Attach target group to auto scaling group
resource "aws_autoscaling_attachment" "tech241-parichat-asg-attachment" {
  autoscaling_group_name = aws_autoscaling_group.tech241-parichat-asg.name
  lb_target_group_arn = aws_lb_target_group.tech241-parichat-target-group.arn
}

# cloudwatch monitoring for asg
resource "aws_cloudwatch_metric_alarm" "tech241-asg-alarm" {
  alarm_name = "tech241-parichat-asg-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods = "2"
  metric_name = "GroupDesiredCapacity"
  namespace = "AWS/Autoscaling"
  period = "120"
  statistic = "Average"
  threshold = "2"
  alarm_description = "The checks if the desired capacity of the asg is greater than or equal to 2 for two consecutive periods of 2 minutes"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.tech241-parichat-asg.name
  }

}

# Create Simple Notification Service (SNS)
resource "aws_sns_topic" "tech241-parichat-sns-topic" {
  name = "tech241-parichat-sns-topic"
}

# Alert by email
resource "aws_sns_topic_subscription" "tech241-parichat-sns-sub" {
  topic_arn = aws_sns_topic.tech241-parichat-sns-topic.arn
  protocol = "email"
  endpoint = "parichanket@gmail.com"
}