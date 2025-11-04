#!/bin/bash
set -e

# Log de ejecución
exec > >(tee /var/log/k8s-master-init.log)
exec 2>&1

echo "========================================="
echo "Iniciando configuración del Master Node"
echo "========================================="

# 1. Actualizar sistema
echo "[1/10] Actualizando paquetes del sistema..."
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get install -y curl apt-transport-https ca-certificates gnupg lsb-release unzip

# Instalar AWS CLI
echo "Instalando AWS CLI..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
sudo ./aws/install
rm -rf aws awscliv2.zip

# 2. Desactivar swap
echo "[2/10] Desactivando swap..."
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# 3. Configurar parámetros del kernel para CNI
echo "[3/10] Configurando parámetros del kernel..."
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
echo "[6/10] Inicializando cluster Kubernetes..."
sudo kubeadm init --pod-network-cidr=${pod_network_cidr} --ignore-preflight-errors=all

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

# Guardar también en un archivo accesible via SSH
sudo kubeadm token create --print-join-command | sudo tee /tmp/join-command.sh
sudo chmod 644 /tmp/join-command.sh

# Subir el comando de join a S3 para que los workers puedan accederlo
echo "Subiendo comando de join a S3..."
aws s3 cp /tmp/join-command.sh s3://${s3_bucket}/join-command.sh --region ${aws_region}

echo "========================================="
echo "Master Node configurado exitosamente!"
echo "========================================="

# Mostrar estado del cluster
sudo -u ubuntu kubectl get nodes
sudo -u ubuntu kubectl get pods -A

echo ""
echo "El cluster está listo. Los workers se unirán automáticamente."
