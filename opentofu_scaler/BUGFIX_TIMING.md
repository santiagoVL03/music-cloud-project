# 🐛 Bug: Terraform Conecta Antes de que Master Esté Listo

## 📋 Problema

### Error Observado
```
null_resource.k8s_setup (remote-exec): The connection to the server 10.0.1.209:6443 was refused
Error: remote-exec provisioner error
error executing "/tmp/terraform_888443475.sh": Process exited with status 1
```

### ¿Qué Pasó?

**Cronología del problema:**

```
1. Terraform crea instancia EC2 del master
   ↓ (30 segundos - instancia "running")
   
2. Terraform ve instancia "running" → intenta conectar
   ↓ (conecta via SSH exitosamente)
   
3. Terraform ejecuta: kubectl get nodes
   ↓
   
4. ERROR: connection refused
   
¿Por qué?
   master-init.sh AÚN ESTÁ CORRIENDO en background
   (toma ~6 minutos total)
```

**El problema:** El estado "running" de EC2 significa que la instancia está encendida, **NO** que Kubernetes esté listo.

### Timeline Real

| Tiempo | Estado EC2 | master-init.sh | Kubernetes API | Terraform |
|--------|-----------|----------------|----------------|-----------|
| 0:00   | launching | - | - | Esperando |
| 0:30   | **running** ✅ | Iniciando | - | **Intenta conectar** |
| 1:00   | running | apt-get update | - | ❌ kubectl fails |
| 3:00   | running | Instalando K8s | - | - |
| 5:00   | running | kubeadm init | Iniciando | - |
| 6:00   | running | Flannel CNI | **Ready** ✅ | - |
| 6:30   | running | Apache2 | Ready | - |

**El problema:** Terraform conecta en 0:30, pero K8s API está listo en 6:00.

---

## ✅ Solución Implementada

### 1. Espera Inicial (local-exec)

Agregamos un delay de 60 segundos **antes** de que Terraform intente conectar:

```hcl
provisioner "local-exec" {
  command = "echo 'Waiting 60 seconds for master to start initialization...' && sleep 60"
}
```

**Por qué:** Le da tiempo al `master-init.sh` de comenzar.

---

### 2. Espera por Archivo Indicador (remote-exec)

Esperamos a que `master-init.sh` **termine completamente**:

```bash
# Esperar a que el archivo de resumen exista (indica que master-init.sh terminó)
timeout 600 bash -c 'until [ -f /home/ubuntu/setup-summary.txt ]; do 
    echo "Waiting for master-init.sh to complete..."; 
    sleep 10; 
done'
```

**Por qué:** 
- El archivo `setup-summary.txt` es lo **último** que crea `master-init.sh`
- Si existe, sabemos que todo el script terminó (incluido Apache2)

---

### 3. Espera por API Server (remote-exec)

Verificamos que `kubectl` realmente funcione:

```bash
timeout 120 bash -c 'until kubectl get nodes 2>/dev/null; do 
    echo "Waiting for API server..."; 
    sleep 5; 
done'
```

**Por qué:**
- Doble verificación de que K8s API server esté respondiendo
- 120 segundos es suficiente (normalmente responde en 10-20s después de que termine init)

---

### 4. Trigger para Recrear

```hcl
triggers = {
  master_id = aws_instance.k8s_master.id
}
```

**Por qué:** Si el master se recrea, el null_resource también se recrea.

---

## 🔍 Código Completo

### main.tf - null_resource

```hcl
resource "null_resource" "k8s_setup" {
  depends_on = [
    aws_instance.k8s_master,
    aws_instance.k8s_worker
  ]

  # Recrear cuando cambie el master
  triggers = {
    master_id = aws_instance.k8s_master.id
  }

  # 1. Espera inicial
  provisioner "local-exec" {
    command = "echo 'Waiting 60 seconds for master to start initialization...' && sleep 60"
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(var.ssh_private_key_path)
    host        = aws_instance.k8s_master.public_ip
  }

  # 2. Esperar a que master-init.sh complete
  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for master initialization to complete...'",
      "echo 'This may take 5-7 minutes...'",
      
      # Esperar archivo indicador
      "timeout 600 bash -c 'until [ -f /home/ubuntu/setup-summary.txt ]; do echo \"Waiting for master-init.sh to complete...\"; sleep 10; done'",
      "echo 'Master initialization script completed!'",
      
      # 3. Esperar API server
      "echo 'Waiting for Kubernetes API server...'",
      "timeout 120 bash -c 'until kubectl get nodes 2>/dev/null; do echo \"Waiting for API server...\"; sleep 5; done'",
      
      "echo 'Cluster is ready!'",
      "kubectl get nodes"
    ]
  }
  
  # ... resto del código (copiar manifests, deploy apps)
}
```

---

## 📊 Nuevo Timeline

| Tiempo | Acción | Resultado |
|--------|--------|-----------|
| 0:00 | Terraform crea instancia | - |
| 0:30 | Instancia "running" | - |
| 0:30 | **local-exec: sleep 60** | ⏱️ Terraform espera |
| 1:30 | Terraform intenta SSH | ✅ Conecta |
| 1:30 | **Espera setup-summary.txt** | ⏱️ master-init.sh corriendo |
| 6:00 | setup-summary.txt creado | ✅ Script completado |
| 6:00 | **Espera kubectl get nodes** | ⏱️ Verificando API |
| 6:05 | kubectl responde | ✅ API listo |
| 6:05 | Deploy aplicaciones | ✅ Todo funciona |

---

## 🎯 Timeouts Configurados

| Etapa | Timeout | Razón |
|-------|---------|-------|
| local-exec sleep | 60s | Dar tiempo a que inicie master-init.sh |
| setup-summary.txt | 600s (10 min) | master-init.sh puede tomar hasta 8 min |
| kubectl get nodes | 120s (2 min) | API normalmente listo en 10-20s |

---

## 🧪 Testing

### Probar manualmente

```bash
# 1. Aplicar
cd opentofu_scaler/
tofu apply

# Deberías ver:
# null_resource.k8s_setup: Creating...
# null_resource.k8s_setup: Provisioning with 'local-exec'...
# null_resource.k8s_setup (local-exec): Waiting 60 seconds for master to start initialization...
# (espera 60s)
# null_resource.k8s_setup: Provisioning with 'remote-exec'...
# null_resource.k8s_setup (remote-exec): Waiting for master initialization to complete...
# null_resource.k8s_setup (remote-exec): This may take 5-7 minutes...
# null_resource.k8s_setup (remote-exec): Waiting for master-init.sh to complete...
# (espera varios minutos)
# null_resource.k8s_setup (remote-exec): Master initialization script completed!
# null_resource.k8s_setup (remote-exec): Waiting for Kubernetes API server...
# null_resource.k8s_setup (remote-exec): Cluster is ready!
# null_resource.k8s_setup (remote-exec): NAME STATUS ROLES AGE VERSION
# null_resource.k8s_setup (remote-exec): ip-10-0-1-xxx Ready control-plane 5m v1.28.15
# null_resource.k8s_setup: Creation complete!
```

---

## 🚨 Troubleshooting

### Si aún falla después de 10 minutos

**Posibles causas:**

1. **master-init.sh tiene un error:**
   ```bash
   ssh ubuntu@<master-ip>
   sudo cat /var/log/k8s-setup/master-errors.log
   ```

2. **kubeadm init falló:**
   ```bash
   ssh ubuntu@<master-ip>
   sudo journalctl -u kubelet -n 100
   ```

3. **Timeout muy corto:**
   - Aumentar timeout de 600s a 900s si la red es lenta

---

## 📝 Notas Importantes

### ¿Por qué no usar `depends_on` solamente?

```hcl
# ❌ NO FUNCIONA
resource "null_resource" "k8s_setup" {
  depends_on = [aws_instance.k8s_master]
  # Esto solo espera a que la INSTANCIA esté "running"
  # NO espera a que master-init.sh termine
}
```

`depends_on` solo espera a que el **recurso se cree**, no a que los scripts `user_data` terminen.

### ¿Por qué no usar cloud-init wait?

Podríamos usar `cloud-init status --wait`, pero:
- Requiere instalar cloud-init-wait
- Más complejo
- El método del archivo indicador es más explícito

---

## ✅ Resultado Final

Con estos cambios, Terraform:

1. ✅ Espera 60s antes de conectar
2. ✅ Verifica que `master-init.sh` haya terminado
3. ✅ Verifica que Kubernetes API esté respondiendo
4. ✅ Despliega aplicaciones exitosamente

**Tiempo total estimado:** ~12-15 minutos (vs fallo inmediato antes)

---

**Fecha:** 2025-11-05  
**Causa:** Terraform conecta antes de que master-init.sh termine  
**Solución:** Esperas explícitas con archivos indicadores  
**Estado:** RESUELTO ✅
