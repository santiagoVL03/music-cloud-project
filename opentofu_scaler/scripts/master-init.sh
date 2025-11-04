#!/bin/bash
set -e

# Configurar logging en múltiples archivos
LOG_DIR="/var/log/k8s-setup"
sudo mkdir -p $LOG_DIR

MASTER_LOG="$LOG_DIR/master-init.log"
ERROR_LOG="$LOG_DIR/master-errors.log"
COMPLETE_LOG="$LOG_DIR/master-complete.log"

# Función para logging con timestamps
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | sudo tee -a $MASTER_LOG $COMPLETE_LOG
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | sudo tee -a $ERROR_LOG $COMPLETE_LOG
}

# Redirigir toda la salida a los archivos de log
exec > >(sudo tee -a $COMPLETE_LOG /var/log/k8s-master-init.log)
exec 2> >(sudo tee -a $ERROR_LOG $COMPLETE_LOG >&2)

log "========================================="
log "Iniciando configuración del Master Node"
log "========================================="
log "Logs guardados en:"
log "  - Master log: $MASTER_LOG"
log "  - Error log:  $ERROR_LOG"
log "  - Complete log: $COMPLETE_LOG"
log "========================================="

# 1. Actualizar sistema
log "[1/10] Actualizando paquetes del sistema..."
if ! sudo apt-get update 2>&1 | sudo tee -a $COMPLETE_LOG; then
    log_error "Falló apt-get update"
    exit 1
fi

if ! sudo apt-get upgrade -y 2>&1 | sudo tee -a $COMPLETE_LOG; then
    log_error "Falló apt-get upgrade"
    exit 1
fi

if ! sudo apt-get install -y curl apt-transport-https ca-certificates gnupg lsb-release 2>&1 | sudo tee -a $COMPLETE_LOG; then
    log_error "Falló instalación de paquetes básicos"
    exit 1
fi
log "✓ Paquetes básicos instalados"

# 2. Desactivar swap
log "[2/10] Desactivando swap..."
sudo swapoff -a 2>&1 | sudo tee -a $COMPLETE_LOG || log_error "Advertencia: swapoff falló"
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
log "✓ Swap desactivado"

# 3. Configurar parámetros del kernel para CNI
log "[3/10] Configurando parámetros del kernel..."
sudo modprobe br_netfilter 2>&1 | sudo tee -a $COMPLETE_LOG || log_error "Advertencia: br_netfilter"
sudo modprobe overlay 2>&1 | sudo tee -a $COMPLETE_LOG || log_error "Advertencia: overlay"

cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf >> $COMPLETE_LOG
br_netfilter
overlay
EOF

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf >> $COMPLETE_LOG
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

sudo sysctl --system 2>&1 | sudo tee -a $COMPLETE_LOG
log "✓ Parámetros del kernel configurados"

# 4. Instalar containerd
echo "[4/10] Instalando containerd..."
sudo apt-get install -y containerd

# Configurar containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml

# Configurar systemd cgroup driver
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

sudo systemctl restart containerd
sudo systemctl enable containerd

# 5. Instalar kubeadm, kubelet y kubectl
echo "[5/10] Instalando kubeadm, kubelet y kubectl..."
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# 6. Inicializar el cluster de Kubernetes
log "[6/10] Inicializando cluster Kubernetes..."
log "Pod Network CIDR: ${pod_network_cidr}"
if ! sudo kubeadm init --pod-network-cidr=${pod_network_cidr} --ignore-preflight-errors=all 2>&1 | sudo tee -a $COMPLETE_LOG; then
    log_error "CRÍTICO: Falló kubeadm init"
    exit 1
fi
log "✓ Cluster Kubernetes inicializado"

# 7. Configurar kubectl para el usuario ubuntu
echo "[7/10] Configurando kubectl..."
mkdir -p /home/ubuntu/.kube
sudo cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
sudo chown ubuntu:ubuntu /home/ubuntu/.kube/config

# También para root (útil para troubleshooting)
mkdir -p /root/.kube
sudo cp -i /etc/kubernetes/admin.conf /root/.kube/config

# 8. Instalar Flannel CNI
echo "[8/10] Instalando Flannel CNI..."
sleep 10
sudo -u ubuntu kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

# 9. Instalar Metrics Server
echo "[9/10] Instalando Metrics Server..."
sleep 20
sudo -u ubuntu kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Patchear metrics-server para que funcione con IPs privadas
sudo -u ubuntu kubectl patch deployment metrics-server -n kube-system --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/args/-",
    "value": "--kubelet-insecure-tls"
  }
]'

# 10. Guardar el comando join para los workers
echo "[10/10] Generando comando de join para workers..."
sudo kubeadm token create --print-join-command > /home/ubuntu/join-command.sh
chmod +x /home/ubuntu/join-command.sh

# Guardar también en un archivo accesible via SSH para los workers
sudo kubeadm token create --print-join-command > /tmp/join-command.sh
sudo chmod 644 /tmp/join-command.sh

log "✓ Comando de join guardado en /tmp/join-command.sh"
log "Los workers se conectarán via SSH para obtenerlo"
log "Comando de join: $(cat /tmp/join-command.sh)"

log "========================================="
log "Master Node configurado exitosamente!"
log "========================================="

# Mostrar estado del cluster
log "Estado del cluster:"
sudo -u ubuntu kubectl get nodes 2>&1 | sudo tee -a $COMPLETE_LOG
log ""
log "Pods del sistema:"
sudo -u ubuntu kubectl get pods -A 2>&1 | sudo tee -a $COMPLETE_LOG

log ""
log "========================================="
log "INSTALACIÓN COMPLETA"
log "========================================="
log "Archivos de log disponibles:"
log "  - Master log: $MASTER_LOG"
log "  - Error log:  $ERROR_LOG"
log "  - Complete log: $COMPLETE_LOG"
log "  - Legacy log: /var/log/k8s-master-init.log"
log ""
log "Para ver los logs: sudo cat $COMPLETE_LOG"
log "Para ver errores: sudo cat $ERROR_LOG"
log ""
log "El cluster está listo. Los workers se unirán automáticamente."

# Crear un archivo de resumen accesible
sudo cat > /home/ubuntu/setup-summary.txt <<EOF
========================================
RESUMEN DE INSTALACIÓN - MASTER NODE
========================================
Fecha: $(date)
Hostname: $(hostname)

ESTADO DEL CLUSTER:
$(sudo -u ubuntu kubectl get nodes 2>&1)

PODS DEL SISTEMA:
$(sudo -u ubuntu kubectl get pods -A 2>&1)

ARCHIVOS DE LOG:
- Master log: $MASTER_LOG
- Error log:  $ERROR_LOG  
- Complete log: $COMPLETE_LOG

COMANDO PARA VER LOGS:
  sudo tail -f $COMPLETE_LOG
  sudo cat $ERROR_LOG

COMANDO DE JOIN PARA WORKERS:
$(cat /tmp/join-command.sh)

========================================
EOF

sudo chown ubuntu:ubuntu /home/ubuntu/setup-summary.txt
log "✓ Resumen guardado en /home/ubuntu/setup-summary.txt"
