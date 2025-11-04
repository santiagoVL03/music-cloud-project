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
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "k8s-vpc"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "k8s-public-subnet-a"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "k8s-igw"
  }
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "k8s-route-table"
  }
}

resource "aws_route_table_association" "assoc_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.rt.id
}

# --- Security Group para Kubernetes ---
resource "aws_security_group" "k8s_sg" {
  name        = "k8s-cluster-sg"
  description = "Security group for Kubernetes cluster"
  vpc_id      = aws_vpc.main.id

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access"
  }

  # Kubernetes API Server
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Kubernetes API Server"
  }

  # NodePort Services (30000-32767)
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "NodePort Services"
  }

  # HTTP/HTTPS para aplicaciones
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS"
  }

  # All traffic within VPC (para comunicación entre nodos)
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Internal cluster communication"
  }

  # Permitir todo el tráfico saliente
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "k8s-cluster-sg"
  }
}

# --- S3 Bucket para compartir el token de join ---
resource "aws_s3_bucket" "k8s_token_bucket" {
  bucket_prefix = "k8s-join-token-"
  force_destroy = true

  tags = {
    Name = "k8s-join-token-bucket"
  }
}

resource "aws_s3_bucket_public_access_block" "k8s_token_bucket_pab" {
  bucket = aws_s3_bucket.k8s_token_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# --- IAM Role para las instancias EC2 ---
resource "aws_iam_role" "k8s_node_role" {
  name = "k8s-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "k8s_node_policy" {
  name = "k8s-node-policy"
  role = aws_iam_role.k8s_node_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.k8s_token_bucket.arn,
          "${aws_s3_bucket.k8s_token_bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "k8s_node_profile" {
  name = "k8s-node-profile"
  role = aws_iam_role.k8s_node_role.name
}

# --- Key Pair para acceso SSH ---
resource "aws_key_pair" "k8s_key" {
  key_name   = "k8s-cluster-key"
  public_key = var.ssh_public_key

  tags = {
    Name = "k8s-cluster-key"
  }
}

# --- Nodo Master de Kubernetes ---
resource "aws_instance" "k8s_master" {
  ami                    = var.ami_id
  instance_type          = var.master_instance_type
  subnet_id              = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]
  key_name               = aws_key_pair.k8s_key.key_name
  iam_instance_profile   = aws_iam_instance_profile.k8s_node_profile.name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/scripts/master-init.sh", {
    pod_network_cidr = "10.244.0.0/16"
  })

  tags = {
    Name = "k8s-master"
    Role = "master"
  }

  depends_on = [
    aws_internet_gateway.gw,
    aws_s3_bucket.k8s_token_bucket
  ]
}

# --- Nodos Worker de Kubernetes ---
resource "aws_instance" "k8s_worker" {
  count = var.worker_count

  ami                    = var.ami_id
  instance_type          = var.worker_instance_type
  subnet_id              = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]
  key_name               = aws_key_pair.k8s_key.key_name
  iam_instance_profile   = aws_iam_instance_profile.k8s_node_profile.name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/scripts/worker-init.sh", {
    master_ip = aws_instance.k8s_master.private_ip
  })

  tags = {
    Name = "k8s-worker-${count.index + 1}"
    Role = "worker"
  }

  depends_on = [
    aws_instance.k8s_master,
    aws_internet_gateway.gw,
    aws_s3_bucket.k8s_token_bucket
  ]
}

# --- Null resource para configurar kubectl y desplegar aplicaciones ---
resource "null_resource" "k8s_setup" {
  depends_on = [
    aws_instance.k8s_master,
    aws_instance.k8s_worker
  ]

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(var.ssh_private_key_path)
    host        = aws_instance.k8s_master.public_ip
  }

  # Esperar a que el cluster esté listo
  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for cluster to be ready...'",
      "timeout 300 bash -c 'until kubectl get nodes 2>/dev/null; do sleep 5; done'",
      "echo 'Cluster is ready!'",
      "kubectl get nodes"
    ]
  }

  # Copiar los manifiestos de Kubernetes
  provisioner "file" {
    source      = "${path.module}/../postgres.yaml"
    destination = "/tmp/postgres.yaml"
  }

  provisioner "file" {
    source      = "${path.module}/../web.yaml"
    destination = "/tmp/web.yaml"
  }

  provisioner "file" {
    content = templatefile("${path.module}/manifests/hpa.yaml", {})
    destination = "/tmp/hpa.yaml"
  }

  # Desplegar las aplicaciones
  provisioner "remote-exec" {
    inline = [
      "echo 'Deploying Postgres...'",
      "kubectl apply -f /tmp/postgres.yaml",
      "echo 'Waiting for Postgres to be ready...'",
      "sleep 45",
      
      "echo 'Deploying Web application (includes init_data.py)...'",
      "kubectl apply -f /tmp/web.yaml",
      "echo 'Waiting for web to initialize database...'",
      "sleep 30",
      
      "echo 'Deploying HPA...'",
      "kubectl apply -f /tmp/hpa.yaml",
      
      "echo 'Deployment complete!'",
      "kubectl get pods -A",
      "kubectl get svc -A",
      "kubectl get hpa"
    ]
  }
}
