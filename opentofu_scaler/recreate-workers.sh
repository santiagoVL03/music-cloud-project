#!/bin/bash
# Script rápido para recrear workers con el nuevo sistema SSH

set -e

echo "=============================================="
echo "Recreando Workers con Sistema SSH"
echo "=============================================="
echo ""

cd "$(dirname "$0")"

# Confirmar
echo "Este script va a:"
echo "  1. Destruir los workers actuales"
echo "  2. Recrearlos con el nuevo sistema SSH (sin S3)"
echo ""
read -p "¿Continuar? (y/N): " confirm

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Cancelado."
    exit 0
fi

echo ""
echo "[1/2] Destruyendo workers existentes..."
tofu destroy -target=aws_instance.k8s_worker -auto-approve

echo ""
echo "[2/2] Creando nuevos workers con SSH..."
tofu apply -target=aws_instance.k8s_worker -auto-approve

echo ""
echo "=============================================="
echo "✅ Workers recreados exitosamente!"
echo "=============================================="
echo ""
echo "Verifica el estado del cluster:"
echo "  ssh ubuntu@$(tofu output -raw k8s_master_public_ip)"
echo "  kubectl get nodes"
echo ""
echo "Logs de los workers:"
echo "  ./view-logs.sh"
echo ""
