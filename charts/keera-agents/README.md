# Keera Agents Helm Chart

keera-agents Helm chart for Kubernetes

**Homepage:** <https://keera.ch>

Keera Agents runs AI agents on top of [Keera Gateway](../keera-gateway). The chart installs the control plane with the Kubernetes driver: each agent and workspace runs as a StatefulSet of its own in a separate namespace.

## Quickstart

This installs keera-agents together with the internal PostgreSQL database, next to a gateway installed with the keera-gateway chart in the namespace `keera`.

1. Create a Secret holding randomly generated credentials for keera-agents and the database:

   ```sh
   kubectl create secret generic keera-agents-credentials \
     --namespace keera \
     --from-literal=KEERA_AGENTS_SERVICE_KEY="$(openssl rand -hex 32)" \
     --from-literal=KEERA_AGENTS_SECRET_KEY="$(openssl rand -hex 32)" \
     --from-literal=password="$(openssl rand -hex 32)"
   ```

   The key names match the defaults of `credentials.existingSecret` and `database.internal.existingSecretPasswordKey`.

2. Set two variables on Keera Gateway and restart it: `KEERA_AGENTS_URL`, the `publicUrl` below, and `KEERA_AGENTS_SERVICE_KEY`, the same value as in the Secret.

3. Install the chart, referencing that Secret:

   ```sh
   helm upgrade --install keera-agents oci://ghcr.io/bespinian/keera-helm-charts/keera-agents \
     --version 0.1.0 \
     --namespace keera \
     --set publicUrl=https://agents.example.ch \
     --set gateway.url=https://keera.example.ch \
     --set gateway.internalUrl=http://keera-gateway.keera.svc \
     --set credentials.existingSecret.name=keera-agents-credentials \
     --set database.internal.existingSecret=keera-agents-credentials
   ```

4. Wait for keera-agents to become ready:

   ```sh
   kubectl --namespace keera rollout status deployment/keera-agents
   ```

Keep the Secret when uninstalling the release: the database only accepts the password it was initialized with, and without `KEERA_AGENTS_SECRET_KEY` every stored connector credential is unreadable.

## Where agents run

Agents run in `agents.namespace.name`, `<release namespace>-agents` by default, and never in the release namespace: whoever reads pods there reads runtime tokens. The chart creates it with the `restricted` Pod Security Standard and keeps it on uninstall, since it holds the agents' workspaces. Delete it yourself to remove them.

In that namespace the chart creates:

- a Role and RoleBinding that let keera-agents manage StatefulSets and read pods (`agents.rbac.create`),
- a default-deny NetworkPolicy that lets agents reach only DNS, Keera Gateway and keera-agents, and one that lets keera-agents reach workspaces (`agents.networkPolicy.enabled`). The CNI must enforce them.

Agents reach Keera Gateway at `gateway.internalUrl`. The NetworkPolicy allows the pods matching `agents.networkPolicy.gateway`, by default keera-gateway's pods in the release namespace on port 8080. Add further destinations, such as an internal package proxy, to `agents.networkPolicy.extraEgress`.

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
| agents.idleSuspend | string | `""` |  |
| agents.image.repository | string | `"ghcr.io/bespinian/keera-agent"` |  |
| agents.image.tag | string | `""` |  |
| agents.imagePullSecrets | list | `[]` |  |
| agents.maxCpu | string | `""` |  |
| agents.maxDisk | string | `""` |  |
| agents.maxMemory | string | `""` |  |
| agents.minIsolation | string | `""` |  |
| agents.namespace.annotations | object | `{}` |  |
| agents.namespace.create | bool | `true` |  |
| agents.namespace.labels."pod-security.kubernetes.io/enforce" | string | `"restricted"` |  |
| agents.namespace.name | string | `""` |  |
| agents.networkPolicy.dns.namespaceSelector.matchLabels."kubernetes.io/metadata.name" | string | `"kube-system"` |  |
| agents.networkPolicy.dns.podSelector.matchLabels.k8s-app | string | `"kube-dns"` |  |
| agents.networkPolicy.enabled | bool | `true` |  |
| agents.networkPolicy.extraEgress | list | `[]` |  |
| agents.networkPolicy.gateway.namespace | string | `""` |  |
| agents.networkPolicy.gateway.podSelector.matchLabels."app.kubernetes.io/name" | string | `"keera-gateway"` |  |
| agents.networkPolicy.gateway.port | int | `8080` |  |
| agents.rbac.create | bool | `true` |  |
| agents.runtimeClasses.isolated | string | `""` |  |
| agents.runtimeClasses.standard | string | `""` |  |
| agents.runtimeClasses.vm | string | `""` |  |
| agents.serviceAccount | string | `""` |  |
| agents.storageClass | string | `""` |  |
| agents.userNamespaces | bool | `false` |  |
| controlPlane.affinity | object | `{}` |  |
| controlPlane.autoscaling.enabled | bool | `false` |  |
| controlPlane.autoscaling.maxReplicas | int | `100` |  |
| controlPlane.autoscaling.minReplicas | int | `1` |  |
| controlPlane.autoscaling.targetCPUUtilizationPercentage | int | `80` |  |
| controlPlane.httpRoute.annotations | object | `{}` |  |
| controlPlane.httpRoute.enabled | bool | `false` |  |
| controlPlane.httpRoute.hostnames | list | `[]` |  |
| controlPlane.httpRoute.labels | object | `{}` |  |
| controlPlane.httpRoute.parentRefs | list | `[]` |  |
| controlPlane.httpRoute.rules[0].matches[0].path.type | string | `"PathPrefix"` |  |
| controlPlane.httpRoute.rules[0].matches[0].path.value | string | `"/"` |  |
| controlPlane.image.pullPolicy | string | `"IfNotPresent"` |  |
| controlPlane.image.repository | string | `"ghcr.io/bespinian/keera-agents"` |  |
| controlPlane.image.tag | string | `""` |  |
| controlPlane.ingress.annotations | object | `{}` |  |
| controlPlane.ingress.enabled | bool | `false` |  |
| controlPlane.ingress.extraHosts | list | `[]` |  |
| controlPlane.ingress.extraTls | list | `[]` |  |
| controlPlane.ingress.hostname | string | `""` |  |
| controlPlane.ingress.ingressClassName | string | `""` |  |
| controlPlane.ingress.labels | object | `{}` |  |
| controlPlane.ingress.path | string | `"/"` |  |
| controlPlane.ingress.pathType | string | `"Prefix"` |  |
| controlPlane.ingress.tls | bool | `false` |  |
| controlPlane.nodeSelector | object | `{}` |  |
| controlPlane.podAnnotations | object | `{}` |  |
| controlPlane.podLabels | object | `{}` |  |
| controlPlane.podSecurityContext.runAsNonRoot | bool | `true` |  |
| controlPlane.podSecurityContext.seccompProfile.type | string | `"RuntimeDefault"` |  |
| controlPlane.replicaCount | int | `1` |  |
| controlPlane.resources | object | `{}` |  |
| controlPlane.securityContext.allowPrivilegeEscalation | bool | `false` |  |
| controlPlane.securityContext.capabilities.drop[0] | string | `"ALL"` |  |
| controlPlane.securityContext.readOnlyRootFilesystem | bool | `true` |  |
| controlPlane.service.port | int | `80` |  |
| controlPlane.service.type | string | `"ClusterIP"` |  |
| controlPlane.serviceAccount.annotations | object | `{}` |  |
| controlPlane.serviceAccount.create | bool | `true` |  |
| controlPlane.serviceAccount.name | string | `""` |  |
| controlPlane.tolerations | list | `[]` |  |
| controlPlane.volumeMounts | list | `[]` |  |
| controlPlane.volumes | list | `[]` |  |
| credentials.existingSecret.metricsTokenSecretKey | string | `""` |  |
| credentials.existingSecret.name | string | `""` |  |
| credentials.existingSecret.secretSecretKey | string | `"KEERA_AGENTS_SECRET_KEY"` |  |
| credentials.existingSecret.serviceSecretKey | string | `"KEERA_AGENTS_SERVICE_KEY"` |  |
| credentials.metricsToken | string | `""` |  |
| credentials.secretKey | string | `""` |  |
| credentials.serviceKey | string | `""` |  |
| database.external.existingSecret | string | `""` |  |
| database.external.existingSecretUrlKey | string | `"url"` |  |
| database.external.url | string | `""` |  |
| database.internal.affinity | object | `{}` |  |
| database.internal.database | string | `"keera_agents"` |  |
| database.internal.existingSecret | string | `""` |  |
| database.internal.existingSecretPasswordKey | string | `"password"` |  |
| database.internal.extraEnvVars | list | `[]` |  |
| database.internal.image.pullPolicy | string | `"IfNotPresent"` |  |
| database.internal.image.repository | string | `"docker.io/library/postgres"` |  |
| database.internal.image.tag | string | `"18"` |  |
| database.internal.livenessProbe.failureThreshold | int | `6` |  |
| database.internal.livenessProbe.initialDelaySeconds | int | `30` |  |
| database.internal.livenessProbe.periodSeconds | int | `10` |  |
| database.internal.livenessProbe.timeoutSeconds | int | `5` |  |
| database.internal.nodeSelector | object | `{}` |  |
| database.internal.password | string | `""` |  |
| database.internal.persistence.accessMode | string | `"ReadWriteOnce"` |  |
| database.internal.persistence.annotations | object | `{}` |  |
| database.internal.persistence.enabled | bool | `true` |  |
| database.internal.persistence.existingClaim | string | `""` |  |
| database.internal.persistence.size | string | `"1Gi"` |  |
| database.internal.persistence.storageClass | string | `""` |  |
| database.internal.podAnnotations | object | `{}` |  |
| database.internal.podLabels | object | `{}` |  |
| database.internal.podSecurityContext.fsGroup | int | `999` |  |
| database.internal.podSecurityContext.fsGroupChangePolicy | string | `"OnRootMismatch"` |  |
| database.internal.podSecurityContext.runAsGroup | int | `999` |  |
| database.internal.podSecurityContext.runAsUser | int | `999` |  |
| database.internal.readinessProbe.failureThreshold | int | `3` |  |
| database.internal.readinessProbe.initialDelaySeconds | int | `5` |  |
| database.internal.readinessProbe.periodSeconds | int | `10` |  |
| database.internal.readinessProbe.timeoutSeconds | int | `5` |  |
| database.internal.resources | object | `{}` |  |
| database.internal.securityContext.allowPrivilegeEscalation | bool | `false` |  |
| database.internal.securityContext.capabilities.drop[0] | string | `"ALL"` |  |
| database.internal.shmSizeLimit | string | `"512Mi"` |  |
| database.internal.tolerations | list | `[]` |  |
| database.internal.username | string | `"keera"` |  |
| database.type | string | `"internal"` |  |
| extraEnvVars | list | `[]` |  |
| fullnameOverride | string | `""` |  |
| gateway.internalUrl | string | `""` |  |
| gateway.url | string | `""` |  |
| imagePullSecrets | list | `[]` |  |
| logFormat | string | `""` |  |
| logLevel | string | `""` |  |
| nameOverride | string | `""` |  |
| prices.cpuHour | string | `""` |  |
| prices.diskGiBMonth | string | `""` |  |
| prices.memoryGiBHour | string | `""` |  |
| publicUrl | string | `""` |  |
| taskTimeout | string | `""` |  |
| upstreamDeny | string | `""` |  |
| upstreamPrivate | string | `""` |  |
| watchInterval | string | `""` |  |
| workspaces.idleSuspend | string | `""` |  |
| workspaces.image.repository | string | `"ghcr.io/bespinian/keera-workspace"` |  |
| workspaces.image.tag | string | `""` |  |
