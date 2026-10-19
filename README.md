# Gobernanza en tiempos de IA

Laboratorios prácticos de gobernanza de cargas de IA en Kubernetes, preparados para la charla **«Gobernanza en tiempos de IA»** en [DevOpsDays Bogotá 2026](https://devopsdays.org/).

Este repositorio muestra, con cluster local y políticas reales, cómo limitar GPUs, verificar la integridad de un modelo, restringir permisos de un agente con acceso a la API de Kubernetes y exigir metadatos de trazabilidad.

> **Importante:** estas demos son educativas. No son un diseño de seguridad listo para producción.

---

## Propósito

Las cargas de IA en Kubernetes suelen pedir aceleradores, montar artefactos de modelo y, cada vez más, operar con agentes que llaman a la API. Sin gobernanza, esos flujos pueden:

- consumir GPUs de forma descontrolada;
- ejecutar modelos alterados o de origen no validado;
- permitir acciones destructivas desde un ServiceAccount de agente;
- desplegar inferencia sin metadatos de ownership ni costo.

Los cuatro laboratorios combinan **RBAC de Kubernetes** y **Kyverno** (Validate, Mutate, Generate/Synchronize) para ilustrar controles en admisión y en tiempo de ejecución.

---

## Arquitectura y prerrequisitos

### Entorno de referencia

| Componente | Detalle verificado en este proyecto |
|---|---|
| Sistema | macOS (Apple Silicon) |
| Contenedores | Podman (`KIND_EXPERIMENTAL_PROVIDER=podman`) |
| Cluster | Kind, nombre `devopsdays` |
| Kubernetes | v1.37.x (nodo Kind) |
| Helm | 3.x |
| Kyverno | chart `3.9.1` / app `v1.19.1` |
| GPUs simuladas | NVIDIA Mokka (`nvml-mock`) + device plugin mock |
| Modelo local (Lab 03) | Ollama + `qwen2.5:3b` en el host |
| Agente (Lab 03) | Python (`ollama`, `kubernetes`) como Job |

### Estructura del repositorio

```text
devopsdays-labs/
├── bootstrap/
├── lab01-gpu/
├── lab02-model-supply-chain/
├── lab03-ai-agent/
└── lab04-ai-traceability/
```

### Herramientas necesarias

- [Podman](https://podman.io/)
- [Kind](https://kind.sigs.k8s.io/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/) ≥ 3.8 (charts OCI)
- [Ollama](https://ollama.com/) (solo Lab 03)
- `curl` o `wget` (descarga del modelo GGUF del Lab 02)

Los binarios de modelo (`.gguf`), tokens locales, `.venv/` y archivos `.tar` de imagen **no** forman parte del repositorio Git (ver `.gitignore`).

---

## Inicio rápido (plataforma compartida)

Los laboratorios asumen un cluster Kind llamado `devopsdays`, Kyverno instalado y, para el Lab 01, GPUs simuladas con Mokka.

Los scripts en `bootstrap/` son operaciones **separadas** e idempotentes donde aplica. No recrean un cluster existente.

### 1. Crear el cluster Kind con Podman

```bash
export KIND_EXPERIMENTAL_PROVIDER=podman
./bootstrap/01-create-cluster.sh
```

Equivale a `kind create cluster --name devopsdays --config bootstrap/kind-config.yaml` si el cluster aún no existe.

### 2. Instalar Kyverno v1.19.1

```bash
./bootstrap/02-install-kyverno.sh
```

Instala o actualiza el chart `kyverno/kyverno` versión `3.9.1` (app `v1.19.1`).

### 3. Instalar GPUs simuladas (Mokka + device plugin)

Estas no son GPUs físicas: Mokka expone un NVML mock y el device plugin registra `nvidia.com/gpu` en el nodo.

```bash
./bootstrap/03-install-mokka.sh
```

El script aplica los valores verificados en el entorno de trabajo (`gpu.count=8`, `gpu.profile=h100`), etiqueta nodos con `mokka.nvidia.com/type=sgpu` y despliega `lab01-gpu/nvidia-device-plugin.yaml`.

Deberías ver `8` en la columna `GPUS`.

### 4. Namespaces de los laboratorios

```bash
./bootstrap/04-create-namespaces.sh
```

### 5. RBAC del Background Controller (Lab 03 Generate/Synchronize)

Necesario antes de demostrar `GeneratingPolicy` en el Lab 03:

```bash
./bootstrap/05-apply-kyverno-generate-rbac.sh
```

Aplica:

- `lab03-ai-agent/kyverno-generate-permissions.yaml` — Role/RoleBinding en `ai-agent-lab` para que `kyverno-background-controller` gestione Roles y RoleBindings del namespace.
- `lab03-ai-agent/kyverno-watch-rbac.yaml` — ClusterRole/ClusterRoleBinding con `list`/`watch` de Roles y RoleBindings (el watcher de synchronize opera a nivel de cluster).

No se concede `cluster-admin`. Synchronize restaura recursos generados tras detectar drift; **no** elimina ventanas temporales de exposición de privilegios.
---

## Resumen de laboratorios

| Lab | Carpeta | Riesgo | Controles |
|---|---|---|---|
| 01 | `lab01-gpu` | Solicitudes excesivas de GPU | `ClusterPolicy` (Validate) + `MutatingPolicy` |
| 02 | `lab02-model-supply-chain` | Modelo alterado / verificación omitida | InitContainer SHA-256 + `ValidatingPolicy` |
| 03 | `lab03-ai-agent` | Agente con permisos destructivos | RBAC + `ValidatingPolicy` + `GeneratingPolicy` |
| 04 | `lab04-ai-traceability` | Inferencia sin metadatos | `ValidatingPolicy` + `MutatingPolicy` |

APIs de Kyverno en este repo:

- `kyverno.io/v1` `ClusterPolicy` — validación inicial de GPUs en Lab 01.
- `policies.kyverno.io/v1` — `ValidatingPolicy`, `MutatingPolicy`, `GeneratingPolicy` en Labs 01–04.

---

## Lab 01 — ¿Quién pidió 8 GPUs?

### Objetivo

Demostrar gobernanza de recursos GPU para cargas de IA: rechazar solicitudes excesivas y asignar límites según el entorno.

### Riesgo

Sin admisión, un Deployment en `ai-dev` puede solicitar `nvidia.com/gpu: 8` y el scheduler lo aceptará si el nodo (simulado) tiene capacidad.

### Arquitectura / componentes

- Namespaces: `ai-dev`, `ai-ml`, `ai-prod`
- Mokka + DaemonSet `nvidia-device-plugin-mock`
- Workloads de ejemplo con imagen `nginx:alpine` (placeholder de inferencia)
- Políticas Kyverno de validación y mutación

### Manifests relevantes

| Archivo | Rol |
|---|---|
| `lab01-gpu/nvidia-device-plugin.yaml` | Device plugin mock |
| `lab01-gpu/deployment-bad.yaml` | 8 GPUs en `ai-dev` |
| `lab01-gpu/deployment-good.yaml` | 1 GPU en `ai-dev` |
| `lab01-gpu/deployment-auto.yaml` | Sin límite GPU (para mutación) |
| `lab01-gpu/gpu-policy.yaml` | `ClusterPolicy` — máx. 1 GPU en `ai-dev` |
| `lab01-gpu/gpu-mutate.yaml` | `MutatingPolicy` — asigna GPUs por namespace |

### Setup

Completa el [inicio rápido](#inicio-rápido-plataforma-compartida) (cluster, Kyverno, Mokka, namespaces).

Antes de cada escenario, limpia Deployments de prueba:

```bash
kubectl delete deployment ai-inference ai-inference-auto \
  -n ai-dev --ignore-not-found
kubectl delete deployment ai-inference-auto -n ai-ml --ignore-not-found
kubectl delete deployment ai-inference-auto -n ai-prod --ignore-not-found
kubectl delete clusterpolicy restrict-ai-gpus --ignore-not-found
kubectl delete mutatingpolicy assign-gpus-by-environment --ignore-not-found
```

### Antes de la gobernanza

```bash
kubectl apply -f lab01-gpu/deployment-bad.yaml
kubectl get pods -n ai-dev -o wide
kubectl get pod -n ai-dev -l app=ai-inference \
  -o jsonpath='{.items[0].spec.containers[0].resources.limits}' ; echo
```

El Pod puede quedar `Running` consumiendo 8 GPUs **simuladas**.

### Después de la gobernanza

**Validate (API clásica `ClusterPolicy`):**

```bash
kubectl delete deployment ai-inference -n ai-dev --ignore-not-found
kubectl apply -f lab01-gpu/gpu-policy.yaml

kubectl apply -f lab01-gpu/deployment-bad.yaml
# Esperado: rechazo — maximum 1 GPU per container in ai-dev

kubectl apply -f lab01-gpu/deployment-good.yaml
# Esperado: aceptado
```

**Mutate (API `policies.kyverno.io/v1` `MutatingPolicy`):**

Asigna `nvidia.com/gpu` solo si el contenedor aún no lo declara:

| Namespace | GPUs asignadas |
|---|---|
| `ai-dev` | 1 |
| `ai-ml` | 2 |
| `ai-prod` | 8 |

```bash
kubectl apply -f lab01-gpu/gpu-mutate.yaml

kubectl apply -f lab01-gpu/deployment-auto.yaml -n ai-dev
kubectl apply -f lab01-gpu/deployment-auto.yaml -n ai-ml
kubectl apply -f lab01-gpu/deployment-auto.yaml -n ai-prod

for ns in ai-dev ai-ml ai-prod; do
  kubectl get deploy ai-inference-auto -n "$ns" \
    -o custom-columns=\
'NS:.metadata.namespace,GPU:.spec.template.spec.containers[0].resources.limits.nvidia\.com/gpu'
done
```

### Resultados esperados

- Sin política: `deployment-bad.yaml` se admite.
- Con `restrict-ai-gpus`: 8 GPUs en `ai-dev` se deniegan; 1 GPU se admite.
- Con `assign-gpus-by-environment`: `deployment-auto.yaml` recibe 1 / 2 / 8 según namespace.

### Cleanup

```bash
kubectl delete deployment ai-inference ai-inference-auto \
  -n ai-dev --ignore-not-found
kubectl delete deployment ai-inference-auto -n ai-ml --ignore-not-found
kubectl delete deployment ai-inference-auto -n ai-prod --ignore-not-found
kubectl delete -f lab01-gpu/gpu-policy.yaml --ignore-not-found
kubectl delete -f lab01-gpu/gpu-mutate.yaml --ignore-not-found
```

### Lecciones y límites

- Las GPUs son **simuladas** (Mokka). Sirven para scheduling y políticas, no para cómputo real.
- `ClusterPolicy` (`kyverno.io/v1`) convive aquí con `MutatingPolicy` moderna; el experimento de validación GPU usa a propósito la API clásica.
- La mutación no sobrescribe un límite GPU ya declarado; solo lo añade si falta.

---

## Lab 02 — ¿De dónde salió ese modelo?

### Objetivo

Demostrar controles de integridad del artefacto de modelo y de la configuración de verificación en admisión.

### Riesgo

Un Pod puede montar un `.gguf` alterado, o saltarse el InitContainer de verificación, y aun así “arrancar inferencia”.

### Arquitectura / componentes

- Namespace: `ai-supply`
- PVC `ai-model-storage` + Pod `model-loader`
- Modelo GGUF local (no versionado en Git): `lab02-model-supply-chain/models/model.gguf`
- Origen verificado: Hugging Face `unsloth/SmolLM2-135M-Instruct-GGUF` (`SmolLM2-135M-Instruct-Q4_K_M.gguf`)
- Pod `model-verification` con InitContainer `verify-model` (`sha256sum -c`)
- Digest esperado (hardcodeado en el manifiesto y en la política):

  `ed5fa30c487b282ec156c29062f1222e5c20875a944ac98289dbd242e947f747`

### Manifests relevantes

| Archivo | Rol |
|---|---|
| `lab02-model-supply-chain/download-model.sh` | Descarga + verificación SHA-256 |
| `lab02-model-supply-chain/model-storage.yaml` | PVC + loader |
| `lab02-model-supply-chain/model-verify.yaml` | Verificación SHA-256 correcta |
| `lab02-model-supply-chain/model-without-verification.yaml` | Sin InitContainer |
| `lab02-model-supply-chain/model-fake-verification.yaml` | “Verifier” falso |
| `lab02-model-supply-chain/model-unapproved-registry.yaml` | Imagen fuera de `docker.io` |
| `lab02-model-supply-chain/require-model-verification.yaml` | `ValidatingPolicy` de verificación |
| `lab02-model-supply-chain/registry-policy.yaml` | `ValidatingPolicy` — solo `docker.io` |

### Setup

```bash
kubectl create namespace ai-supply --dry-run=client -o yaml | kubectl apply -f -

./lab02-model-supply-chain/download-model.sh

kubectl delete pod model-loader model-verification \
  model-verification-bypass model-verification-fake \
  model-unapproved-registry \
  -n ai-supply --ignore-not-found
kubectl delete -f lab02-model-supply-chain/require-model-verification.yaml --ignore-not-found
kubectl delete -f lab02-model-supply-chain/registry-policy.yaml --ignore-not-found

kubectl apply -f lab02-model-supply-chain/model-storage.yaml
kubectl wait --for=condition=Ready pod/model-loader -n ai-supply --timeout=120s

kubectl cp lab02-model-supply-chain/models/model.gguf \
  ai-supply/model-loader:/models/model.gguf
```

### Antes de la gobernanza (integridad del archivo)

**Modelo íntegro:**

```bash
kubectl delete pod model-verification -n ai-supply --ignore-not-found
kubectl apply -f lab02-model-supply-chain/model-verify.yaml
kubectl wait --for=condition=Ready pod/model-verification \
  -n ai-supply --timeout=120s

kubectl logs model-verification -n ai-supply -c verify-model
kubectl logs model-verification -n ai-supply -c inference
```

Esperado:

```text
/models/model.gguf: OK
Model verified. Starting inference...
```

**Modelo alterado:**

```bash
kubectl exec -n ai-supply model-loader -- \
  sh -c 'echo tampered >> /models/model.gguf'

kubectl delete pod model-verification -n ai-supply --ignore-not-found
kubectl apply -f lab02-model-supply-chain/model-verify.yaml
kubectl get pod model-verification -n ai-supply
kubectl logs model-verification -n ai-supply -c verify-model
```

Esperado: InitContainer en error; el contenedor principal no arranca.

Restaura el modelo antes de seguir:

```bash
kubectl cp lab02-model-supply-chain/models/model.gguf \
  ai-supply/model-loader:/models/model.gguf
```

### Después de la gobernanza (admisión Kyverno)

```bash
kubectl apply -f lab02-model-supply-chain/require-model-verification.yaml

kubectl apply -f lab02-model-supply-chain/model-without-verification.yaml
# Esperado: Deny — approved model verifier and checksum required

kubectl apply -f lab02-model-supply-chain/model-fake-verification.yaml
# Esperado: Deny — el comando/env no coinciden con el verifier aprobado

kubectl apply -f lab02-model-supply-chain/model-verify.yaml
# Esperado: admitido (configuración exacta requerida por la política)
```

**Validación de registry (negativo):**

La política `restrict-ai-registries` exige registry `docker.io` en containers / initContainers / ephemeralContainers. El manifiesto negativo usa `quay.io/quay/busybox:latest` en el contenedor principal (el InitContainer mantiene el verifier aprobado para aislar el fallo al registry):

```bash
kubectl apply -f lab02-model-supply-chain/registry-policy.yaml

kubectl apply -f lab02-model-supply-chain/model-unapproved-registry.yaml
# Esperado: Deny — AI Governance: container registry not approved.
# El rechazo ocurre en admisión; Kubernetes no llega a hacer pull de quay.io.
```

### Cleanup

```bash
kubectl delete pod model-verification model-verification-bypass \
  model-verification-fake model-unapproved-registry model-loader \
  -n ai-supply --ignore-not-found
kubectl delete -f lab02-model-supply-chain/require-model-verification.yaml --ignore-not-found
kubectl delete -f lab02-model-supply-chain/registry-policy.yaml --ignore-not-found
kubectl delete -f lab02-model-supply-chain/model-storage.yaml --ignore-not-found
```

### Lecciones y límites

- SHA-256 comprueba **integridad del archivo** frente a un digest esperado. No implica seguridad del modelo, procedencia criptográfica ni ausencia de backdoors.
- La `ValidatingPolicy` exige coincidencia exacta de imagen, comando, digest y mount de solo lectura: es demo de admission control, no un marco completo de supply chain (p. ej. cosign/SLSA).

---

## Lab 03 — Un agente de IA con demasiados permisos

### Objetivo

Mostrar el riesgo de un agente que llama a la API de Kubernetes, y separar autorización runtime (RBAC), gobernanza de admisión (Validate) y reconciliación (Generate/Synchronize).

### Riesgo

Un Job con ServiceAccount privilegiado puede inspeccionar y borrar Deployments reales si el modelo decide invocar herramientas.

### Arquitectura / componentes

- Namespace aislado: `ai-agent-lab`
- ServiceAccount `ai-operator` + Role/RoleBinding
- Deployment desechable `payment-api` (objetivo de borrado)
- Ollama en el **host** Mac con `qwen2.5:3b`
- Imagen `localhost/ai-agent:lab03` (Dockerfile + `agent.py`)
- Job `ai-agent` con `OLLAMA_URL=http://host.containers.internal:11434`
- Políticas Kyverno sobre el Role y RBAC de solo lectura generado

### Manifests y código relevantes

| Archivo | Rol |
|---|---|
| `lab03-ai-agent/agent.py` | Agente con tools `list` / `inspect` / `delete` |
| `lab03-ai-agent/prompts/investigate.txt` | Prompt escenario A (inspección) |
| `lab03-ai-agent/prompts/authorized-delete.txt` | Prompt escenario B (borrado autorizado) |
| `lab03-ai-agent/Dockerfile` | Imagen Python 3.12 + `ollama` + `kubernetes` |
| `lab03-ai-agent/agent-job.yaml` | Job (default `AGENT_SCENARIO=authorized-delete`) |
| `lab03-ai-agent/agent-job-investigate.yaml` | Job escenario A |
| `lab03-ai-agent/agent-job-delete.yaml` | Job escenario B |
| `lab03-ai-agent/payment-api.yaml` | Deployment desechable objetivo |
| `lab03-ai-agent/agent-rbac.yaml` | SA + Role permisivo + RoleBinding (bootstrap inicial) |
| `lab03-ai-agent/agent-rbac-permissive.yaml` | Role con `get`/`list`/`delete` |
| `lab03-ai-agent/agent-rbac-restricted.yaml` | Role con `get`/`list` (sin `delete`) |
| `lab03-ai-agent/agent-rbac-policy.yaml` | `ValidatingPolicy` — bloquea verbs destructivos en `ai-operator-role` |
| `lab03-ai-agent/agent-generate-rbac.yaml` | `GeneratingPolicy` — Role/RoleBinding readonly + synchronize |
| `lab03-ai-agent/kyverno-generate-permissions.yaml` | Role/RoleBinding para que Kyverno genere RBAC en el namespace |
| `lab03-ai-agent/kyverno-watch-rbac.yaml` | ClusterRole/Binding `list/watch` de roles/rolebindings |

> **No uses ni publiques** `agent-token.txt`, `.venv/`, ni archivos `.tar` de imagen. Están en `.gitignore`. La vía soportada es construir la imagen con el `Dockerfile` (respeta `.dockerignore`).

### Setup — Ollama y conectividad Podman/Kind

1. En el Mac:

```bash
ollama pull qwen2.5:3b
ollama serve   # si no está ya escuchando en :11434
```

2. El Job usa `host.containers.internal:11434` para alcanzar Ollama desde el contenedor Kind/Podman. Con Podman en macOS, ese hostname apunta al host. Verifica desde un Pod de prueba si hace falta:

```bash
kubectl run -n ai-agent-lab curl-ollama --rm -it --restart=Never \
  --image=curlimages/curl -- \
  curl -sS http://host.containers.internal:11434/api/tags
```

3. Construir y cargar la imagen del agente:

```bash
export KIND_EXPERIMENTAL_PROVIDER=podman

cd lab03-ai-agent
podman build -t localhost/ai-agent:lab03 .
kind load docker-image localhost/ai-agent:lab03 --name devopsdays
cd ..
```

4. Identidad, RBAC permisivo y target (antes de aplicar la ValidatingPolicy):

```bash
kubectl create namespace ai-agent-lab --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f lab03-ai-agent/agent-rbac.yaml
kubectl apply -f lab03-ai-agent/payment-api.yaml
```

### Selección de escenario del agente (`AGENT_SCENARIO`)

| Valor | Prompt | Job |
|---|---|---|
| `investigate` | Lista/inspecciona `payment-api`; **sin** autorización de borrado | `agent-job-investigate.yaml` |
| `authorized-delete` | Inspecciona y ejecuta `delete_deployment` sobre `payment-api` | `agent-job-delete.yaml` |

El agente lee el prompt desde `prompts/` según `AGENT_SCENARIO`. No hace falta editar `agent.py` entre demos; sí hay que reconstruir la imagen si cambias los archivos de prompt.

### Orden de operaciones RBAC (importante)

1. Aplica el Role **permisivo** (`agent-rbac.yaml` o `agent-rbac-permissive.yaml`) **antes** de `agent-rbac-policy.yaml`.
2. Demuestra borrado con `AGENT_SCENARIO=authorized-delete`.
3. Pasa a Role **restringido** con `agent-rbac-restricted.yaml` (admitido con o sin la ValidatingPolicy).
4. Aplica `agent-rbac-policy.yaml`.
5. Intentar volver al Role permisivo con la política activa debe fallar en admisión.

### Escenarios

**A) Investigar (sin autorización de borrado en el prompt)**

```bash
kubectl apply -f lab03-ai-agent/agent-rbac-restricted.yaml
kubectl apply -f lab03-ai-agent/payment-api.yaml

kubectl delete job ai-agent -n ai-agent-lab --ignore-not-found
kubectl apply -f lab03-ai-agent/agent-job-investigate.yaml
kubectl wait --for=condition=complete job/ai-agent -n ai-agent-lab --timeout=180s
kubectl logs job/ai-agent -n ai-agent-lab
```

Esperado: tool calls de `list_deployments` / `inspect_deployment`; el Deployment permanece.

**B1) Con permiso `delete` — el agente puede borrar**

```bash
# Solo si protect-ai-agent-permissions AÚN NO está aplicada:
kubectl apply -f lab03-ai-agent/agent-rbac-permissive.yaml
kubectl apply -f lab03-ai-agent/payment-api.yaml

kubectl delete job ai-agent -n ai-agent-lab --ignore-not-found
kubectl apply -f lab03-ai-agent/agent-job-delete.yaml
kubectl wait --for=condition=complete job/ai-agent -n ai-agent-lab --timeout=180s
kubectl logs job/ai-agent -n ai-agent-lab
kubectl get deploy payment-api -n ai-agent-lab
```

Esperado: tool call de borrado y el Deployment desaparece (si el modelo invoca la herramienta).

**B2) Sin permiso `delete` — Kubernetes responde 403**

```bash
kubectl apply -f lab03-ai-agent/payment-api.yaml
kubectl apply -f lab03-ai-agent/agent-rbac-restricted.yaml

kubectl delete job ai-agent -n ai-agent-lab --ignore-not-found
kubectl apply -f lab03-ai-agent/agent-job-delete.yaml
kubectl logs job/ai-agent -n ai-agent-lab
```

Esperado en logs: error HTTP **403 Forbidden** al intentar borrar.

**3) Kyverno Validate — no reintroducir permisos destructivos**

```bash
kubectl apply -f lab03-ai-agent/agent-rbac-policy.yaml

kubectl apply -f lab03-ai-agent/agent-rbac-permissive.yaml
# Esperado: Deny al actualizar ai-operator-role con verb delete
```

Para restaurar el Role permisivo en otra corrida del taller, elimina primero la ValidatingPolicy y luego reaplica el Role:

```bash
kubectl delete -f lab03-ai-agent/agent-rbac-policy.yaml
kubectl apply -f lab03-ai-agent/agent-rbac-permissive.yaml
```

**4) Kyverno Generate + Synchronize — Role de solo lectura**

```bash
./bootstrap/05-apply-kyverno-generate-rbac.sh
kubectl apply -f lab03-ai-agent/agent-generate-rbac.yaml
```

Si el ServiceAccount `ai-operator` ya existe, la política tiene `generateExisting.enabled: true`. Comprueba:

```bash
kubectl get role,rolebinding -n ai-agent-lab
kubectl get role ai-agent-readonly -n ai-agent-lab -o yaml
```

Prueba de synchronize (la política tiene `synchronize.enabled: true`):

```bash
kubectl delete role ai-agent-readonly -n ai-agent-lab
# tras unos segundos, Kyverno debería recrearlo
kubectl get role ai-agent-readonly -n ai-agent-lab
```

### Resultados esperados

| Capa | Efecto |
|---|---|
| RBAC | Autoriza o deniega (403) cada llamada a la API |
| ValidatingPolicy | Impide *admitir* un Role `ai-operator-role` con `delete` / `deletecollection` / `*` |
| GeneratingPolicy + Synchronize | Crea/restaura `ai-agent-readonly` (+ binding) gestionado por Kyverno |

### Cleanup

```bash
kubectl delete job ai-agent -n ai-agent-lab --ignore-not-found
kubectl delete -f lab03-ai-agent/payment-api.yaml --ignore-not-found
kubectl delete -f lab03-ai-agent/agent-rbac-policy.yaml --ignore-not-found
kubectl delete -f lab03-ai-agent/agent-generate-rbac.yaml --ignore-not-found
kubectl delete role ai-agent-readonly -n ai-agent-lab --ignore-not-found
kubectl delete rolebinding ai-agent-readonly-binding -n ai-agent-lab --ignore-not-found
kubectl delete -f lab03-ai-agent/kyverno-generate-permissions.yaml --ignore-not-found
kubectl delete -f lab03-ai-agent/kyverno-watch-rbac.yaml --ignore-not-found
kubectl delete -f lab03-ai-agent/agent-rbac.yaml --ignore-not-found
```

### Lecciones y límites

- **RBAC** decide en runtime; **Validate** gobierna qué Role se puede crear/actualizar; **Generate/Synchronize** reconcilia recursos generados.
- Synchronize **no** impide todos los cambios temporales de privilegio, ni evita que *otros* Roles/ClusterRoles otorguen permisos adicionales al mismo ServiceAccount.
- El agente solo permite borrar el nombre `payment-api` en código (`ALLOWED_DELETE`); eso es un freno de demo, no un control de plataforma.
- El prompt `investigate` no autoriza borrado, pero el control efectivo de plataforma sigue siendo RBAC (+ políticas).
- Requiere Ollama alcanzable vía `host.containers.internal` desde el cluster Podman/Kind.

---

## Lab 04 — ¿Quién desplegó ese modelo?

### Objetivo

Exigir metadatos organizacionales en Deployments de inferencia y completar ownership/costo desde labels del namespace.

### Riesgo

Sin labels, nadie puede responder con rigor: qué modelo corre, qué versión, qué equipo paga y a qué cost center pertenece.

### Arquitectura / componentes

- Namespace: `ai-traceability` (labels de plataforma en el namespace)
- Labels requeridos en el Deployment:
  - `ai.company.io/model`
  - `ai.company.io/version`
  - `ai.company.io/team`
  - `ai.company.io/cost-center`
- `ValidatingPolicy` + `MutatingPolicy`

### Manifests relevantes

| Archivo | Rol |
|---|---|
| `lab04-ai-traceability/inference-untracked.yaml` | Sin labels AI |
| `lab04-ai-traceability/inference-tracked.yaml` | Labels completos |
| `lab04-ai-traceability/inference-auto.yaml` | Solo model + version |
| `lab04-ai-traceability/ai-metadata-policy.yaml` | `ValidatingPolicy` |
| `lab04-ai-traceability/ai-metadata-mutate.yaml` | `MutatingPolicy` desde labels del namespace |

### Setup

```bash
kubectl create namespace ai-traceability --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace ai-traceability \
  ai.company.io/team=ml-platform \
  ai.company.io/cost-center=CC-1024 \
  --overwrite

kubectl delete deploy qwen-inference qwen-inference-auto \
  -n ai-traceability --ignore-not-found
kubectl delete -f lab04-ai-traceability/ai-metadata-policy.yaml --ignore-not-found
kubectl delete -f lab04-ai-traceability/ai-metadata-mutate.yaml --ignore-not-found
```

### Antes de la gobernanza

```bash
kubectl apply -f lab04-ai-traceability/inference-untracked.yaml
kubectl get deploy qwen-inference -n ai-traceability --show-labels
```

Kubernetes admite el Deployment sin metadatos AI.

### Después de la gobernanza

```bash
kubectl delete deploy qwen-inference -n ai-traceability --ignore-not-found
kubectl apply -f lab04-ai-traceability/ai-metadata-policy.yaml

kubectl apply -f lab04-ai-traceability/inference-untracked.yaml
# Esperado: Deny — faltan labels obligatorios

kubectl apply -f lab04-ai-traceability/inference-tracked.yaml
# Esperado: aceptado
kubectl get deploy qwen-inference -n ai-traceability --show-labels
```

**Mutación de ownership / cost center:**

```bash
kubectl apply -f lab04-ai-traceability/ai-metadata-mutate.yaml
kubectl apply -f lab04-ai-traceability/inference-auto.yaml

kubectl get deploy qwen-inference-auto -n ai-traceability -o jsonpath='{.metadata.labels}' ; echo
```

Esperado: el Deployment declara `model` y `version`; Kyverno añade `team=ml-platform` y `cost-center=CC-1024` desde el namespace, y la validación lo acepta.

### Cleanup

```bash
kubectl delete deploy qwen-inference qwen-inference-auto \
  -n ai-traceability --ignore-not-found
kubectl delete -f lab04-ai-traceability/ai-metadata-policy.yaml --ignore-not-found
kubectl delete -f lab04-ai-traceability/ai-metadata-mutate.yaml --ignore-not-found
```

### Lecciones y límites

- Los labels son **metadatos declarados**, no proveniencia criptográfica del modelo ni auditoría independiente.
- La mutación asume que el namespace ya trae `ai.company.io/team` y `ai.company.io/cost-center`.

---

## Consideraciones de seguridad

- Todo el material es para **laboratorio / charla**. No copies estos permisos, digests fijos ni excepciones a un cluster productivo sin rediseño.
- Mokka y el device plugin mock **no** sustituyen controles de GPU reales ni aislamiento de aceleradores.
- El checksum del Lab 02 es un ancla didáctica; en producción usarías firmas, attestations y registries de confianza.
- El agente del Lab 03 ejecuta tool calls reales contra la API. Mantén el namespace aislado y el target desechable.
- `.gitignore` excluye tokens, `.venv/`, `.env`, binarios `.gguf`, archivos `.tar` de imagen y artefactos locales. No los subas a Git.
- Kyverno Generate/Synchronize ayuda a drift de recursos generados; no es un sustituto completo de least privilege continuo ni de revisión de todos los RoleBindings.

---

## Limpieza global

```bash
# Workloads y políticas por lab
kubectl delete deployment,job,pod --all -n ai-dev --ignore-not-found
kubectl delete deployment,job,pod --all -n ai-ml --ignore-not-found
kubectl delete deployment,job,pod --all -n ai-prod --ignore-not-found
kubectl delete deployment,job,pod,pvc --all -n ai-supply --ignore-not-found
kubectl delete deployment,job,pod --all -n ai-agent-lab --ignore-not-found
kubectl delete deployment,job,pod --all -n ai-traceability --ignore-not-found

kubectl delete clusterpolicy restrict-ai-gpus --ignore-not-found
kubectl delete mutatingpolicy assign-gpus-by-environment assign-ai-ownership --ignore-not-found
kubectl delete validatingpolicy \
  require-ai-model-verification \
  restrict-ai-registries \
  protect-ai-agent-permissions \
  require-ai-model-metadata \
  --ignore-not-found
kubectl delete generatingpolicy generate-ai-agent-rbac --ignore-not-found

kubectl delete -f lab03-ai-agent/kyverno-generate-permissions.yaml --ignore-not-found
kubectl delete -f lab03-ai-agent/kyverno-watch-rbac.yaml --ignore-not-found
kubectl delete -f lab01-gpu/nvidia-device-plugin.yaml --ignore-not-found

# Opcional: borrar namespaces de labs
kubectl delete ns ai-dev ai-ml ai-prod ai-supply ai-agent-lab ai-traceability --ignore-not-found

# Opcional: desinstalar plataforma
helm uninstall nvml-mock -n mokka 2>/dev/null || true
helm uninstall kyverno -n kyverno 2>/dev/null || true
kind delete cluster --name devopsdays
```

---

## Referencias

- [Kubernetes Documentation](https://kubernetes.io/docs/home/)
- [Kubernetes RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [Kyverno Documentation](https://kyverno.io/docs/)
- [Kyverno policies.kyverno.io (Validating / Mutating / Generating)](https://kyverno.io/docs/policy-types/)
- [NVIDIA Mokka (k8s-test-infra)](https://nvidia.github.io/k8s-test-infra/)
- [Mokka — NVIDIA Device Plugin guide](https://nvidia.github.io/k8s-test-infra/guides/device-plugin/)
- [Ollama](https://github.com/ollama/ollama)
- [Kind](https://kind.sigs.k8s.io/)
- [CNCF — Cloud Native Glossary / proyectos](https://www.cncf.io/)
- [DevOpsDays](https://devopsdays.org/)

---

## DevOpsDays Bogotá 2026

Estos laboratorios acompañan la presentación **«Gobernanza en tiempos de IA»**: una mirada práctica a cómo la plataforma (Kubernetes + políticas de admisión + RBAC) puede poner límites claros a cargas y agentes de IA sin pretender que un solo control resuelva supply chain, safety del modelo o cumplimiento completo.

Si usas este material en tu comunidad o empresa, adapta namespaces, digests y permisos a tu contexto, y trata cada demo como punto de partida — no como checklist de producción.
