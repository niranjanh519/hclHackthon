#Provision a VPC with public and private subnet
provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "nhhakathon" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.nhhakathon.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.nhhakathon.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.nhhakathon.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "us-east-1a"
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.nhhakathon.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.nhhakathon.id
}

resource "aws_route" "internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id            =  aws_internet_gateway.gw.id
}

#Set up an ECS cluster with Fargate launch type
resource "aws_iam_role" "ecs_task_execution_rolee" {
  name = "ecs_task_execution_rolee"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Effect    = "Allow"
        Sid       = ""
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "ecs_task_execution_policy" {
  name       = "ecs-task-execution-policy"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  roles      = [aws_iam_role.ecs_task_execution_rolee.name]
}

resource "aws_ecs_cluster" "ecs_cluster" {
  name = "ecs_cluster"
}

resource "aws_ecs_task_definition" "fargate_task" {
  family = "fargate_task"
  network_mode = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu = "256"
  memory = "512"

  container_definitions = jsonencode([
   {
    name = "my-app"
    image = "fargate:Latest"
    essential = true
    portMappings = [
     {
      containerPort = 80
      hostPort = 80
     }
    ]
   }
 ])
}

resource "aws_ecs_service" "fargate_service" {
  name = "fargate_service"
  cluster = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.fargate_task.arn
  desired_count = 1
  launch_type = "FARGATE"

  network_configuration {
  subnets = [aws_subnet.public.id]
  security_groups = [aws_security_group.security_group.id]
  assign_public_ip = true
 }
}

resource "aws_ecr_repository" "ecs-repo" {
  name = "ecs-repo"
}

#Configure necessary IAM roles and security groups
resource "aws_security_group" "security_group" {
  name        = "security_group"
  description = "Allow traffic"
  vpc_id      = aws_vpc.nhhakathon.id
}

resource "aws_security_group" "alb_security_group" {
  name        = "alb_security_group"
  description = "Allow HTTP traffic for ALB"
  vpc_id      = aws_vpc.nhhakathon.id
}

resource "aws_security_group_rule" "allow_http" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  cidr_blocks             = ["0.0.0.0/0"]
  security_group_id      = aws_security_group.security_group.id
}

#Create an Application Load Balancer
resource "aws_lb" "app_lb" {
  name               = "app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups   = [aws_security_group.security_group.id]
  subnets            = [aws_subnet.public.id, aws_subnet.public_2.id]
  enable_deletion_protection = false
}

resource "aws_lb_target_group" "app_target_group" {
  name     = "app-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.nhhakathon.id
}

resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      status_code = 200
      content_type = "text/plain"
      message_body = "Hello"
    }
  }
}
