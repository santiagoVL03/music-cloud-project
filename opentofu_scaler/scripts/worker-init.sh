#!/bin/bash
set -e

# Configurar logging en múltiples archivos
LOG_DIR="/var/log/k8s-setup"
sudo mkdir -p $LOG_DIR

WORKER_LOG="$LOG_DIR/worker-init.log"
ERROR_LOG="$LOG_DIR/worker-errors.log"
COMPLETE_LOG="$LOG_DIR/worker-complete.log"

# Función para logging con timestamps
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | sudo tee -a $WORKER_LOG $COMPLETE_LOG
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | sudo tee -a $ERROR_LOG $COMPLETE_LOG
}

# Redirigir toda la salida a los archivos de log
exec > >(sudo tee -a $COMPLETE_LOG /var/log/k8s-worker-init.log)
exec 2> >(sudo tee -a $ERROR_LOG $COMPLETE_LOG >&2)

log "========================================="
log "Iniciando configuración del Worker Node"
log "========================================="
log "Logs guardados en:"
log "  - Worker log: $WORKER_LOG"
log "  - Error log:  $ERROR_LOG"
log "  - Complete log: $COMPLETE_LOG"
log "========================================="

# 1. Actualizar sistema
log "[1/9] Actualizando paquetes del sistema..."
if ! sudo apt-get update 2>&1 | sudo tee -a $COMPLETE_LOG; then
    log_error "Falló apt-get update"
    exit 1
fi

if ! sudo apt-get upgrade -y 2>&1 | sudo tee -a $COMPLETE_LOG; then
    log_error "Falló apt-get upgrade"
    exit 1
fi

if ! sudo apt-get install -y curl apt-transport-https ca-certificates gnupg lsb-release netcat-openbsd 2>&1 | sudo tee -a $COMPLETE_LOG; then
    log_error "Falló instalación de paquetes básicos"
    exit 1
fi
log "✓ Paquetes básicos instalados"

# 2. Desactivar swap
echo "[2/9] Desactivando swap..."
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# 3. Configurar parámetros del kernel para CNI
echo "[3/9] Configurando parámetros del kernel..."
sudo modprobe br_netfilter
sudo modprobe overlay

cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
br_netfilter
overlay
EOF

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

sudo sysctl --system

# 4. Instalar containerd
echo "[4/9] Instalando containerd..."
sudo apt-get install -y containerd

# Configurar containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml

# Configurar systemd cgroup driver
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

sudo systemctl restart containerd
sudo systemctl enable containerd

# 5. Instalar kubeadm, kubelet y kubectl
echo "[5/9] Instalando kubeadm, kubelet y kubectl..."
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# 6. Esperar a que el master esté listo
log "[6/9] Esperando a que el master esté listo..."
MASTER_IP="${master_ip}"
log "Master IP: $MASTER_IP"

MAX_ATTEMPTS=60
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    log "Intento $((ATTEMPT + 1))/$MAX_ATTEMPTS: Verificando disponibilidad del master..."
    
    # Intentar obtener el comando de join desde el master
    if timeout 5 bash -c "curl -s http://$MASTER_IP:6443 >/dev/null 2>&1" || \
       timeout 5 bash -c "nc -zv $MASTER_IP 6443 >/dev/null 2>&1"; then
        log "✓ Master está respondiendo en el puerto 6443"
        break
    fi
    
    ATTEMPT=$((ATTEMPT + 1))
    if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
        sleep 10
    fi
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    log_error "CRÍTICO: No se pudo conectar al master después de $MAX_ATTEMPTS intentos"
    exit 1
fi
log "✓ Master disponible"

# 7. Esperar adicional para asegurar que kubeadm init haya terminado
log "[7/9] Esperando que kubeadm init complete en el master..."
sleep 60
log "✓ Tiempo de espera completado"

# 8. Obtener el comando de join del master via HTTP
log "[8/9] Obteniendo comando de join del master via HTTP..."
log "Master IP: ${master_ip}"

MAX_JOIN_ATTEMPTS=30
JOIN_ATTEMPT=0

while [ $JOIN_ATTEMPT -lt $MAX_JOIN_ATTEMPTS ]; do
    log "Intento $((JOIN_ATTEMPT + 1))/$MAX_JOIN_ATTEMPTS: Descargando comando de join via HTTP..."
    
    # Intentar descargar el comando de join via HTTP (más simple que SSH)
    CURL_OUTPUT=$(curl -f -s -o /tmp/join-command.sh http://${master_ip}:8080/join-command.sh 2>&1)
    CURL_EXIT=$?
    
    # Registrar el output si hay alguno
    if [ -n "$CURL_OUTPUT" ]; then
        echo "$CURL_OUTPUT" | sudo tee -a $COMPLETE_LOG > /dev/null
    fi
    
    # Verificar si la descarga fue exitosa Y el archivo realmente existe
    if [ $CURL_EXIT -eq 0 ] && [ -f /tmp/join-command.sh ] && [ -s /tmp/join-command.sh ]; then
        log "✓ Comando de join descargado exitosamente via HTTP!"
        break
    else
        log "Descarga falló (curl exit code: $CURL_EXIT) - archivo no disponible aún"
    fi
    
    JOIN_ATTEMPT=$((JOIN_ATTEMPT + 1))
    if [ $JOIN_ATTEMPT -lt $MAX_JOIN_ATTEMPTS ]; then
        log "Esperando 10 segundos antes de reintentar..."
        sleep 10
    fi
done

if [ ! -f /tmp/join-command.sh ]; then
    log_error "CRÍTICO: No se pudo obtener el comando de join después de $MAX_JOIN_ATTEMPTS intentos"
    log_error "Verifica que nginx esté corriendo en el master: curl http://${master_ip}:8080/join-command.sh"
    log_error "Verifica conectividad: ping ${master_ip}"
    log_error "Revisa los logs del master: sudo cat /var/log/k8s-setup/master-complete.log"
    exit 1
fi

log "✓ Comando de join obtenido exitosamente"
log "Comando: $(cat /tmp/join-command.sh)"

# 9. Unirse al cluster
log "[9/9] Uniéndose al cluster..."
chmod +x /tmp/join-command.sh

if ! sudo bash /tmp/join-command.sh 2>&1 | sudo tee -a $COMPLETE_LOG; then
    log_error "CRÍTICO: Falló el join al cluster"
    log_error "Revisa el comando de join: $(cat /tmp/join-command.sh)"
    exit 1
fi

log "✓ Worker unido al cluster exitosamente!"

log "========================================="
log "Worker Node unido al cluster exitosamente!"
log "========================================="

# Verificar el estado
sleep 10
log "Estado del kubelet:"
sudo systemctl status kubelet --no-pager 2>&1 | sudo tee -a $COMPLETE_LOG

log ""
log "========================================="
log "INSTALACIÓN COMPLETA"
log "========================================="
log "Archivos de log disponibles:"
log "  - Worker log: $WORKER_LOG"
log "  - Error log:  $ERROR_LOG"
log "  - Complete log: $COMPLETE_LOG"
log "  - Legacy log: /var/log/k8s-worker-init.log"
log ""
log "Para ver los logs: sudo cat $COMPLETE_LOG"
log "Para ver errores: sudo cat $ERROR_LOG"
log ""

# Crear un archivo de resumen accesible
sudo cat > /home/ubuntu/setup-summary.txt <<EOF
========================================
RESUMEN DE INSTALACIÓN - WORKER NODE
========================================
Fecha: $(date)
Hostname: $(hostname)
Master IP: ${master_ip}

ESTADO DEL KUBELET:
$(sudo systemctl status kubelet --no-pager 2>&1)

ARCHIVOS DE LOG:
- Worker log: $WORKER_LOG
- Error log:  $ERROR_LOG
- Complete log: $COMPLETE_LOG

COMANDO PARA VER LOGS:
  sudo tail -f $COMPLETE_LOG
  sudo cat $ERROR_LOG

COMANDO DE JOIN USADO:
$(cat /tmp/join-command.sh)

NOTA: Verifica el estado de este nodo desde el master con:
  kubectl get nodes

========================================
EOF

sudo chown ubuntu:ubuntu /home/ubuntu/setup-summary.txt
log "✓ Resumen guardado en /home/ubuntu/setup-summary.txt"
