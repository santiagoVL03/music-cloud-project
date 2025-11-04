# Infraestructura Kubernetes en AWS con OpenTofu/Terraform

Este proyecto despliega automáticamente un cluster de Kubernetes (1 master + 2 workers) en AWS utilizando Infraestructura como Código (IaC) con OpenTofu/Terraform.

## 📋 Características

- **Cluster Kubernetes**: 1 nodo master + 2 nodos worker
- **CNI**: Flannel con red de pods 10.244.0.0/16
- **Metrics Server**: Para HPA y monitoreo
- **HPA**: Horizontal Pod Autoscaler configurado para la aplicación web
- **Despliegue automático**: PostgreSQL, aplicación web y configuración inicial
- **Gestión de tokens**: Uso de S3 para compartir tokens de join entre nodos

## 🏗️ Arquitectura

```
┌─────────────────────────────────────────────────────────┐
│                      VPC 10.0.0.0/16                     │
│  ┌────────────────────────────────────────────────────┐ │
│  │         Subnet Public A (10.0.1.0/24)              │ │
│  │                                                     │ │
│  │  ┌──────────────┐  ┌──────────────┐ ┌────────────┐│ │
│  │  │  K8s Master  │  │ K8s Worker 1 │ │K8s Worker 2││ │
│  │  │  (t3.medium) │  │  (t3.small)  │ │ (t3.small) ││ │
│  │  └──────────────┘  └──────────────┘ └────────────┘│ │
│  │                                                     │ │
│  │  Flannel CNI | Metrics Server | HPA                │ │
│  └────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
         │                  │
         └──────────────────┘
         Internet Gateway
```

## 🔧 Requisitos Previos

1. **OpenTofu o Terraform** instalado (versión >= 1.0)
2. **AWS CLI** configurado con credenciales válidas
3. **Par de llaves SSH** para acceso a las instancias
4. **Permisos AWS** para crear VPC, EC2, S3, IAM roles

## 🚀 Despliegue

### Paso 1: Generar par de llaves SSH (si no tienes una)

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/k8s-cluster-key -N ""
```

### Paso 2: Configurar variables

Crea un archivo `terraform.tfvars`:

```hcl
aws_region            = "us-east-1"
ami_id                = "ami-0866a3c8686eaeeba"  # Ubuntu 24.04 LTS en us-east-1
master_instance_type  = "t3.medium"
worker_instance_type  = "t3.small"
worker_count          = 2
ssh_public_key        = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDa..."  # Tu clave pública
ssh_private_key_path  = "~/.ssh/k8s-cluster-key"  # Ruta a tu clave privada
```

**Nota**: Para obtener tu clave pública:
```bash
cat ~/.ssh/k8s-cluster-key.pub
```

### Paso 3: Inicializar Terraform/OpenTofu

```bash
cd opentofu_scaler
terraform init
# o
tofu init
```

### Paso 4: Planificar el despliegue

```bash
terraform plan
# o
tofu plan
```

### Paso 5: Aplicar la configuración

```bash
terraform apply
# o
tofu apply
```

El proceso tomará aproximadamente **10-15 minutos**.

## 📊 Verificación del Cluster

### Conectarse al nodo master

```bash
# Obtener la IP del master desde los outputs
terraform output k8s_master_public_ip

# Conectarse via SSH
ssh -i ~/.ssh/k8s-cluster-key ubuntu@<MASTER_IP>
```

### Verificar los nodos

```bash
kubectl get nodes
```

Deberías ver algo como:
```
NAME         STATUS   ROLES           AGE   VERSION
k8s-master   Ready    control-plane   10m   v1.28.x
k8s-worker-1 Ready    <none>          8m    v1.28.x
k8s-worker-2 Ready    <none>          8m    v1.28.x
```

### Verificar los pods

```bash
kubectl get pods -A
```

### Verificar el HPA

```bash
kubectl get hpa
kubectl describe hpa web-hpa
```

## 🌐 Acceder a la Aplicación

La aplicación web está expuesta en el **NodePort 30080**:

```bash
# Obtener la URL desde los outputs
terraform output application_url

# Acceder desde el navegador
http://<MASTER_IP>:30080
```

## 📈 Probar el Autoscaling

### Generar carga en la aplicación

Desde el master, ejecuta:

```bash
# Instalar hey para pruebas de carga
wget https://hey-release.s3.us-east-2.amazonaws.com/hey_linux_amd64
chmod +x hey_linux_amd64
sudo mv hey_linux_amd64 /usr/local/bin/hey

# Generar carga (ajusta la IP del servicio)
hey -z 5m -c 50 http://<SERVICE_IP>:8000
```

### Monitorear el escalado

En otra terminal SSH:

```bash
# Observar el HPA en tiempo real
watch kubectl get hpa

# Ver los pods escalando
watch kubectl get pods

# Ver métricas
kubectl top nodes
kubectl top pods
```

## 🔍 Debugging

### Sistema de Logs Mejorado

Cada nodo genera múltiples archivos de log organizados en `/var/log/k8s-setup/`:

**En el Master:**
- `/var/log/k8s-setup/master-complete.log` - Log completo con toda la salida
- `/var/log/k8s-setup/master-errors.log` - Solo errores
- `/var/log/k8s-setup/master-init.log` - Log principal con timestamps
- `/home/ubuntu/setup-summary.txt` - Resumen de instalación

**En los Workers:**
- `/var/log/k8s-setup/worker-complete.log` - Log completo con toda la salida
- `/var/log/k8s-setup/worker-errors.log` - Solo errores
- `/var/log/k8s-setup/worker-init.log` - Log principal con timestamps
- `/home/ubuntu/setup-summary.txt` - Resumen de instalación

### Visor de Logs Interactivo

Usa el script `view-logs.sh` para ver los logs fácilmente:

```bash
./view-logs.sh
```

Este script te permite:
1. Ver logs completos del master
2. Ver solo errores del master
3. Ver resumen de instalación del master
4. Ver logs de workers
5. Ver solo errores de workers
6. Ver resumen de workers
7. **Descargar TODOS los logs localmente**
8. Ver logs en tiempo real (tail -f)

### Ver logs manualmente del master

```bash
# Conectarse al master
ssh -i ~/.ssh/k8s-cluster-key ubuntu@<MASTER_IP>

# Ver log completo
sudo cat /var/log/k8s-setup/master-complete.log

# Ver solo errores
sudo cat /var/log/k8s-setup/master-errors.log

# Ver log en tiempo real
sudo tail -f /var/log/k8s-setup/master-complete.log

# Ver resumen
cat ~/setup-summary.txt
```

### Ver logs de un worker

```bash
# Conectarse al worker
ssh -i ~/.ssh/k8s-cluster-key ubuntu@<WORKER_IP>

# Ver log completo
sudo cat /var/log/k8s-setup/worker-complete.log

# Ver solo errores
sudo cat /var/log/k8s-setup/worker-errors.log

# Ver log en tiempo real
sudo tail -f /var/log/k8s-setup/worker-complete.log

# Ver resumen
cat ~/setup-summary.txt
```

### Descargar logs localmente

```bash
# Usar el script automático
./view-logs.sh
# Selecciona opción 7

# O manualmente
scp -i ~/.ssh/k8s-cluster-key ubuntu@<MASTER_IP>:/var/log/k8s-setup/*.log ./
```

### Ver logs de un pod

```bash
kubectl logs <pod-name>
kubectl logs -f deployment/web
kubectl logs -f deployment/postgres
```

### Ver eventos del cluster

```bash
kubectl get events --sort-by='.lastTimestamp'
```

## 🧹 Limpieza

Para destruir toda la infraestructura:

```bash
terraform destroy
# o
tofu destroy
```

**IMPORTANTE**: Esto eliminará todas las instancias EC2, el bucket S3, VPC y recursos asociados.

## 📝 Componentes Desplegados

### Infraestructura AWS
- ✅ VPC con CIDR 10.0.0.0/16
- ✅ Subnet pública en availability zone A
- ✅ Internet Gateway y tablas de ruteo
- ✅ Security Group para cluster K8s
- ✅ 1 instancia EC2 t3.medium (master)
- ✅ 2 instancias EC2 t3.small (workers)
- ✅ Bucket S3 para tokens de join
- ✅ IAM roles y policies

### Kubernetes
- ✅ Cluster K8s v1.28
- ✅ Flannel CNI (10.244.0.0/16)
- ✅ Metrics Server con TLS insecure
- ✅ Deployment PostgreSQL
- ✅ Deployment Web (musiccloud)
- ✅ Job de inicialización de BD
- ✅ HPA configurado (1-5 replicas, 50% CPU)
- ✅ Services (ClusterIP para Postgres, NodePort para Web)

## 🛠️ Personalización

### Cambiar número de workers

En `terraform.tfvars`:
```hcl
worker_count = 3  # Cambia a 3 o más workers
```

### Cambiar tipos de instancia

```hcl
master_instance_type = "t3.large"
worker_instance_type = "t3.medium"
```

### Cambiar región de AWS

```hcl
aws_region = "us-west-2"
ami_id     = "ami-xxx"  # AMI de Ubuntu en esa región
```

Para encontrar AMIs de Ubuntu: https://cloud-images.ubuntu.com/locator/ec2/

## 🔐 Seguridad

⚠️ **Consideraciones de seguridad**:

1. El Security Group permite SSH (22) desde 0.0.0.0/0 - **Restringir a tu IP en producción**
2. El API Server (6443) está expuesto - **Considerar VPN o bastion host**
3. Las claves SSH deben protegerse adecuadamente
4. El bucket S3 contiene tokens sensibles - **Se elimina automáticamente al destruir**

### Restringir acceso SSH solo a tu IP

En `main.tf`, modifica el security group:

```hcl
ingress {
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["TU_IP/32"]  # Reemplaza con tu IP
  description = "SSH access"
}
```

## 📚 Referencias

- [Kubernetes Official Documentation](https://kubernetes.io/docs/)
- [kubeadm Setup](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)
- [Flannel CNI](https://github.com/flannel-io/flannel)
- [Metrics Server](https://github.com/kubernetes-sigs/metrics-server)
- [Horizontal Pod Autoscaler](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)

## 📄 Licencia

Este proyecto es para fines educativos.

## 👤 Autor

Santiago - Music Cloud Project

---

**Nota**: Este cluster está optimizado para desarrollo y pruebas. Para producción, considera usar servicios administrados como EKS, AKS o GKE.
