# Keera Agents Helm Chart

Installs Keera Agents in a Kubernetes cluster.

**Homepage:** <https://keera.ch/en/agents>

Keera Agents runs AI agents on top of [Keera Gateway](../keera-gateway). The chart installs the control plane with the Kubernetes driver: each agent and workspace runs as a StatefulSet of its own in a separate namespace.

## Quickstart

This installs keera-agents together with the internal PostgreSQL database, in the namespace `keera-agents`, next to a gateway installed with the keera-gateway chart in the namespace `keera-gateway`.

1. Create a namespace and a Secret holding randomly generated credentials for keera-agents and the database:

   ```sh
   kubectl create namespace keera-agents

   kubectl create secret generic keera-agents-credentials \
     --namespace keera-agents \
     --from-literal=KEERA_AGENTS_SERVICE_KEY="$(openssl rand -hex 32)" \
     --from-literal=KEERA_AGENTS_SECRET_KEY="$(openssl rand -hex 32)" \
     --from-literal=password="$(openssl rand -hex 32)"
   ```

   The key names match the defaults of `credentials.existingSecret` and `database.internal.existingSecretPasswordKey`.

2. Set two variables on Keera Gateway and restart it: `KEERA_AGENTS_URL`, the `publicUrl` below, and `KEERA_AGENTS_SERVICE_KEY`, the same value as in the Secret.

3. Install the chart, referencing that Secret:

   ```sh
   helm upgrade --install keera-agents oci://ghcr.io/bespinian/keera-helm-charts/keera-agents \
     --version 0.1.4 \
     --namespace keera-agents \
     --set publicUrl=https://agents.example.ch \
     --set gateway.url=https://keera.example.ch \
     --set gateway.internalUrl=http://keera-gateway.keera-gateway.svc \
     --set agents.networkPolicy.gateway.namespace=keera-gateway \
     --set credentials.existingSecret.name=keera-agents-credentials \
     --set database.internal.existingSecret=keera-agents-credentials
   ```

4. Wait for keera-agents to become ready:

   ```sh
   kubectl --namespace keera-agents rollout status deployment/keera-agents
   ```

5. Forward the keera-agents Service to your machine, it is then reachable at <http://localhost:8070>:

   ```sh
   kubectl --namespace keera-agents port-forward services/keera-agents 8070:80
   ```

Keep the Secret when uninstalling the release: the database only accepts the password it was initialized with, and without `KEERA_AGENTS_SECRET_KEY` every stored connector credential is unreadable.

## Where agents run

Agents run in `agents.namespace.name`, `<release namespace>-sandbox` by default (`keera-agents-sandbox` in the quickstart), and never in the release namespace: whoever reads pods there reads runtime tokens. The chart creates it with the `restricted` Pod Security Standard and keeps it on uninstall, since it holds the agents' workspaces. Delete it yourself to remove them.

In that namespace the chart creates:

- a Role and RoleBinding that let keera-agents manage StatefulSets and read pods (`agents.rbac.create`),
- a default-deny NetworkPolicy that lets agents reach only DNS, Keera Gateway and keera-agents, and one that lets keera-agents reach workspaces (`agents.networkPolicy.enabled`). The CNI must enforce them.

Agents reach Keera Gateway at `gateway.internalUrl`. The NetworkPolicy allows the pods matching `agents.networkPolicy.gateway`, by default keera-gateway's pods in the release namespace on port 8080. Set `agents.networkPolicy.gateway.namespace` when the gateway runs in a namespace of its own, as in the quickstart. Add further destinations, such as an internal package proxy, to `agents.networkPolicy.extraEgress`.

Isolation tiers need RuntimeClasses: set `agents.runtimeClasses.isolated` for gVisor and `agents.runtimeClasses.vm` for Kata. See [agents.md](https://github.com/bespinian/keera-agents/blob/main/docs/agents.md) for the hardening the cluster has to provide, such as `podPidsLimit` on the kubelet.

## Exposing keera-agents

People, chat services and the `keera` command line reach keera-agents at `publicUrl`. Expose it through `controlPlane.ingress` or `controlPlane.httpRoute`, and keep in mind:

- `/runtime` and `/metrics` are only needed inside the cluster. Block them at your proxy if it can.
- Workspaces take connections over with Upgrade requests. The proxy must pass them on over HTTP/1.1 and not cut idle connections short.

## Database

With `database.type: internal` (the default), the chart deploys a single PostgreSQL instance as a StatefulSet and wires up `KEERA_AGENTS_DATABASE_URL` automatically. The password has no default, set either `database.internal.password` or `database.internal.existingSecret`. PostgreSQL applies the username, password and database name only when it initializes an empty data directory.

With `database.type: external`, set `database.external.url` or reference a Secret holding it through `database.external.existingSecret`.

## Backups

Back up the database, `KEERA_AGENTS_SECRET_KEY` and the agents' workspaces, the PVCs labelled `app.kubernetes.io/managed-by=keera-agents` in the agents' namespace, on the same schedule. See [install.md](https://github.com/bespinian/keera-agents/blob/main/docs/install.md#backups).

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| agents.idleSuspend | string | `""` | Suspend an agent with nothing to do for this long, "0" never. Empty is 15m. |
| agents.image.repository | string | `"ghcr.io/bespinian/keera-agent"` | Image of the agents. |
| agents.image.tag | string | `""` | Overrides the image tag whose default is the chart appVersion. |
| agents.imagePullSecrets | list | `[]` | Secrets in agents.namespace to pull the agent and workspace images with, as names or as {name: ...} like the top-level imagePullSecrets. |
| agents.maxCpu | string | `""` | The most CPUs one agent may ask for. Empty is 8. |
| agents.maxDisk | string | `""` | The most disk one agent may ask for. Empty is 100Gi. |
| agents.maxMemory | string | `""` | The most memory one agent may ask for. Empty is 32Gi. |
| agents.minIsolation | string | `""` | The weakest tier agents may choose: standard, isolated or vm. Empty is standard. |
| agents.namespace.annotations | object | `{}` | Annotations of the namespace. |
| agents.namespace.create | bool | `true` | Create the namespace. It is kept on uninstall, since it holds the agents' workspaces. |
| agents.namespace.labels | object | `{"pod-security.kubernetes.io/enforce":"restricted"}` | Labels of the namespace. The default makes agents' pods meet the restricted Pod Security Standard. |
| agents.namespace.name | string | `""` | Where agents run. Empty is "<release namespace>-sandbox". Agents need a namespace of their own: whoever reads pods there reads runtime tokens. |
| agents.networkPolicy.dns | object | `{"namespaceSelector":{"matchLabels":{"kubernetes.io/metadata.name":"kube-system"}},"podSelector":{"matchLabels":{"k8s-app":"kube-dns"}}}` | Where DNS answers. |
| agents.networkPolicy.enabled | bool | `true` | Create a default-deny NetworkPolicy for agents.namespace. It allows DNS, Keera Gateway and keera-agents, and lets keera-agents reach workspaces. The CNI must enforce it. |
| agents.networkPolicy.extraEgress | list | `[]` | Further egress rules, such as an internal package proxy. |
| agents.networkPolicy.gateway.namespace | string | `""` | Namespace Keera Gateway's pods run in. Empty is the release namespace. |
| agents.networkPolicy.gateway.podSelector | object | `{"matchLabels":{"app.kubernetes.io/name":"keera-gateway"}}` | Selects Keera Gateway's pods. |
| agents.networkPolicy.gateway.port | int | `8080` | Port Keera Gateway's pods listen on. |
| agents.rbac.create | bool | `true` | Create the Role keera-agents needs in agents.namespace. |
| agents.runtimeClasses.isolated | string | `""` | RuntimeClass of the isolated tier, gVisor, such as gvisor. |
| agents.runtimeClasses.standard | string | `""` | RuntimeClass of the standard tier. Empty is the cluster's default runtime. |
| agents.runtimeClasses.vm | string | `""` | RuntimeClass of the vm tier, Kata, such as kata. |
| agents.serviceAccount | string | `""` | ServiceAccount agents run as, in agents.namespace. Its token is never mounted. Empty is the namespace's default. |
| agents.storageClass | string | `""` | StorageClass workspaces are provisioned from. Empty is the cluster's default. |
| agents.userNamespaces | bool | `false` | Run standard-tier pods in a user namespace of their own. Needs Kubernetes 1.33 and a container runtime that supports it. |
| controlPlane.affinity | object | `{}` | Affinity of the pods. |
| controlPlane.autoscaling.enabled | bool | `false` | Create a HorizontalPodAutoscaler, which then sets the replicas. |
| controlPlane.autoscaling.maxReplicas | int | `100` | The most replicas. |
| controlPlane.autoscaling.minReplicas | int | `1` | The fewest replicas. |
| controlPlane.autoscaling.targetCPUUtilizationPercentage | int | `80` | CPU utilization to scale at. |
| controlPlane.httpRoute.annotations | object | `{}` | Annotations of the HTTPRoute. |
| controlPlane.httpRoute.enabled | bool | `false` | Create an HTTPRoute. |
| controlPlane.httpRoute.hostnames | list | `[]` | Host names of the HTTPRoute. Empty matches any host. |
| controlPlane.httpRoute.labels | object | `{}` | Labels of the HTTPRoute. |
| controlPlane.httpRoute.parentRefs | list | `[]` | Gateways the route attaches to. |
| controlPlane.httpRoute.rules | list | `[{"matches":[{"path":{"type":"PathPrefix","value":"/"}}]}]` | Rules of the HTTPRoute. The backend is always the keera-agents service; each rule may set matches, filters and timeouts. |
| controlPlane.image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. |
| controlPlane.image.repository | string | `"ghcr.io/bespinian/keera-agents"` | Image of keera-agents. |
| controlPlane.image.tag | string | `""` | Overrides the image tag whose default is the chart appVersion. |
| controlPlane.ingress.annotations | object | `{}` | Annotations of the Ingress. |
| controlPlane.ingress.enabled | bool | `false` | Create an Ingress. |
| controlPlane.ingress.extraHosts | list | `[]` | Further host names, path and pathType default to the ones above. |
| controlPlane.ingress.extraTls | list | `[]` | Further TLS entries. |
| controlPlane.ingress.hostname | string | `""` | Host name of the Ingress. Empty matches any host. |
| controlPlane.ingress.ingressClassName | string | `""` | IngressClass of the Ingress. |
| controlPlane.ingress.labels | object | `{}` | Labels of the Ingress. |
| controlPlane.ingress.path | string | `"/"` | Path of the Ingress. |
| controlPlane.ingress.pathType | string | `"Prefix"` | Path type of the Ingress. |
| controlPlane.ingress.tls | bool | `false` | TLS for hostname and extraHosts from the Secret <fullname>-tls. |
| controlPlane.nodeSelector | object | `{}` | Node selector of the pods. |
| controlPlane.podAnnotations | object | `{}` | Annotations of the pods. |
| controlPlane.podLabels | object | `{}` | Labels of the pods. |
| controlPlane.podSecurityContext | object | `{"runAsNonRoot":true,"seccompProfile":{"type":"RuntimeDefault"}}` | Security context of the pods. |
| controlPlane.replicaCount | int | `1` | Several replicas are fine, periodic work is coordinated in the database. |
| controlPlane.resources | object | `{}` | Resources of the keera-agents container. |
| controlPlane.securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true}` | Security context of the keera-agents container. |
| controlPlane.service.port | int | `80` | Port of the Service. |
| controlPlane.service.type | string | `"ClusterIP"` | Type of the Service. |
| controlPlane.serviceAccount.annotations | object | `{}` | Annotations of the ServiceAccount. |
| controlPlane.serviceAccount.create | bool | `true` | Create a ServiceAccount. |
| controlPlane.serviceAccount.name | string | `""` | Name of the ServiceAccount. Empty is the full name when create is true, and the namespace's default otherwise. |
| controlPlane.tolerations | list | `[]` | Tolerations of the pods. |
| controlPlane.volumeMounts | list | `[]` | Further volume mounts of the keera-agents container. |
| controlPlane.volumes | list | `[]` | Further volumes of the pods. |
| credentials.existingSecret.metricsTokenSecretKey | string | `""` | Key in the existing Secret holding the metrics token. Empty turns /metrics off. |
| credentials.existingSecret.name | string | `""` | Use this existing Secret instead. When set, the values above are ignored. |
| credentials.existingSecret.secretSecretKey | string | `"KEERA_AGENTS_SECRET_KEY"` | Key in the existing Secret holding the secret key. |
| credentials.existingSecret.serviceSecretKey | string | `"KEERA_AGENTS_SERVICE_KEY"` | Key in the existing Secret holding the service key. |
| credentials.metricsToken | string | `""` | Bearer token for /metrics, at least 16 characters. Empty turns /metrics off. |
| credentials.secretKey | string | `""` | Seals cookies, agents' keys and connector credentials, at least 16 characters. Required unless existingSecret.name is set. Back it up with the database: without it every stored credential is unreadable. |
| credentials.serviceKey | string | `""` | The same value as KEERA_AGENTS_SERVICE_KEY on Keera Gateway, at least 32 characters. Required unless existingSecret.name is set. |
| database.external.existingSecret | string | `""` | Use an existing Secret for the URL instead. |
| database.external.existingSecretUrlKey | string | `"url"` | Key in the existing Secret holding the URL. |
| database.external.url | string | `""` | Connection URL, such as postgres://keera:...@db:5432/keera_agents. Required unless existingSecret is set. |
| database.internal.affinity | object | `{}` | Affinity of the pod. |
| database.internal.database | string | `"keera_agents"` | Database created on first start. |
| database.internal.existingSecret | string | `""` | Use an existing Secret for the password instead of creating one. |
| database.internal.existingSecretPasswordKey | string | `"password"` | Key in the existing Secret holding the password. |
| database.internal.extraEnvVars | list | `[]` | Further environment variables of the PostgreSQL container. |
| database.internal.image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. |
| database.internal.image.repository | string | `"docker.io/library/postgres"` | Image of PostgreSQL. |
| database.internal.image.tag | string | `"18"` | Tag of the PostgreSQL image. |
| database.internal.livenessProbe | object | `{"failureThreshold":6,"initialDelaySeconds":30,"periodSeconds":10,"timeoutSeconds":5}` | Liveness probe timings. |
| database.internal.nodeSelector | object | `{}` | Node selector of the pod. |
| database.internal.password | string | `""` | Password of the superuser. Required unless existingSecret is set. |
| database.internal.persistence.accessMode | string | `"ReadWriteOnce"` | Access mode of the PersistentVolumeClaim. |
| database.internal.persistence.annotations | object | `{}` | Annotations of the PersistentVolumeClaim. |
| database.internal.persistence.enabled | bool | `true` | Store data on a PersistentVolumeClaim. If disabled, data is stored in an emptyDir and lost when the pod is deleted. |
| database.internal.persistence.existingClaim | string | `""` | Use an existing PersistentVolumeClaim instead of creating one. |
| database.internal.persistence.size | string | `"1Gi"` | Size of the PersistentVolumeClaim. |
| database.internal.persistence.storageClass | string | `""` | Empty uses the cluster default StorageClass, "-" disables dynamic provisioning. |
| database.internal.podAnnotations | object | `{}` | Annotations of the pod. |
| database.internal.podLabels | object | `{}` | Labels of the pod. |
| database.internal.podSecurityContext | object | `{"fsGroup":999,"fsGroupChangePolicy":"OnRootMismatch","runAsGroup":999,"runAsNonRoot":true,"runAsUser":999,"seccompProfile":{"type":"RuntimeDefault"}}` | Security context of the pod. The official image runs PostgreSQL as uid/gid 999. |
| database.internal.readinessProbe | object | `{"failureThreshold":3,"initialDelaySeconds":5,"periodSeconds":10,"timeoutSeconds":5}` | Readiness probe timings. |
| database.internal.resources | object | `{}` | Resources of the PostgreSQL container. |
| database.internal.securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}` | Security context of the PostgreSQL container. |
| database.internal.shmSizeLimit | string | `"512Mi"` | Size limit of /dev/shm, PostgreSQL uses it for shared_buffers. |
| database.internal.tolerations | list | `[]` | Tolerations of the pod. |
| database.internal.username | string | `"keera"` | Superuser created on first start, also owner of the database below. |
| database.type | string | `"internal"` | "internal" deploys a single PostgreSQL instance as part of this release, "external" uses database.external. |
| extraEnvVars | list | `[]` | Further environment variables of the keera-agents container. |
| fullnameOverride | string | `""` | Overrides the full name of the release's resources. |
| gateway.internalUrl | string | `""` | Keera Gateway as keera-agents and agents reach it, such as http://keera-gateway.keera-gateway.svc. Empty is gateway.url, which the agents' NetworkPolicy blocks unless agents.networkPolicy.extraEgress allows it. |
| gateway.url | string | `""` | Required. Keera Gateway as a browser reaches it, such as https://keera.example.ch. |
| imagePullSecrets | list | `[]` | Secrets to pull the keera-agents and internal database images with. Agents use agents.imagePullSecrets. See https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/ |
| logFormat | string | `""` | text or json. Empty is text. |
| logLevel | string | `""` | debug, info, warn or error. Empty is info. |
| nameOverride | string | `""` | Overrides the chart name. |
| prices.cpuHour | string | `""` | Price of a CPU hour. Empty is free. |
| prices.diskGiBMonth | string | `""` | Price of a GiB month of disk. Empty is free. |
| prices.memoryGiBHour | string | `""` | Price of a GiB hour of memory. Empty is free. |
| publicUrl | string | `""` | The address browsers and chat services reach keera-agents on, without a path, such as https://agents.example.ch. Set it on Keera Gateway as KEERA_AGENTS_URL too. |
| taskTimeout | string | `""` | The longest a task may run, such as 30m. Empty is 30m. |
| upstreamDeny | string | `""` | Addresses connectors never reach. Empty keeps the default of loopback and cloud metadata, "none" turns it off. |
| upstreamPrivate | string | `""` | Hosts inside the network connectors may reach, such as gitlab.internal, or "all". Empty is "none": public addresses only. |
| watchInterval | string | `""` | How often watched folders are checked, at least 30s. Empty is 5m. |
| workspaces.idleSuspend | string | `""` | Suspend a workspace nobody is connected to for this long, "0" never. Empty is 2h. |
| workspaces.image.repository | string | `"ghcr.io/bespinian/keera-workspace"` | Image of the workspaces. |
| workspaces.image.tag | string | `""` | Overrides the image tag whose default is the chart appVersion. |
