# 🚀 GUÍA RÁPIDA DE DESPLIEGUE

## Cluster Kubernetes en AWS con OpenTofu/Terraform

### 📋 Pre-requisitos
- ✅ Terraform o OpenTofu instalado
- ✅ AWS CLI configurado con credenciales
- ✅ Cuenta AWS con permisos para EC2, VPC, S3, IAM

### ⚡ Inicio Rápido (3 pasos)

#### 1️⃣ Configuración automática
```bash
cd opentofu_scaler
./setup.sh
```

Este script:
- ✅ Verifica Terraform/OpenTofu
- ✅ Verifica AWS CLI
- ✅ Genera par de llaves SSH
- ✅ Crea terraform.tfvars
- ✅ Inicializa Terraform

#### 2️⃣ Desplegar el cluster
```bash
terraform plan      # Revisar cambios
terraform apply     # Crear infraestructura
```

⏱️ **Tiempo estimado:** 10-15 minutos

#### 3️⃣ Verificar el cluster
```bash
# Obtener IP del master
terraform output k8s_master_public_ip

# Conectarse via SSH
ssh -i ~/.ssh/k8s-cluster-key ubuntu@<MASTER_IP>

# Verificar nodos
kubectl get nodes

# Verificar aplicaciones
kubectl get pods -A
kubectl get svc
```

### 🌐 Acceder a la aplicación

```bash
# La aplicación está en el NodePort 30080
http://<MASTER_IP>:30080
```

### 📊 Probar Autoscaling

```bash
# Desde el master
./test-hpa.sh

# O descargar el script
scp -i ~/.ssh/k8s-cluster-key test-hpa.sh ubuntu@<MASTER_IP>:~/
ssh -i ~/.ssh/k8s-cluster-key ubuntu@<MASTER_IP>
./test-hpa.sh
```

### 🧹 Limpieza

```bash
terraform destroy
```

---

## 📚 Documentación Completa

- 📖 **README.md** - Documentación completa y arquitectura
- 🔧 **TROUBLESHOOTING.md** - Solución de problemas comunes
- ⚙️ **terraform.tfvars.example** - Ejemplo de configuración

---

## 🏗️ Lo que se despliega

### Infraestructura AWS
- 🔸 VPC (10.0.0.0/16)
- 🔸 Subnet pública
- 🔸 Internet Gateway
- 🔸 Security Group
- 🔸 1 EC2 t3.medium (Master)
- 🔸 2 EC2 t3.small (Workers)
- 🔸 S3 Bucket (tokens)
- 🔸 IAM Roles

### Kubernetes
- 🔹 Cluster K8s v1.28
- 🔹 Flannel CNI
- 🔹 Metrics Server
- 🔹 PostgreSQL
- 🔹 App Web (musiccloud)
- 🔹 HPA (1-5 réplicas)
- 🔹 NodePort Service

---

## ⚠️ Costos Estimados

**Aproximado por hora (us-east-1):**
- Master (t3.medium): ~$0.042/hora
- 2 Workers (t3.small): ~$0.042/hora
- **Total:** ~$0.084/hora ≈ $2/día ≈ $60/mes

💡 **Tip:** Destruye el cluster cuando no lo uses con `terraform destroy`

---

## 🎯 Outputs Importantes

Después de `terraform apply`, obtendrás:

```hcl
k8s_master_public_ip    = "1.2.3.4"
k8s_worker_public_ips   = ["1.2.3.5", "1.2.3.6"]
ssh_command_master      = "ssh -i ~/.ssh/k8s-cluster-key ubuntu@1.2.3.4"
application_url         = "http://1.2.3.4:30080"
```

---

## 🔑 Archivos Importantes

```
opentofu_scaler/
├── main.tf                    # Configuración principal
├── variables.tf               # Variables
├── outputs.tf                 # Outputs
├── terraform.tfvars           # TUS configuraciones (no en git)
├── setup.sh                   # Script de configuración
├── test-hpa.sh               # Script para probar HPA
├── scripts/
│   ├── master-init.sh        # Inicialización del master
│   └── worker-init.sh        # Inicialización de workers
├── manifests/
│   └── hpa.yaml              # Configuración HPA
├── README.md                  # Documentación completa
└── TROUBLESHOOTING.md        # Guía de problemas
```

---

## 🎓 Para el Proyecto Universitario

### Explicación de la implementación

Este proyecto implementa **Infraestructura como Código (IaC)** usando Terraform/OpenTofu para desplegar automáticamente un cluster de Kubernetes en AWS que replica tu configuración local de VirtualBox.

**Componentes clave implementados:**

1. **Cluster K8s automático:** 
   - Inicialización con `kubeadm init` en el master
   - Join automático de workers usando S3
   - Pod network CIDR: 10.244.0.0/16

2. **Red CNI (Flannel):**
   - Instalación automática post-init
   - Compatible con el CIDR configurado

3. **Metrics Server:**
   - Desplegado automáticamente
   - Patch para funcionar con TLS insecure
   - Requerido para HPA

4. **HPA (Horizontal Pod Autoscaler):**
   - Configurado para deployment "web"
   - Min: 1, Max: 5 réplicas
   - Target: 50% CPU
   - Políticas de escalado optimizadas

5. **Aplicaciones:**
   - PostgreSQL como base de datos
   - App web (musiccloud) con NodePort
   - Job de inicialización de BD

### Ventajas del enfoque IaC

✅ **Reproducibilidad:** Mismo cluster cada vez  
✅ **Versionamiento:** Cambios trackeados en Git  
✅ **Documentación:** El código es la documentación  
✅ **Destrucción segura:** `terraform destroy`  
✅ **Escalabilidad:** Cambiar variables fácilmente  

### Diferencias con VirtualBox

| Aspecto | VirtualBox | AWS con IaC |
|---------|-----------|-------------|
| Tiempo de setup | Manual, ~2-3 horas | Automatizado, ~15 min |
| Red | NAT/Bridge manual | VPC automática |
| Persistencia | Siempre activo | On-demand |
| Costo | Hardware local | Pay-per-use |
| Acceso | Solo local | Internet (NodePort) |

---

## 📝 Ejemplo de uso para el informe

```bash
# 1. Clonar repositorio
git clone <tu-repo>
cd music-cloud-project/opentofu_scaler

# 2. Configurar entorno
./setup.sh

# 3. Revisar plan
terraform plan

# 4. Desplegar
terraform apply -auto-approve

# 5. Esperar ~10-15 minutos

# 6. Conectarse al master
ssh -i ~/.ssh/k8s-cluster-key ubuntu@$(terraform output -raw k8s_master_public_ip)

# 7. Verificar cluster
kubectl get nodes
kubectl get pods -A
kubectl get hpa

# 8. Probar HPA
./test-hpa.sh

# 9. Limpiar
terraform destroy -auto-approve
```

---

## 🆘 Soporte

Si encuentras problemas:

1. Revisa **TROUBLESHOOTING.md**
2. Verifica logs: `/var/log/k8s-*-init.log`
3. Ejecuta: `terraform refresh` y `terraform plan`

---

**¡Tu cluster Kubernetes está listo para producción en AWS! 🎉**
