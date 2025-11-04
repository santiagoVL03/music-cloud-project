#!/bin/bash
set -e

# Log de ejecución
exec > >(tee /var/log/k8s-worker-init.log)
exec 2>&1

echo "========================================="
echo "Iniciando configuración del Worker Node"
echo "========================================="

# 1. Actualizar sistema
echo "[1/9] Actualizando paquetes del sistema..."
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get install -y curl apt-transport-https ca-certificates gnupg lsb-release unzip netcat-openbsd

# Instalar AWS CLI
echo "Instalando AWS CLI..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
sudo ./aws/install
rm -rf aws awscliv2.zip

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
echo "[6/9] Esperando a que el master esté listo..."
MASTER_IP="${master_ip}"
MAX_ATTEMPTS=60
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    echo "Intento $((ATTEMPT + 1))/$MAX_ATTEMPTS: Verificando disponibilidad del master..."
    
    # Intentar obtener el comando de join desde el master
    if timeout 5 bash -c "curl -s http://$MASTER_IP:6443 >/dev/null 2>&1" || \
       timeout 5 bash -c "nc -zv $MASTER_IP 6443 >/dev/null 2>&1"; then
        echo "Master está respondiendo en el puerto 6443"
        break
    fi
    
    ATTEMPT=$((ATTEMPT + 1))
    if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
        sleep 10
    fi
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    echo "ERROR: No se pudo conectar al master después de $MAX_ATTEMPTS intentos"
    exit 1
fi

# 7. Esperar adicional para asegurar que kubeadm init haya terminado
echo "[7/9] Esperando que kubeadm init complete en el master..."
sleep 60

# 8. Obtener el comando de join del master
echo "[8/9] Obteniendo comando de join del master desde S3..."
MAX_JOIN_ATTEMPTS=30
JOIN_ATTEMPT=0

while [ $JOIN_ATTEMPT -lt $MAX_JOIN_ATTEMPTS ]; do
    echo "Intento $((JOIN_ATTEMPT + 1))/$MAX_JOIN_ATTEMPTS: Descargando comando de join desde S3..."
    
    # Intentar descargar el comando de join desde S3
    if aws s3 cp s3://${s3_bucket}/join-command.sh /tmp/join-command.sh --region ${aws_region} 2>/dev/null; then
        echo "Comando de join descargado exitosamente!"
        break
    fi
    
    JOIN_ATTEMPT=$((JOIN_ATTEMPT + 1))
    if [ $JOIN_ATTEMPT -lt $MAX_JOIN_ATTEMPTS ]; then
        echo "Archivo no disponible aún, esperando 10 segundos..."
        sleep 10
    fi
done

if [ ! -f /tmp/join-command.sh ]; then
    echo "ERROR: No se pudo obtener el comando de join después de $MAX_JOIN_ATTEMPTS intentos"
    exit 1
fi

# 9. Unirse al cluster
echo "[9/9] Uniéndose al cluster..."
chmod +x /tmp/join-command.sh
sudo bash /tmp/join-command.sh

echo "========================================="
echo "Worker Node unido al cluster exitosamente!"
echo "========================================="

# Verificar el estado
sleep 10
echo "Estado del kubelet:"
sudo systemctl status kubelet --no-pager
