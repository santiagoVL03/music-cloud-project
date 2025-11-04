#!/bin/bash

# Script para ver los logs de instalación del cluster Kubernetes
# Ejecutar desde tu máquina local para ver logs remotos

set -e

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "======================================================"
echo "Visor de Logs de Cluster Kubernetes"
echo "======================================================"
echo ""

# Obtener IPs de los nodos
echo -e "${BLUE}Obteniendo IPs de los nodos...${NC}"

if ! MASTER_IP=$(tofu output -raw k8s_master_public_ip 2>/dev/null); then
    echo -e "${RED}ERROR: No se pudo obtener la IP del master${NC}"
    echo "Asegúrate de haber ejecutado: tofu apply"
    exit 1
fi

WORKER_IPS=$(tofu output -json k8s_worker_public_ips 2>/dev/null | jq -r '.[]' 2>/dev/null)

echo -e "${GREEN}✓ Master IP: $MASTER_IP${NC}"
if [ -n "$WORKER_IPS" ]; then
    echo -e "${GREEN}✓ Worker IPs:${NC}"
    echo "$WORKER_IPS" | while read ip; do
        echo "  - $ip"
    done
fi

echo ""
echo "======================================================"
echo "Selecciona una opción:"
echo "======================================================"
echo "1) Ver logs del MASTER (completo)"
echo "2) Ver logs del MASTER (solo errores)"
echo "3) Ver resumen de instalación del MASTER"
echo "4) Ver logs de un WORKER (completo)"
echo "5) Ver logs de un WORKER (solo errores)"
echo "6) Ver resumen de instalación de un WORKER"
echo "7) Descargar TODOS los logs localmente"
echo "8) Ver logs en tiempo real (tail -f)"
echo "9) Salir"
echo ""

read -p "Opción (1-9): " option

SSH_KEY="${HOME}/.ssh/k8s-cluster-key"

if [ ! -f "$SSH_KEY" ]; then
    echo -e "${RED}ERROR: No se encuentra la clave SSH en $SSH_KEY${NC}"
    exit 1
fi

case $option in
    1)
        echo -e "${BLUE}Mostrando logs completos del MASTER...${NC}"
        echo ""
        ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@$MASTER_IP \
            "sudo cat /var/log/k8s-setup/master-complete.log" || \
            echo -e "${YELLOW}Si el archivo no existe, prueba: sudo cat /var/log/k8s-master-init.log${NC}"
        ;;
    2)
        echo -e "${BLUE}Mostrando errores del MASTER...${NC}"
        echo ""
        ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@$MASTER_IP \
            "sudo cat /var/log/k8s-setup/master-errors.log 2>/dev/null || echo 'No hay errores registrados o el archivo no existe aún'"
        ;;
    3)
        echo -e "${BLUE}Mostrando resumen de instalación del MASTER...${NC}"
        echo ""
        ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@$MASTER_IP \
            "cat /home/ubuntu/setup-summary.txt 2>/dev/null || echo 'Resumen no disponible aún'"
        ;;
    4)
        echo ""
        echo "Workers disponibles:"
        i=1
        echo "$WORKER_IPS" | while read ip; do
            echo "$i) $ip"
            i=$((i + 1))
        done
        echo ""
        read -p "Selecciona worker (1-$(echo "$WORKER_IPS" | wc -l)): " worker_num
        
        SELECTED_WORKER=$(echo "$WORKER_IPS" | sed -n "${worker_num}p")
        
        if [ -z "$SELECTED_WORKER" ]; then
            echo -e "${RED}Worker inválido${NC}"
            exit 1
        fi
        
        echo -e "${BLUE}Mostrando logs completos del WORKER $SELECTED_WORKER...${NC}"
        echo ""
        ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@$SELECTED_WORKER \
            "sudo cat /var/log/k8s-setup/worker-complete.log" || \
            echo -e "${YELLOW}Si el archivo no existe, prueba: sudo cat /var/log/k8s-worker-init.log${NC}"
        ;;
    5)
        echo ""
        echo "Workers disponibles:"
        i=1
        echo "$WORKER_IPS" | while read ip; do
            echo "$i) $ip"
            i=$((i + 1))
        done
        echo ""
        read -p "Selecciona worker (1-$(echo "$WORKER_IPS" | wc -l)): " worker_num
        
        SELECTED_WORKER=$(echo "$WORKER_IPS" | sed -n "${worker_num}p")
        
        if [ -z "$SELECTED_WORKER" ]; then
            echo -e "${RED}Worker inválido${NC}"
            exit 1
        fi
        
        echo -e "${BLUE}Mostrando errores del WORKER $SELECTED_WORKER...${NC}"
        echo ""
        ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@$SELECTED_WORKER \
            "sudo cat /var/log/k8s-setup/worker-errors.log 2>/dev/null || echo 'No hay errores registrados o el archivo no existe aún'"
        ;;
    6)
        echo ""
        echo "Workers disponibles:"
        i=1
        echo "$WORKER_IPS" | while read ip; do
            echo "$i) $ip"
            i=$((i + 1))
        done
        echo ""
        read -p "Selecciona worker (1-$(echo "$WORKER_IPS" | wc -l)): " worker_num
        
        SELECTED_WORKER=$(echo "$WORKER_IPS" | sed -n "${worker_num}p")
        
        if [ -z "$SELECTED_WORKER" ]; then
            echo -e "${RED}Worker inválido${NC}"
            exit 1
        fi
        
        echo -e "${BLUE}Mostrando resumen del WORKER $SELECTED_WORKER...${NC}"
        echo ""
        ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@$SELECTED_WORKER \
            "cat /home/ubuntu/setup-summary.txt 2>/dev/null || echo 'Resumen no disponible aún'"
        ;;
    7)
        LOG_DIR="./cluster-logs-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$LOG_DIR"
        
        echo -e "${BLUE}Descargando logs a $LOG_DIR...${NC}"
        echo ""
        
        # Descargar logs del master
        echo "Descargando logs del master..."
        scp -i "$SSH_KEY" -o StrictHostKeyChecking=no \
            ubuntu@$MASTER_IP:/var/log/k8s-setup/master-complete.log \
            "$LOG_DIR/master-complete.log" 2>/dev/null || echo "  - master-complete.log no disponible"
        
        scp -i "$SSH_KEY" -o StrictHostKeyChecking=no \
            ubuntu@$MASTER_IP:/var/log/k8s-setup/master-errors.log \
            "$LOG_DIR/master-errors.log" 2>/dev/null || echo "  - master-errors.log no disponible"
        
        scp -i "$SSH_KEY" -o StrictHostKeyChecking=no \
            ubuntu@$MASTER_IP:/home/ubuntu/setup-summary.txt \
            "$LOG_DIR/master-summary.txt" 2>/dev/null || echo "  - master-summary.txt no disponible"
        
        # Descargar logs de los workers
        i=1
        echo "$WORKER_IPS" | while read ip; do
            echo "Descargando logs del worker $i ($ip)..."
            scp -i "$SSH_KEY" -o StrictHostKeyChecking=no \
                ubuntu@$ip:/var/log/k8s-setup/worker-complete.log \
                "$LOG_DIR/worker${i}-complete.log" 2>/dev/null || echo "  - worker${i}-complete.log no disponible"
            
            scp -i "$SSH_KEY" -o StrictHostKeyChecking=no \
                ubuntu@$ip:/var/log/k8s-setup/worker-errors.log \
                "$LOG_DIR/worker${i}-errors.log" 2>/dev/null || echo "  - worker${i}-errors.log no disponible"
            
            scp -i "$SSH_KEY" -o StrictHostKeyChecking=no \
                ubuntu@$ip:/home/ubuntu/setup-summary.txt \
                "$LOG_DIR/worker${i}-summary.txt" 2>/dev/null || echo "  - worker${i}-summary.txt no disponible"
            
            i=$((i + 1))
        done
        
        echo ""
        echo -e "${GREEN}✓ Logs descargados en: $LOG_DIR${NC}"
        ls -lh "$LOG_DIR"
        ;;
    8)
        echo ""
        echo "Ver logs en tiempo real de:"
        echo "1) Master"
        echo "2) Worker"
        read -p "Opción: " node_type
        
        if [ "$node_type" = "1" ]; then
            echo -e "${BLUE}Conectando al master (Ctrl+C para salir)...${NC}"
            ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@$MASTER_IP \
                "sudo tail -f /var/log/k8s-setup/master-complete.log"
        elif [ "$node_type" = "2" ]; then
            echo ""
            echo "Workers disponibles:"
            i=1
            echo "$WORKER_IPS" | while read ip; do
                echo "$i) $ip"
                i=$((i + 1))
            done
            echo ""
            read -p "Selecciona worker: " worker_num
            
            SELECTED_WORKER=$(echo "$WORKER_IPS" | sed -n "${worker_num}p")
            
            if [ -z "$SELECTED_WORKER" ]; then
                echo -e "${RED}Worker inválido${NC}"
                exit 1
            fi
            
            echo -e "${BLUE}Conectando al worker (Ctrl+C para salir)...${NC}"
            ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@$SELECTED_WORKER \
                "sudo tail -f /var/log/k8s-setup/worker-complete.log"
        fi
        ;;
    9)
        echo "Saliendo..."
        exit 0
        ;;
    *)
        echo -e "${RED}Opción inválida${NC}"
        exit 1
        ;;
esac

echo ""
echo "======================================================"
