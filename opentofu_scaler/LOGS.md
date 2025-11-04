# 📋 Guía de Logs y Monitoreo

## 📂 Estructura de Logs

Cada nodo del cluster Kubernetes genera logs organizados en diferentes archivos para facilitar el debugging y monitoreo.

### Ubicación de los Logs

```
/var/log/k8s-setup/
├── master-complete.log    # (Master) Log completo con toda la salida
├── master-errors.log      # (Master) Solo errores y advertencias
├── master-init.log        # (Master) Log principal con timestamps
│
├── worker-complete.log    # (Worker) Log completo con toda la salida
├── worker-errors.log      # (Worker) Solo errores y advertencias
└── worker-init.log        # (Worker) Log principal con timestamps

/var/log/
├── k8s-master-init.log    # (Master) Log legacy para compatibilidad
└── k8s-worker-init.log    # (Worker) Log legacy para compatibilidad

/home/ubuntu/
└── setup-summary.txt      # Resumen de la instalación
```

## 🔍 Cómo Ver los Logs

### Opción 1: Script Interactivo (RECOMENDADO)

Desde tu máquina local (donde ejecutaste terraform):

```bash
cd opentofu_scaler
./view-logs.sh
```

El script te mostrará un menú interactivo:

```
====================================================
Selecciona una opción:
====================================================
1) Ver logs del MASTER (completo)
2) Ver logs del MASTER (solo errores)
3) Ver resumen de instalación del MASTER
4) Ver logs de un WORKER (completo)
5) Ver logs de un WORKER (solo errores)
6) Ver resumen de instalación de un WORKER
7) Descargar TODOS los logs localmente
8) Ver logs en tiempo real (tail -f)
9) Salir
```

### Opción 2: Conexión SSH Manual

#### Ver logs del Master

```bash
# Conectarse
ssh -i ~/.ssh/k8s-cluster-key ubuntu@$(terraform output -raw k8s_master_public_ip)

# Ver log completo
sudo cat /var/log/k8s-setup/master-complete.log

# Ver solo errores
sudo cat /var/log/k8s-setup/master-errors.log

# Ver log en tiempo real
sudo tail -f /var/log/k8s-setup/master-complete.log

# Buscar errores específicos
sudo grep -i "error\|failed\|critical" /var/log/k8s-setup/master-complete.log

# Ver resumen de instalación
cat ~/setup-summary.txt

# Ver estado del cluster
kubectl get nodes
kubectl get pods -A
```

#### Ver logs de un Worker

```bash
# Obtener IPs de los workers
terraform output k8s_worker_public_ips

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

# Ver estado del kubelet
sudo systemctl status kubelet
```

## 📥 Descargar Logs Localmente

### Método Automático

```bash
./view-logs.sh
# Selecciona opción 7
```

Esto creará una carpeta `cluster-logs-YYYYMMDD-HHMMSS/` con todos los logs.

### Método Manual

```bash
# Crear directorio local
mkdir cluster-logs
cd cluster-logs

# Descargar logs del master
scp -i ~/.ssh/k8s-cluster-key ubuntu@<MASTER_IP>:/var/log/k8s-setup/*.log ./master/
scp -i ~/.ssh/k8s-cluster-key ubuntu@<MASTER_IP>:/home/ubuntu/setup-summary.txt ./master/

# Descargar logs de cada worker
scp -i ~/.ssh/k8s-cluster-key ubuntu@<WORKER1_IP>:/var/log/k8s-setup/*.log ./worker1/
scp -i ~/.ssh/k8s-cluster-key ubuntu@<WORKER1_IP>:/home/ubuntu/setup-summary.txt ./worker1/

scp -i ~/.ssh/k8s-cluster-key ubuntu@<WORKER2_IP>:/var/log/k8s-setup/*.log ./worker2/
scp -i ~/.ssh/k8s-cluster-key ubuntu@<WORKER2_IP>:/home/ubuntu/setup-summary.txt ./worker2/
```

## 🔎 Análisis de Logs

### Buscar Errores

```bash
# En el master
ssh -i ~/.ssh/k8s-cluster-key ubuntu@<MASTER_IP>

# Buscar errores críticos
sudo grep -i "error\|failed\|critical" /var/log/k8s-setup/master-complete.log

# Contar errores
sudo grep -ic "error" /var/log/k8s-setup/master-complete.log

# Ver contexto de un error (10 líneas antes y después)
sudo grep -B 10 -A 10 -i "error" /var/log/k8s-setup/master-complete.log
```

### Ver Logs de Componentes Específicos

```bash
# Logs de kubeadm init
sudo grep "kubeadm init" /var/log/k8s-setup/master-complete.log -A 50

# Logs de Flannel
sudo grep "Flannel" /var/log/k8s-setup/master-complete.log

# Logs de Metrics Server
sudo grep "Metrics Server" /var/log/k8s-setup/master-complete.log

# Logs de AWS CLI
sudo grep "aws s3" /var/log/k8s-setup/master-complete.log
```

### Ver Timestamps de Cada Paso

```bash
# Todos los logs tienen timestamps en formato:
# [2025-11-04 10:30:45] Mensaje

# Ver duración de la instalación
sudo head -1 /var/log/k8s-setup/master-complete.log
sudo tail -1 /var/log/k8s-setup/master-complete.log
```

## 📊 Monitoreo en Tiempo Real

### Monitorear Instalación en Progreso

```bash
# Ver logs en tiempo real mientras se instala
./view-logs.sh
# Selecciona opción 8

# O manualmente
ssh -i ~/.ssh/k8s-cluster-key ubuntu@<MASTER_IP>
sudo tail -f /var/log/k8s-setup/master-complete.log
```

### Monitorear el Cluster Post-Instalación

```bash
# Desde el master
ssh -i ~/.ssh/k8s-cluster-key ubuntu@<MASTER_IP>

# Ver eventos del cluster
kubectl get events --all-namespaces --sort-by='.lastTimestamp'

# Ver logs de pods
kubectl logs -f deployment/web
kubectl logs -f deployment/postgres

# Ver estado de los nodos
watch kubectl get nodes

# Ver métricas
kubectl top nodes
kubectl top pods
```

## 🚨 Troubleshooting Común

### Problema: No se pueden ver los logs

```bash
# Verificar que los archivos existen
ssh -i ~/.ssh/k8s-cluster-key ubuntu@<MASTER_IP>
ls -lh /var/log/k8s-setup/

# Si no existen, la instalación puede estar en progreso
# Verificar el log legacy
sudo tail -f /var/log/k8s-master-init.log
```

### Problema: Logs muestran errores de AWS CLI

```bash
# Verificar instalación de AWS CLI
ssh -i ~/.ssh/k8s-cluster-key ubuntu@<MASTER_IP>
aws --version

# Verificar IAM role
curl http://169.254.169.254/latest/meta-data/iam/security-credentials/

# Ver errores específicos de S3
sudo grep "s3" /var/log/k8s-setup/master-errors.log
```

### Problema: Worker no se une al cluster

```bash
# En el worker, verificar logs
ssh -i ~/.ssh/k8s-cluster-key ubuntu@<WORKER_IP>

# Ver errores de join
sudo cat /var/log/k8s-setup/worker-errors.log

# Verificar que obtuvo el comando de join
cat /tmp/join-command.sh

# Verificar conectividad con el master
ping <MASTER_PRIVATE_IP>
nc -zv <MASTER_PRIVATE_IP> 6443
```

## 📝 Formato de Logs

Todos los logs siguen este formato:

```
[YYYY-MM-DD HH:MM:SS] NIVEL: Mensaje
```

Ejemplos:

```
[2025-11-04 10:30:45] [1/10] Actualizando paquetes del sistema...
[2025-11-04 10:31:20] ✓ AWS CLI instalado: aws-cli/2.x.x
[2025-11-04 10:35:10] ERROR: Falló apt-get update
[2025-11-04 10:40:00] ✓ Cluster Kubernetes inicializado
```

## 🎯 Mejores Prácticas

1. **Siempre revisa el resumen primero:**
   ```bash
   cat ~/setup-summary.txt
   ```

2. **Busca errores antes de ver todo el log:**
   ```bash
   sudo cat /var/log/k8s-setup/master-errors.log
   ```

3. **Descarga los logs localmente para análisis offline:**
   ```bash
   ./view-logs.sh  # Opción 7
   ```

4. **Usa grep para buscar problemas específicos:**
   ```bash
   sudo grep -i "failed\|error" /var/log/k8s-setup/master-complete.log
   ```

5. **Monitorea en tiempo real durante la instalación:**
   ```bash
   sudo tail -f /var/log/k8s-setup/master-complete.log
   ```

## 📦 Logs para Compartir/Reportar

Si necesitas compartir los logs (ej. para soporte o proyecto universitario):

```bash
# Opción 1: Descargar con el script
./view-logs.sh  # Opción 7
cd cluster-logs-*/
tar -czf cluster-logs.tar.gz .
# Compartir el archivo cluster-logs.tar.gz

# Opción 2: Manual
ssh -i ~/.ssh/k8s-cluster-key ubuntu@<MASTER_IP>
cd /var/log/k8s-setup
sudo tar -czf /home/ubuntu/logs.tar.gz .
exit

scp -i ~/.ssh/k8s-cluster-key ubuntu@<MASTER_IP>:/home/ubuntu/logs.tar.gz ./
```

## 🔄 Rotación de Logs

Los logs pueden crecer mucho. Para limpiar:

```bash
# Desde el master/worker
ssh -i ~/.ssh/k8s-cluster-key ubuntu@<IP>

# Vaciar logs antiguos (CUIDADO: esto borra el historial)
sudo truncate -s 0 /var/log/k8s-setup/*.log

# O comprimir logs antiguos
sudo gzip /var/log/k8s-setup/*.log
```

---

**Nota:** Los logs son cruciales para debugging. Guárdalos antes de destruir el cluster con `terraform destroy`.
