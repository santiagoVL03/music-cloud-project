#!/bin/bash

# Script de validación del proyecto antes de aplicar

echo "======================================================"
echo "Validación de configuración de Terraform"
echo "======================================================"
echo ""

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ERRORS=0

# 1. Verificar que terraform.tfvars existe
echo -n "Verificando terraform.tfvars... "
if [ ! -f "terraform.tfvars" ]; then
    echo -e "${RED}✗ NO ENCONTRADO${NC}"
    echo "  Ejecuta ./setup.sh para crear el archivo"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓${NC}"
    
    # Verificar que no tenga valores por defecto
    if grep -q "REEMPLAZA_CON_TU_CLAVE_PUBLICA" terraform.tfvars; then
        echo -e "${RED}✗ terraform.tfvars contiene valores placeholder${NC}"
        echo "  Edita terraform.tfvars y configura tu clave SSH pública"
        ERRORS=$((ERRORS + 1))
    fi
fi

# 2. Verificar archivos de configuración
echo -n "Verificando archivos de configuración... "
REQUIRED_FILES=("main.tf" "variables.tf" "outputs.tf")
MISSING_FILES=0

for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo -e "${RED}✗ Falta $file${NC}"
        MISSING_FILES=$((MISSING_FILES + 1))
    fi
done

if [ $MISSING_FILES -eq 0 ]; then
    echo -e "${GREEN}✓${NC}"
else
    ERRORS=$((ERRORS + 1))
fi

# 3. Verificar scripts
echo -n "Verificando scripts... "
SCRIPT_DIRS=("scripts/master-init.sh" "scripts/worker-init.sh")
MISSING_SCRIPTS=0

for script in "${SCRIPT_DIRS[@]}"; do
    if [ ! -f "$script" ]; then
        echo -e "${RED}✗ Falta $script${NC}"
        MISSING_SCRIPTS=$((MISSING_SCRIPTS + 1))
    fi
done

if [ $MISSING_SCRIPTS -eq 0 ]; then
    echo -e "${GREEN}✓${NC}"
else
    ERRORS=$((ERRORS + 1))
fi

# 4. Verificar manifiestos
echo -n "Verificando manifiestos de Kubernetes... "
if [ ! -f "manifests/hpa.yaml" ]; then
    echo -e "${RED}✗ Falta manifests/hpa.yaml${NC}"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓${NC}"
fi

# 5. Verificar manifiestos de la aplicación
echo -n "Verificando manifiestos de aplicación... "
APP_MANIFESTS=("../web.yaml" "../postgres.yaml")
MISSING_APP=0

for manifest in "${APP_MANIFESTS[@]}"; do
    if [ ! -f "$manifest" ]; then
        echo -e "${YELLOW}⚠ Falta $manifest${NC}"
        MISSING_APP=$((MISSING_APP + 1))
    fi
done

if [ $MISSING_APP -eq 0 ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}⚠ Algunos manifiestos no encontrados (se pueden agregar después)${NC}"
fi

# 6. Verificar AWS CLI
echo -n "Verificando AWS CLI... "
if ! command -v aws &> /dev/null; then
    echo -e "${RED}✗ AWS CLI no instalado${NC}"
    ERRORS=$((ERRORS + 1))
else
    if aws sts get-caller-identity &> /dev/null; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗ AWS CLI no configurado${NC}"
        echo "  Ejecuta: aws configure"
        ERRORS=$((ERRORS + 1))
    fi
fi

# 7. Verificar Terraform/OpenTofu
echo -n "Verificando Terraform/OpenTofu... "
if command -v terraform &> /dev/null; then
    echo -e "${GREEN}✓ Terraform $(terraform version | head -n1 | cut -d' ' -f2)${NC}"
elif command -v tofu &> /dev/null; then
    echo -e "${GREEN}✓ OpenTofu $(tofu version | head -n1 | cut -d' ' -f3)${NC}"
else
    echo -e "${RED}✗ Ni Terraform ni OpenTofu encontrados${NC}"
    ERRORS=$((ERRORS + 1))
fi

# 8. Verificar .terraform
echo -n "Verificando inicialización de Terraform... "
if [ -d ".terraform" ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}⚠ No inicializado${NC}"
    echo "  Ejecuta: terraform init"
fi

# 9. Validar sintaxis de Terraform
echo -n "Validando sintaxis de Terraform... "
if command -v terraform &> /dev/null; then
    if terraform validate &> /dev/null; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗ Error de sintaxis${NC}"
        terraform validate
        ERRORS=$((ERRORS + 1))
    fi
elif command -v tofu &> /dev/null; then
    if tofu validate &> /dev/null; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗ Error de sintaxis${NC}"
        tofu validate
        ERRORS=$((ERRORS + 1))
    fi
fi

# 10. Verificar clave SSH
echo -n "Verificando clave SSH... "
if [ -f "$HOME/.ssh/k8s-cluster-key" ]; then
    echo -e "${GREEN}✓${NC}"
    
    # Verificar permisos
    PERMS=$(stat -c %a "$HOME/.ssh/k8s-cluster-key" 2>/dev/null || stat -f %A "$HOME/.ssh/k8s-cluster-key" 2>/dev/null)
    if [ "$PERMS" != "600" ]; then
        echo -e "${YELLOW}⚠ Permisos incorrectos en la clave privada${NC}"
        echo "  Ejecuta: chmod 600 $HOME/.ssh/k8s-cluster-key"
    fi
else
    echo -e "${YELLOW}⚠ Clave SSH no encontrada${NC}"
    echo "  Se buscó en: $HOME/.ssh/k8s-cluster-key"
fi

echo ""
echo "======================================================"

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ Todas las validaciones pasaron${NC}"
    echo ""
    echo "Próximos pasos:"
    echo "  1. terraform plan"
    echo "  2. terraform apply"
    echo ""
    exit 0
else
    echo -e "${RED}✗ Se encontraron $ERRORS errores${NC}"
    echo ""
    echo "Por favor corrige los errores antes de continuar"
    echo ""
    exit 1
fi
