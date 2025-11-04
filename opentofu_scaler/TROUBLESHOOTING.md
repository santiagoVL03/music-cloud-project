# Troubleshooting y Guía de Problemas Comunes

## 🔍 Problemas Comunes y Soluciones

### 1. Los workers no se unen al cluster

**Síntomas:**
- `kubectl get nodes` solo muestra el master
- Los workers aparecen como NotReady

**Soluciones:**

```bash
# En el worker, verificar logs
ssh -i ~/.ssh/k8s-cluster-key ubuntu@<WORKER_IP>
sudo tail -f /var/log/k8s-worker-init.log

# Verificar que el worker puede alcanzar el master
ping <MASTER_PRIVATE_IP>
nc -zv <MASTER_PRIVATE_IP> 6443

# Verificar que el archivo de join existe en S3
aws s3 ls s3://<BUCKET_NAME>/

# Unir manualmente el worker
# Desde el master, obtener el comando de join
kubeadm token create --print-join-command

# Ejecutar el comando en el worker
sudo <comando-de-join>
```

### 2. Metrics Server no funciona

**Síntomas:**
- `kubectl top nodes` devuelve error
- HPA muestra "unknown" en las métricas

**Soluciones:**

```bash
# Verificar pods del metrics-server
kubectl get pods -n kube-system | grep metrics-server

# Ver logs del metrics-server
kubectl logs -n kube-system deployment/metrics-server

# Reiniciar metrics-server
kubectl rollout restart deployment metrics-server -n kube-system

# Verificar que el patch se aplicó correctamente
kubectl get deployment metrics-server -n kube-system -o yaml | grep kubelet-insecure-tls

# Si no está, aplicar manualmente:
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/args/-",
    "value": "--kubelet-insecure-tls"
  }
]'
```

### 3. Pods en estado Pending o CrashLoopBackOff

**Síntomas:**
- Pods de la aplicación no inician
- Estado Pending, CrashLoopBackOff o Error

**Soluciones:**

```bash
# Describir el pod para ver eventos
kubectl describe pod <pod-name>

# Ver logs del pod
kubectl logs <pod-name>
kubectl logs <pod-name> --previous  # Si el pod reinició

# Verificar recursos disponibles
kubectl describe nodes

# Verificar imágenes
kubectl get pods -o jsonpath='{.items[*].spec.containers[*].image}'

# Si es problema de red CNI (Flannel)
kubectl get pods -n kube-system | grep flannel
kubectl logs -n kube-system <flannel-pod>
```

### 4. No puedo acceder a la aplicación via NodePort

**Síntomas:**
- No se puede acceder a http://<MASTER_IP>:30080
- Timeout al conectar

**Soluciones:**

```bash
# Verificar que el servicio existe
kubectl get svc web

# Verificar que los pods están corriendo
kubectl get pods -l app=web

# Verificar el security group en AWS
# Asegurarse que el puerto 30080 está abierto

# Probar desde dentro del cluster
kubectl run -it --rm debug --image=busybox --restart=Never -- sh
# Dentro del pod:
wget -O- http://web:8000

# Verificar NodePort
kubectl get svc web -o yaml | grep nodePort
```

### 5. HPA no escala los pods

**Síntomas:**
- HPA configurado pero no escala
- Métricas muestran "unknown"

**Soluciones:**

```bash
# Verificar HPA
kubectl get hpa web-hpa
kubectl describe hpa web-hpa

# Verificar que los pods tienen recursos definidos
kubectl get deployment web -o yaml | grep -A 5 resources

# Generar carga manualmente
kubectl run -i --tty load-generator --rm --image=busybox --restart=Never -- /bin/sh -c "while true; do wget -q -O- http://web:8000; done"

# Ver eventos del HPA
kubectl get events --field-selector involvedObject.name=web-hpa
```

### 6. PostgreSQL no persiste datos

**Síntomas:**
- Datos se pierden al reiniciar el pod
- Error al inicializar la base de datos

**Soluciones:**

```bash
# Verificar el PVC (si está configurado)
kubectl get pvc

# Ver logs de Postgres
kubectl logs deployment/postgres

# Conectarse a Postgres para verificar
kubectl exec -it deployment/postgres -- psql -U santiago -d musiccloud

# Si usas emptyDir (no persiste), considera usar PVC
# Editar postgres.yaml para usar un PersistentVolumeClaim
```

### 7. Terraform apply falla

**Síntomas:**
- Error al crear recursos
- Timeout en la creación de instancias

**Soluciones:**

```bash
# Ver logs detallados
terraform apply -auto-approve

# Verificar credenciales AWS
aws sts get-caller-identity

# Verificar límites de la cuenta AWS
# EC2 > Limits (verificar límites de instancias)

# Limpiar estado corrupto
terraform state list
terraform state rm <resource>  # Si es necesario

# Destruir y recrear
terraform destroy -auto-approve
terraform apply -auto-approve
```

### 8. No puedo conectarme por SSH

**Síntomas:**
- Permission denied al intentar SSH
- Connection timeout

**Soluciones:**

```bash
# Verificar permisos de la llave
chmod 600 ~/.ssh/k8s-cluster-key

# Verificar que la IP pública es correcta
terraform output k8s_master_public_ip

# Probar conexión
ssh -vvv -i ~/.ssh/k8s-cluster-key ubuntu@<MASTER_IP>

# Verificar security group
# Asegurarse que el puerto 22 está abierto para tu IP

# Si cambió tu IP pública, actualizar el security group
```

### 9. Costo excesivo de AWS

**Síntomas:**
- Factura AWS más alta de lo esperado

**Soluciones:**

```bash
# Verificar instancias corriendo
aws ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId,State.Name,InstanceType]' --output table

# Destruir el cluster cuando no lo uses
terraform destroy -auto-approve

# Usar instancias más pequeñas (en terraform.tfvars)
master_instance_type = "t3.micro"  # Solo para pruebas, no recomendado
worker_instance_type = "t3.micro"

# Reducir número de workers
worker_count = 1
```

## 📊 Comandos Útiles

### Verificación del Cluster

```bash
# Estado general
kubectl cluster-info
kubectl get nodes -o wide
kubectl get pods -A

# Ver todos los recursos
kubectl get all -A

# Métricas
kubectl top nodes
kubectl top pods -A

# Eventos recientes
kubectl get events --sort-by='.lastTimestamp' -A

# Verificar componentes del control plane
kubectl get componentstatuses
```

### Debugging de Pods

```bash
# Ejecutar comando en un pod
kubectl exec -it <pod-name> -- /bin/bash

# Ver logs en tiempo real
kubectl logs -f <pod-name>

# Ver logs de todos los pods de un deployment
kubectl logs -f deployment/web

# Describir pod (muy útil)
kubectl describe pod <pod-name>

# Ver configuración del pod
kubectl get pod <pod-name> -o yaml
```

### Networking

```bash
# Ver servicios
kubectl get svc -A

# Ver endpoints
kubectl get endpoints

# Probar conectividad
kubectl run tmp-shell --rm -i --tty --image nicolaka/netshoot -- /bin/bash

# DNS debugging
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup web
```

### HPA y Autoscaling

```bash
# Ver HPA
kubectl get hpa
kubectl describe hpa <hpa-name>

# Ver métricas del HPA
kubectl get hpa <hpa-name> -o yaml

# Eventos del HPA
kubectl get events --field-selector involvedObject.name=<hpa-name>

# Escalar manualmente (para probar)
kubectl scale deployment web --replicas=3
```

### Flannel (CNI)

```bash
# Ver pods de Flannel
kubectl get pods -n kube-system -l app=flannel

# Logs de Flannel
kubectl logs -n kube-system -l app=flannel

# Ver configuración de red
kubectl get configmap -n kube-system kube-flannel-cfg -o yaml
```

## 🔧 Comandos de Mantenimiento

### Reiniciar componentes

```bash
# Reiniciar deployment
kubectl rollout restart deployment/<name>

# Ver estado del rollout
kubectl rollout status deployment/<name>

# Historial de rollouts
kubectl rollout history deployment/<name>
```

### Limpiar recursos

```bash
# Eliminar pods completados
kubectl delete pods --field-selector=status.phase=Succeeded -A

# Eliminar pods fallidos
kubectl delete pods --field-selector=status.phase=Failed -A

# Limpiar nodos evicted
kubectl get pods -A | grep Evicted | awk '{print $2 " -n " $1}' | xargs kubectl delete pod
```

### Backup y Restore

```bash
# Backup de recursos
kubectl get all -A -o yaml > cluster-backup.yaml

# Backup de namespace específico
kubectl get all -n default -o yaml > default-ns-backup.yaml

# Restore
kubectl apply -f cluster-backup.yaml
```

## 📝 Logs Importantes

### En el Master

```bash
# Log de inicialización
/var/log/k8s-master-init.log

# Logs de kubelet
journalctl -u kubelet -f

# Logs del API server
kubectl logs -n kube-system kube-apiserver-<master-name>
```

### En los Workers

```bash
# Log de inicialización
/var/log/k8s-worker-init.log

# Logs de kubelet
journalctl -u kubelet -f

# Logs de containerd
journalctl -u containerd -f
```

## 🆘 Recuperación de Desastres

### Cluster no responde

```bash
# 1. Verificar estado de los nodos (desde el master)
kubectl get nodes

# 2. Reiniciar kubelet en todos los nodos
sudo systemctl restart kubelet

# 3. Si el API server no responde
sudo systemctl status kube-apiserver

# 4. Verificar etcd (almacén de datos del cluster)
kubectl get pods -n kube-system | grep etcd
```

### Recrear un worker

```bash
# 1. Remover del cluster (desde el master)
kubectl drain <worker-name> --ignore-daemonsets --delete-emptydir-data
kubectl delete node <worker-name>

# 2. En AWS, terminar la instancia
terraform taint aws_instance.k8s_worker[0]
terraform apply

# 3. El nuevo worker se unirá automáticamente
```

### Recrear el master

⚠️ **ADVERTENCIA**: Esto destruirá todo el cluster

```bash
terraform destroy -target=aws_instance.k8s_master
terraform apply
```

## 📞 Recursos Adicionales

- [Kubernetes Troubleshooting](https://kubernetes.io/docs/tasks/debug/)
- [kubeadm Troubleshooting](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/troubleshooting-kubeadm/)
- [Flannel Troubleshooting](https://github.com/flannel-io/flannel/blob/master/Documentation/troubleshooting.md)
