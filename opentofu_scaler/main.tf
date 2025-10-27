terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# --- VPC y subredes ---
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "assoc_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.rt.id
}

resource "aws_route_table_association" "assoc_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.rt.id
}

# --- Grupos de seguridad ---
resource "aws_security_group" "web_sg" {
  name   = "web-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db_sg" {
  name   = "db-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }

  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- Instancia de base de datos PostgreSQL ---
resource "aws_instance" "db_instance" {
  ami           = "ami-0c02fb55956c7d316"
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.db_sg.id]

  user_data = <<-EOF
    #!/bin/bash
    yum install -y docker
    service docker start
    docker run -d --name postgres \
      -e POSTGRES_USER=santiago \
      -e POSTGRES_PASSWORD=santiago \
      -e POSTGRES_DB=musiccloud \
      -p 5432:5432 \
      postgres:13
  EOF

  tags = {
    Name = "musiccloud-db"
  }
}

# --- Plantilla de lanzamiento para web ---
resource "aws_launch_template" "web_template" {
  name_prefix   = "web-template-"
  image_id      = "ami-0c02fb55956c7d316"
  instance_type = "t3.micro"

  user_data = base64encode(<<-EOF
#!/bin/bash
# Actualizamos paquetes y Docker
yum update -y
yum install -y docker
systemctl enable docker
systemctl start docker

# Esperamos unos segundos a que el daemon esté listo
sleep 10

# Ejecutamos el contenedor
docker run -d --name musiccloud-web -p 80:8000 \
  -e DATABASE_URL="postgresql://santiago:santiago@${aws_instance.db_instance.private_ip}:5432/musiccloud" \
  homura69/musiccloud-web:latest

# Guardamos logs por si falla el arranque
echo "Container status:" > /var/log/user_data.log
docker ps >> /var/log/user_data.log 2>&1
docker logs musiccloud-web >> /var/log/user_data.log 2>&1
EOF
  )

  vpc_security_group_ids = [aws_security_group.web_sg.id]
}


# --- Load Balancer ---
resource "aws_lb" "web_lb" {
  name               = "web-lb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}

resource "aws_lb_target_group" "web_tg" {
  name     = "web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

resource "aws_lb_listener" "web_listener" {
  load_balancer_arn = aws_lb.web_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}

# --- AutoScaling group para web ---
resource "aws_autoscaling_group" "web_asg" {
  desired_capacity         = 1
  max_size                 = 3
  min_size                 = 1
  vpc_zone_identifier      = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  health_check_type        = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.web_template.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.web_tg.arn]

  tag {
    key                 = "Name"
    value               = "musiccloud-web-instance"
    propagate_at_launch = true
  }
}

output "database_private_ip" {
  value = aws_instance.db_instance.private_ip
}
