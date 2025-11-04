variable "aws_region" {
  description = "AWS region donde se desplegará el cluster"
  type        = string
  default     = "us-east-1"
}

variable "ami_id" {
  description = "AMI ID para Ubuntu 20.04/22.04 LTS (ajustar según región)"
  type        = string
  default     = "ami-0866a3c8686eaeeba" # Ubuntu 24.04 LTS en us-east-1
}

variable "master_instance_type" {
  description = "Tipo de instancia para el nodo master"
  type        = string
  default     = "t3.medium" # Mínimo recomendado para master
}

variable "worker_instance_type" {
  description = "Tipo de instancia para los nodos worker"
  type        = string
  default     = "t3.small"
}

variable "worker_count" {
  description = "Número de nodos worker"
  type        = number
  default     = 2
}

variable "ssh_public_key" {
  description = "Clave pública SSH para acceder a las instancias"
  type        = string
  # Debes proporcionar tu clave pública, por ejemplo:
  # default = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAB..."
}

variable "ssh_private_key_path" {
  description = "Ruta al archivo de clave privada SSH"
  type        = string
  # Ejemplo: default = "~/.ssh/id_rsa"
}
