# Keera Gateway Helm Chart

Installs Keera Gateway in a Kubernetes cluster.

**Homepage:** <https://keera.ch/en/gateway>

## Quickstart

This installs the gateway together with the internal PostgreSQL database.

1. Create a namespace and a Secret holding randomly generated credentials for the gateway and the database:

   ```sh
   kubectl create namespace keera-gateway

   kubectl create secret generic keera-gateway-credentials \
     --namespace keera-gateway \
     --from-literal=KEERA_OPERATOR_KEY="$(openssl rand -hex 32)" \
     --from-literal=KEERA_SECRET_KEY="$(openssl rand -hex 32)" \
     --from-literal=password="$(openssl rand -hex 32)"
   ```

   The key names match the defaults of `credentials.existingSecret` and `database.internal.existingSecretPasswordKey`.

2. Install the chart, referencing that Secret:

   ```sh
   helm upgrade --install keera-gateway oci://ghcr.io/bespinian/keera-helm-charts/keera-gateway \
     --version 0.1.3 \
     --namespace keera-gateway \
     --set credentials.existingSecret.name=keera-gateway-credentials \
     --set database.internal.existingSecret=keera-gateway-credentials
   ```

3. Wait for the gateway to become ready:

   ```sh
   kubectl --namespace keera-gateway rollout status deployment/keera-gateway
   ```

4. Forward the gateway Service to your machine, it is then reachable at <http://localhost:8080>:

   ```sh
   kubectl --namespace keera-gateway port-forward services/keera-gateway 8080:80
   ```

5. Print the operator key:

   ```sh
   kubectl --namespace keera-gateway get secret keera-gateway-credentials \
     -o template='{{ index .data "KEERA_OPERATOR_KEY" | base64decode }}'
   ```

Keep the Secret when uninstalling the release: the database only accepts the password it was initialized with, see [Database](#database).

## Database

The chart deploys a single PostgreSQL instance as a StatefulSet next to the gateway and wires up `KEERA_DATABASE_URL` automatically. Data is stored on a PersistentVolumeClaim, see `database.internal.persistence`.

The password has no default, set either `database.internal.password` or `database.internal.existingSecret`. PostgreSQL applies the username, password and database name only when it initializes an empty data directory. Changing them later in the values does not update the existing database and breaks the gateway's connection.

## Single sign-on

Without OIDC, the control panel accepts only the operator key. To sign in through an identity provider, set `oidc.enabled`, `publicUrl` (the address a browser reaches the gateway on, whose `/control/auth/callback` every provider's client registration has to list) and either:

- `oidc.issuer`, `oidc.clientId` and `oidc.clientSecret` for a single directory, which becomes a provider named `oidc.name` (`sso` by default), or
- `oidc.providers`, a list of entries with their own `name`, `issuer`, `clientId` and `clientSecret`, for a sign-in button per directory. Each entry needs `domains` then.

A provider's `name` ends up in every identity it writes, so do not change it later. The gateway shares no setting between providers, so the chart copies `adminGroups`, `operatorGroups`, `groupsClaim`, `defaultRole`, `scopes`, `domains` and `signup` into each provider that does not set its own.

Instead of a `clientSecret`, each of them can reference an existing Secret through `existingSecret` and `existingSecretKey`. Client secrets set in the values are stored in a separate `<release>-keera-gateway-oidc` Secret.

The operator role is never assignable through the panel, so it comes from `oidc.operatorGroups` or from the email addresses in `operators`. See the [SSO documentation](https://github.com/bespinian/keera-gateway/blob/main/docs/sso.md) for the provider-specific setup.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| credentials.existingSecret.name | string | `""` | Use this existing Secret instead. When set, operatorKey and secretKey above are ignored. |
| credentials.existingSecret.operatorSecretKey | string | `"KEERA_OPERATOR_KEY"` | Key in the existing Secret holding the operator key. |
| credentials.existingSecret.secretSecretKey | string | `"KEERA_SECRET_KEY"` | Key in the existing Secret holding the secret key. |
| credentials.operatorKey | string | `""` | Operator key. Required unless existingSecret.name is set. |
| credentials.secretKey | string | `""` | Secret key. Required unless existingSecret.name is set. |
| database.internal.affinity | object | `{}` | Affinity of the pod. |
| database.internal.database | string | `"keera_gateway"` | Database created on first start. |
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
| database.internal.podSecurityContext | object | `{"fsGroup":999,"fsGroupChangePolicy":"OnRootMismatch","runAsGroup":999,"runAsUser":999}` | Security context of the pod. The official image runs PostgreSQL as uid/gid 999. |
| database.internal.readinessProbe | object | `{"failureThreshold":3,"initialDelaySeconds":5,"periodSeconds":10,"timeoutSeconds":5}` | Readiness probe timings. |
| database.internal.resources | object | `{}` | Resources of the PostgreSQL container. |
| database.internal.securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}` | Security context of the PostgreSQL container. |
| database.internal.shmSizeLimit | string | `"512Mi"` | Size limit of /dev/shm, PostgreSQL uses it for shared_buffers. |
| database.internal.tolerations | list | `[]` | Tolerations of the pod. |
| database.internal.username | string | `"keera"` | Superuser created on first start, also owner of the database below. |
| fullnameOverride | string | `""` | Overrides the full name of the release's resources. |
| gateway.affinity | object | `{}` | Affinity of the pods. |
| gateway.autoscaling.enabled | bool | `false` | Create a HorizontalPodAutoscaler, which then sets the replicas. |
| gateway.autoscaling.maxReplicas | int | `100` | The most replicas. |
| gateway.autoscaling.minReplicas | int | `1` | The fewest replicas. |
| gateway.autoscaling.targetCPUUtilizationPercentage | int | `80` | CPU utilization to scale at. |
| gateway.httpRoute.annotations | object | `{}` | Annotations of the HTTPRoute. |
| gateway.httpRoute.enabled | bool | `false` | Create an HTTPRoute. |
| gateway.httpRoute.hostnames | list | `[]` | Host names of the HTTPRoute. Empty matches any host. |
| gateway.httpRoute.labels | object | `{}` | Labels of the HTTPRoute. |
| gateway.httpRoute.parentRefs | list | `[]` | Gateways the route attaches to. |
| gateway.httpRoute.rules | list | `[{"matches":[{"path":{"type":"PathPrefix","value":"/"}}]}]` | Rules of the HTTPRoute. The backend is always the gateway's service; each rule may set matches, filters and timeouts. |
| gateway.image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. |
| gateway.image.repository | string | `"ghcr.io/bespinian/keera-gateway"` | Image of the gateway. |
| gateway.image.tag | string | `""` | Overrides the image tag whose default is the chart appVersion. |
| gateway.ingress.annotations | object | `{}` | Annotations of the Ingress. |
| gateway.ingress.enabled | bool | `false` | Create an Ingress. |
| gateway.ingress.extraHosts | list | `[]` | Further host names, path and pathType default to the ones above. |
| gateway.ingress.extraTls | list | `[]` | Further TLS entries. |
| gateway.ingress.hostname | string | `""` | Host name of the Ingress. Empty matches any host. |
| gateway.ingress.ingressClassName | string | `""` | IngressClass of the Ingress. |
| gateway.ingress.labels | object | `{}` | Labels of the Ingress. |
| gateway.ingress.path | string | `"/"` | Path of the Ingress. |
| gateway.ingress.pathType | string | `"Prefix"` | Path type of the Ingress. |
| gateway.ingress.tls | bool | `false` | TLS for hostname and extraHosts from the Secret <fullname>-tls. |
| gateway.nodeSelector | object | `{}` | Node selector of the pods. |
| gateway.podAnnotations | object | `{}` | Annotations of the pods. |
| gateway.podLabels | object | `{}` | Labels of the pods. |
| gateway.podSecurityContext | object | `{}` | Security context of the pods. |
| gateway.replicaCount | int | `1` | Number of replicas. |
| gateway.resources | object | `{}` | Resources of the gateway container. |
| gateway.securityContext | object | `{}` | Security context of the gateway container. |
| gateway.service.port | int | `80` | Port of the Service. |
| gateway.service.type | string | `"ClusterIP"` | Type of the Service. |
| gateway.serviceAccount.annotations | object | `{}` | Annotations of the ServiceAccount. |
| gateway.serviceAccount.automount | bool | `true` | Mount the ServiceAccount's API credentials. |
| gateway.serviceAccount.create | bool | `true` | Create a ServiceAccount. |
| gateway.serviceAccount.name | string | `""` | Name of the ServiceAccount. Empty is the full name when create is true, and the namespace's default otherwise. |
| gateway.tolerations | list | `[]` | Tolerations of the pods. |
| gateway.volumeMounts | list | `[]` | Further volume mounts of the gateway container. |
| gateway.volumes | list | `[]` | Further volumes of the pods. |
| imagePullSecrets | list | `[]` | Secrets to pull the gateway and internal database images with. See https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/ |
| nameOverride | string | `""` | Overrides the chart name. |
| oidc.adminGroups | list | `[]` | Set adminGroups and the directory owns the administrator role: it is read on every sign-in, and the panel, the CLI and the API stop assigning roles. Leave it empty to make administrators with `keera user role`. |
| oidc.clientId | string | `""` | Client ID. |
| oidc.clientSecret | string | `""` | Client secret. Required unless existingSecret is set. |
| oidc.defaultRole | string | `""` | Role of a person matching no group: operator, admin or member. Empty is member. |
| oidc.domains | list | `[]` | Email domains a provider may sign people in with, ["*"] for any. Required with several providers, so one directory cannot vouch for another's addresses. |
| oidc.enabled | bool | `false` | Turn on single sign-on. |
| oidc.existingSecret | string | `""` | Use an existing Secret for the client secret instead. |
| oidc.existingSecretKey | string | `"clientSecret"` | Key in the existing Secret holding the client secret. |
| oidc.groupsClaim | string | `""` | Claim holding the groups. Empty is "groups". |
| oidc.issuer | string | `""` | Issuer URL, such as https://login.microsoftonline.com/<tenant>/v2.0. |
| oidc.label | string | `""` | What the sign-in button says. Empty capitalises the name. |
| oidc.name | string | `"sso"` | Name of the single provider. It is chosen once, see `providers` below. |
| oidc.operatorGroups | list | `[]` | Groups whose members are operators. |
| oidc.providers | list | `[]` | Several directories: a sign-in button per entry, each with a client of its own. Setting this ignores the single-directory fields above; everything from `adminGroups` down is copied to every entry, and an entry may override it. Each entry needs `domains` with several providers. A name is chosen once. It goes in the sign-in URL and in every identity that provider writes, so changing one orphans everybody who signed in through it. |
| oidc.scopes | list | `[]` | Further scopes to request. |
| oidc.signup | bool | `false` | Lets someone whose sign-in matches no organisation create one. |
| operators | list | `[]` | Emails that are operators. The operator role is never assignable through the panel, the CLI or the API, so this and oidc.operatorGroups are the only two things that grant it. |
| passkeys | bool | `false` | Lets administrators create accounts that sign in with a passkey, with or without OIDC. Requires publicUrl with its scheme, which has to be https (or http on localhost) and not an IP address, or the install fails. A passkey belongs to that host name, so changing it later breaks every passkey. See https://github.com/bespinian/keera-gateway/blob/main/docs/sso.md#passkeys. |
| publicUrl | string | `""` | The address a browser reaches the gateway on, without a path, such as https://keera.example.ch. Single sign-on returns to its /control/auth/callback, which every provider's client registration has to list, so it is required when oidc.enabled is true. Passkeys and payments need it too. |
| upstreamPrivate | string | `""` | Host names inside the network that organisations may reach, such as keera-engine, or "none" or "all". Empty is all. Required with oidc.signup, by default a stranger's organisation reaches the whole private network. |
