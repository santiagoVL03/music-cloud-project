#!/bin/bash

# Script para configurar el entorno antes de desplegar el cluster Kubernetes

set -e

echo "======================================================"
echo "Configuración de Cluster Kubernetes en AWS"
echo "======================================================"
echo ""

# Colores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 1. Verificar que Terraform/OpenTofu está instalado
echo -e "${YELLOW}[1/5]${NC} Verificando instalación de Terraform/OpenTofu..."
if command -v terraform &> /dev/null; then
    echo -e "${GREEN}✓${NC} Terraform encontrado: $(terraform version | head -n1)"
elif command -v tofu &> /dev/null; then
    echo -e "${GREEN}✓${NC} OpenTofu encontrado: $(tofu version | head -n1)"
else
    echo -e "${RED}✗${NC} ERROR: Terraform/OpenTofu no encontrado"
    echo "Por favor instala Terraform o OpenTofu antes de continuar"
    exit 1
fi

# 2. Verificar AWS CLI
echo -e "${YELLOW}[2/5]${NC} Verificando AWS CLI..."
if command -v aws &> /dev/null; then
    echo -e "${GREEN}✓${NC} AWS CLI encontrado: $(aws --version | cut -d' ' -f1)"
    
    # Verificar credenciales
    if aws sts get-caller-identity &> /dev/null; then
        echo -e "${GREEN}✓${NC} Credenciales AWS configuradas correctamente"
        aws sts get-caller-identity
    else
        echo -e "${RED}✗${NC} ERROR: Credenciales AWS no configuradas"
        echo "Ejecuta: aws configure"
        exit 1
    fi
else
    echo -e "${RED}✗${NC} ERROR: AWS CLI no encontrado"
    echo "Instala AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    exit 1
fi

# 3. Generar par de llaves SSH si no existe
echo -e "${YELLOW}[3/5]${NC} Configurando par de llaves SSH..."
KEY_PATH="$HOME/.ssh/k8s-cluster-key"

if [ -f "$KEY_PATH" ]; then
    echo -e "${YELLOW}!${NC} El archivo $KEY_PATH ya existe"
    read -p "¿Deseas usar la llave existente? (s/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        echo "Abortando. Por favor elimina o renombra la llave existente."
        exit 1
    fi
    echo -e "${GREEN}✓${NC} Usando llave existente"
else
    echo "Generando nuevo par de llaves SSH..."
    ssh-keygen -t rsa -b 4096 -f "$KEY_PATH" -N "" -C "k8s-cluster-aws"
    echo -e "${GREEN}✓${NC} Par de llaves SSH generado en $KEY_PATH"
fi

chmod 600 "$KEY_PATH"
chmod 644 "$KEY_PATH.pub"

# 4. Crear archivo terraform.tfvars
echo -e "${YELLOW}[4/5]${NC} Creando archivo terraform.tfvars..."

PUBLIC_KEY=$(cat "$KEY_PATH.pub")

if [ -f "terraform.tfvars" ]; then
    echo -e "${YELLOW}!${NC} El archivo terraform.tfvars ya existe"
    read -p "¿Deseas sobrescribirlo? (s/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        echo "Manteniendo terraform.tfvars existente"
    else
        cat > terraform.tfvars <<EOF
# Configuración generada automáticamente
aws_region            = "us-east-1"
ami_id                = "ami-0866a3c8686eaeeba"  # Ubuntu 24.04 LTS en us-east-1
master_instance_type  = "t3.medium"
worker_instance_type  = "t3.small"
worker_count          = 2
ssh_public_key        = "$PUBLIC_KEY"
ssh_private_key_path  = "$KEY_PATH"
EOF
        echo -e "${GREEN}✓${NC} Archivo terraform.tfvars creado"
    fi
else
    cat > terraform.tfvars <<EOF
# Configuración generada automáticamente
aws_region            = "us-east-1"
ami_id                = "ami-0866a3c8686eaeeba"  # Ubuntu 24.04 LTS en us-east-1
master_instance_type  = "t3.medium"
worker_instance_type  = "t3.small"
worker_count          = 2
ssh_public_key        = "$PUBLIC_KEY"
ssh_private_key_path  = "$KEY_PATH"
EOF
    echo -e "${GREEN}✓${NC} Archivo terraform.tfvars creado"
fi

# 5. Inicializar Terraform
echo -e "${YELLOW}[5/5]${NC} Inicializando Terraform..."
if command -v terraform &> /dev/null; then
    terraform init
elif command -v tofu &> /dev/null; then
    tofu init
fi

echo ""
echo "======================================================"
echo -e "${GREEN}✓ Configuración completada exitosamente${NC}"
echo "======================================================"
echo ""
echo "Próximos pasos:"
echo ""
echo "1. Revisar la configuración en terraform.tfvars"
echo "2. Ejecutar: terraform plan (o tofu plan)"
echo "3. Ejecutar: terraform apply (o tofu apply)"
echo ""
echo "La clave SSH se encuentra en: $KEY_PATH"
echo "Para conectarse al master: ssh -i $KEY_PATH ubuntu@<MASTER_IP>"
echo ""
