#!/bin/bash

# Script para probar el Horizontal Pod Autoscaler (HPA) del cluster Kubernetes
# Este script genera carga en la aplicación web para observar el escalado automático

set -e

echo "======================================================"
echo "Prueba de Horizontal Pod Autoscaler (HPA)"
echo "======================================================"
echo ""

# Verificar que estamos conectados al cluster
if ! kubectl cluster-info &> /dev/null; then
    echo "ERROR: No se puede conectar al cluster de Kubernetes"
    echo "Asegúrate de estar conectado al nodo master"
    exit 1
fi

echo "✓ Conectado al cluster Kubernetes"
echo ""

# Mostrar estado actual
echo "Estado actual del cluster:"
echo "------------------------"
kubectl get nodes
echo ""
echo "Pods actuales:"
kubectl get pods -l app=web
echo ""
echo "HPA actual:"
kubectl get hpa web-hpa
echo ""

# Verificar si 'hey' está instalado
if ! command -v hey &> /dev/null; then
    echo "Instalando herramienta 'hey' para pruebas de carga..."
    wget -q https://hey-release.s3.us-east-2.amazonaws.com/hey_linux_amd64
    chmod +x hey_linux_amd64
    sudo mv hey_linux_amd64 /usr/local/bin/hey
    echo "✓ 'hey' instalado exitosamente"
    echo ""
fi

# Obtener la IP del servicio web
SERVICE_IP=$(kubectl get svc web -o jsonpath='{.spec.clusterIP}')
SERVICE_PORT=$(kubectl get svc web -o jsonpath='{.spec.ports[0].port}')

if [ -z "$SERVICE_IP" ]; then
    echo "ERROR: No se pudo obtener la IP del servicio 'web'"
    exit 1
fi

echo "Servicio web detectado en: http://$SERVICE_IP:$SERVICE_PORT"
echo ""

# Función para mostrar métricas en tiempo real
show_metrics() {
    echo "======================================================"
    echo "Métricas del cluster (Ctrl+C para detener)"
    echo "======================================================"
    
    while true; do
        clear
        echo "=== NODOS ==="
        kubectl top nodes 2>/dev/null || echo "Esperando métricas..."
        echo ""
        echo "=== PODS WEB ==="
        kubectl top pods -l app=web 2>/dev/null || echo "Esperando métricas..."
        echo ""
        echo "=== HPA ==="
        kubectl get hpa web-hpa
        echo ""
        echo "=== PODS (Réplicas) ==="
        kubectl get pods -l app=web -o wide
        echo ""
        echo "Presiona Ctrl+C para detener el monitoreo"
        sleep 5
    done
}

# Menú de opciones
echo "Opciones de prueba:"
echo "1) Generar carga ligera (2 minutos, 10 conexiones concurrentes)"
echo "2) Generar carga moderada (3 minutos, 30 conexiones concurrentes)"
echo "3) Generar carga alta (5 minutos, 50 conexiones concurrentes)"
echo "4) Solo monitorear métricas (sin generar carga)"
echo "5) Salir"
echo ""

read -p "Selecciona una opción (1-5): " option

case $option in
    1)
        DURATION="2m"
        CONCURRENCY=10
        ;;
    2)
        DURATION="3m"
        CONCURRENCY=30
        ;;
    3)
        DURATION="5m"
        CONCURRENCY=50
        ;;
    4)
        show_metrics
        exit 0
        ;;
    5)
        echo "Saliendo..."
        exit 0
        ;;
    *)
        echo "Opción inválida"
        exit 1
        ;;
esac

echo ""
echo "======================================================"
echo "Iniciando prueba de carga"
echo "======================================================"
echo "Duración: $DURATION"
echo "Conexiones concurrentes: $CONCURRENCY"
echo "Target: http://$SERVICE_IP:$SERVICE_PORT"
echo ""
echo "IMPORTANTE: Abre otra terminal SSH y ejecuta este mismo script"
echo "            eligiendo la opción 4 para monitorear el escalado"
echo ""
read -p "Presiona Enter para continuar..."
echo ""

# Ejecutar hey en background
echo "Generando carga en la aplicación web..."
hey -z $DURATION -c $CONCURRENCY -q 10 http://$SERVICE_IP:$SERVICE_PORT/ > /tmp/hey-results.txt 2>&1 &
HEY_PID=$!

echo "Prueba de carga iniciada (PID: $HEY_PID)"
echo ""
echo "Monitoreando escalado automático..."
echo "======================================================"
echo ""

# Monitorear durante la prueba
SECONDS=0
while kill -0 $HEY_PID 2> /dev/null; do
    ELAPSED=$((SECONDS))
    MINUTES=$((ELAPSED / 60))
    SECS=$((ELAPSED % 60))
    
    echo "[$MINUTES:$(printf "%02d" $SECS)] Estado del cluster:"
    echo "---"
    
    echo "Réplicas actuales:"
    kubectl get pods -l app=web --no-headers | wc -l
    
    echo ""
    echo "HPA:"
    kubectl get hpa web-hpa --no-headers
    
    echo ""
    echo "CPU de los pods:"
    kubectl top pods -l app=web --no-headers 2>/dev/null || echo "Métricas no disponibles aún..."
    
    echo ""
    echo "======================================================"
    echo ""
    
    sleep 15
done

echo ""
echo "======================================================"
echo "Prueba de carga completada"
echo "======================================================"
echo ""

# Mostrar resultados
if [ -f /tmp/hey-results.txt ]; then
    echo "Resultados de la prueba de carga:"
    cat /tmp/hey-results.txt
    echo ""
fi

echo "Estado final del HPA:"
kubectl get hpa web-hpa
echo ""

echo "Pods finales:"
kubectl get pods -l app=web
echo ""

echo "NOTA: Los pods pueden tardar unos minutos en escalar hacia abajo"
echo "      debido a la ventana de estabilización configurada (5 minutos)"
echo ""

read -p "¿Deseas monitorear el escalado hacia abajo? (s/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Ss]$ ]]; then
    show_metrics
fi
