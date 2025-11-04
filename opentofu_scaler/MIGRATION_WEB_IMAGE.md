# Migración: Nueva Imagen Web con Init Integrado

## 🔄 Cambio Realizado

### Antes
Usábamos dos componentes separados:
1. **Job `db-init`** - Imagen `homura69/musiccloud-db_init:latest` que ejecutaba `init_data.py`
2. **Deployment `web`** - Solo ejecutaba `uvicorn main:app`

### Ahora
Un solo componente:
- **Deployment `web`** - Imagen `homura69/musiccloud-web:latest` que ejecuta:
  ```bash
  python init_data.py && uvicorn main:app --host 0.0.0.0 --port 8000
  ```

---

## ✅ Archivos Actualizados

### 1. `web.yaml`
**Cambios:**
```yaml
# ANTES
command: ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
env:
  - name: ENVIRONMENT
    value: "production"
  - name: DATABASE_URL
    value: "postgresql://santiago:santiago@postgres:5432/musiccloud"

# AHORA
command: ["/bin/bash", "-c"]
args: ["python init_data.py && uvicorn main:app --host 0.0.0.0 --port 8000"]
env:
  - name: ENVIRONMENT
    value: "production"
  - name: DATABASE_URL
    value: "postgresql://santiago:santiago@postgres:5432/musiccloud"
  - name: PYTHONUNBUFFERED
    value: "1"
```

**Razón:** 
- Ahora ejecuta `init_data.py` ANTES de iniciar uvicorn
- Agregada variable `PYTHONUNBUFFERED=1` para logs inmediatos

---

### 2. `main.tf` (OpenTofu)
**Cambios:**
```hcl
# ELIMINADO
provisioner "file" {
  source      = "${path.module}/../db-init.yaml"
  destination = "/tmp/db-init.yaml"
}

# ELIMINADO del remote-exec
"kubectl apply -f /tmp/db-init.yaml",
```

**Orden de deployment actualizado:**
```bash
1. kubectl apply -f /tmp/postgres.yaml     # Primero: PostgreSQL
   sleep 45                                 # Espera a que Postgres esté listo
   
2. kubectl apply -f /tmp/web.yaml          # Segundo: Web (con init_data.py)
   sleep 30                                 # Espera init + uvicorn
   
3. kubectl apply -f /tmp/hpa.yaml          # Tercero: Autoscaling
```

---

### 3. `validate.sh`
**Cambios:**
```bash
# ANTES
APP_MANIFESTS=("../web.yaml" "../postgres.yaml" "../db-init.yaml")

# AHORA
APP_MANIFESTS=("../web.yaml" "../postgres.yaml")
```

---

## 🔍 Verificación de Hostnames

### Docker Compose vs Kubernetes

**En `docker-compose.yaml`:**
```yaml
services:
  db:              # ← Nombre del servicio
    image: postgres:13
  web:
    environment:
      - DATABASE_URL=postgresql://santiago:santiago@db:5432/musiccloud
                                                      # ↑ usa "db"
```

**En Kubernetes (`postgres.yaml`):**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres   # ← Nombre del servicio en K8s
```

**En Kubernetes (`web.yaml`):**
```yaml
env:
  - name: DATABASE_URL
    value: "postgresql://santiago:santiago@postgres:5432/musiccloud"
                                          # ↑ usa "postgres" ✅ CORRECTO
```

### ✅ Esto es CORRECTO porque:
- **Docker Compose:** El hostname DNS es el nombre del servicio (`db`)
- **Kubernetes:** El hostname DNS es el nombre del Service (`postgres`)
- La imagen usa `DATABASE_URL` de variable de entorno, no tiene nada hardcodeado

---

## 🚀 Orden de Ejecución

### 1. **Postgres se inicia primero**
```bash
kubectl apply -f postgres.yaml
# Deployment crea el Pod
# Service expone postgres:5432
# Sleep 45s para asegurar que está listo
```

### 2. **Web se inicia después**
```bash
kubectl apply -f web.yaml
# Pod se crea con la nueva imagen
# Ejecuta: python init_data.py
#   ↓
#   Conecta a postgres:5432
#   Crea tablas y datos de prueba
#   ↓
# Luego ejecuta: uvicorn main:app
#   Servidor FastAPI queda escuchando en :8000
```

### 3. **HPA se configura al final**
```bash
kubectl apply -f hpa.yaml
# Configura autoscaling del web deployment
```

---

## 📊 Ventajas del Nuevo Enfoque

| Aspecto | Antes (Job) | Ahora (Integrated) |
|---------|-------------|-------------------|
| Componentes | 2 (Job + Deployment) | 1 (Deployment) |
| Imágenes Docker | 2 diferentes | 1 única |
| Complejidad | Media | Baja |
| Init en cada deploy | No (solo una vez) | Sí (idempotente) |
| Troubleshooting | Ver logs de Job | Ver logs del Pod |
| Recreación de datos | Requiere re-run del Job | Automático en restart |

---

## 🧪 Verificación Post-Deploy

```bash
# 1. Conectarse al master
ssh ubuntu@<master-ip>

# 2. Ver estado de los pods
kubectl get pods

# Deberías ver:
# NAME                        READY   STATUS    RESTARTS   AGE
# postgres-xxxxxxxxx-xxxxx    1/1     Running   0          2m
# web-xxxxxxxxx-xxxxx         1/1     Running   0          1m

# 3. Ver logs del web (debería mostrar init_data.py output)
kubectl logs deployment/web

# Deberías ver:
# [timestamp] Conectando a la base de datos...
# [timestamp] Creando tablas...
# [timestamp] Insertando datos de prueba...
# [timestamp] ✓ Base de datos inicializada
# INFO:     Started server process [1]
# INFO:     Waiting for application startup.
# INFO:     Application startup complete.
# INFO:     Uvicorn running on http://0.0.0.0:8000

# 4. Probar el API
kubectl get svc web
# NAME   TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
# web    NodePort   10.96.xxx.xxx   <none>        8000:30080/TCP   1m

# Desde fuera del cluster:
curl http://<worker-ip>:30080/api_music/music
```

---

## 🐛 Troubleshooting

### Problema: Pod web en CrashLoopBackOff

**Diagnóstico:**
```bash
kubectl logs deployment/web
kubectl describe pod <web-pod-name>
```

**Posibles causas:**
1. `init_data.py` falla al conectar a postgres
   - Solución: Verificar que postgres esté Running primero
   
2. Variables de entorno incorrectas
   - Solución: Verificar `DATABASE_URL` en web.yaml
   
3. Postgres no está listo aún
   - Solución: Aumentar sleep en main.tf (línea ~315)

### Problema: Base de datos vacía

**Verificar que init_data.py se ejecutó:**
```bash
kubectl logs deployment/web | grep "init_data"
```

**Conectarse a Postgres y verificar:**
```bash
kubectl exec -it deployment/postgres -- psql -U santiago -d musiccloud

musiccloud=# \dt
# Debería mostrar las tablas

musiccloud=# SELECT COUNT(*) FROM music;
# Debería mostrar datos
```

---

## 📁 Archivos que YA NO se usan

- ❌ `db-init.yaml` - Eliminado del deployment
- ❌ Imagen `homura69/musiccloud-db_init:latest` - Ya no se usa

**IMPORTANTE:** Estos archivos pueden permanecer en el repositorio para referencia histórica, pero ya no se despliegan en Kubernetes.

---

## ✨ Próximos Pasos

Si quieres hacer el deployment con estos cambios:

```bash
cd opentofu_scaler/

# Si ya tienes infraestructura corriendo
tofu destroy
tofu apply

# La nueva secuencia será:
# 1. Crea VPC, master, workers
# 2. Workers se unen via SSH
# 3. Deploy postgres
# 4. Deploy web (con init_data.py integrado)
# 5. Deploy HPA
```

---

**Fecha:** 2025-11-04  
**Cambio:** Consolidación de db-init en la imagen web  
**Impacto:** Simplificación de la arquitectura, menos componentes
