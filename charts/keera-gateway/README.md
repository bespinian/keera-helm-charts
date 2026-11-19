# Keera Gateway Helm Chart

keera-gateway Helm chart for Kubernetes

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
     --version 0.1.0 \
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

With `database.type: internal` (the default), the chart deploys a single PostgreSQL instance as a StatefulSet next to the gateway and wires up `KEERA_DATABASE_URL` automatically. Data is stored on a PersistentVolumeClaim, see `database.internal.persistence`.

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
| credentials.existingSecret.name | string | `""` |  |
| credentials.existingSecret.operatorSecretKey | string | `"KEERA_OPERATOR_KEY"` |  |
| credentials.existingSecret.secretSecretKey | string | `"KEERA_SECRET_KEY"` |  |
| credentials.operatorKey | string | `""` |  |
| credentials.secretKey | string | `""` |  |
| database.internal.affinity | object | `{}` |  |
| database.internal.database | string | `"keera"` |  |
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
| fullnameOverride | string | `""` |  |
| gateway.affinity | object | `{}` |  |
| gateway.autoscaling.enabled | bool | `false` |  |
| gateway.autoscaling.maxReplicas | int | `100` |  |
| gateway.autoscaling.minReplicas | int | `1` |  |
| gateway.autoscaling.targetCPUUtilizationPercentage | int | `80` |  |
| gateway.httpRoute.annotations | object | `{}` |  |
| gateway.httpRoute.enabled | bool | `false` |  |
| gateway.httpRoute.hostnames | list | `[]` |  |
| gateway.httpRoute.labels | object | `{}` |  |
| gateway.httpRoute.parentRefs | list | `[]` |  |
| gateway.httpRoute.rules[0].matches[0].path.type | string | `"PathPrefix"` |  |
| gateway.httpRoute.rules[0].matches[0].path.value | string | `"/"` |  |
| gateway.image.pullPolicy | string | `"IfNotPresent"` |  |
| gateway.image.repository | string | `"ghcr.io/bespinian/keera-gateway"` |  |
| gateway.image.tag | string | `""` |  |
| gateway.ingress.annotations | object | `{}` |  |
| gateway.ingress.enabled | bool | `false` |  |
| gateway.ingress.extraHosts | list | `[]` |  |
| gateway.ingress.extraTls | list | `[]` |  |
| gateway.ingress.hostname | string | `""` |  |
| gateway.ingress.ingressClassName | string | `""` |  |
| gateway.ingress.labels | object | `{}` |  |
| gateway.ingress.path | string | `"/"` |  |
| gateway.ingress.pathType | string | `"Prefix"` |  |
| gateway.ingress.tls | bool | `false` |  |
| gateway.nodeSelector | object | `{}` |  |
| gateway.podAnnotations | object | `{}` |  |
| gateway.podLabels | object | `{}` |  |
| gateway.podSecurityContext | object | `{}` |  |
| gateway.replicaCount | int | `1` |  |
| gateway.resources | object | `{}` |  |
| gateway.securityContext | object | `{}` |  |
| gateway.service.port | int | `80` |  |
| gateway.service.type | string | `"ClusterIP"` |  |
| gateway.serviceAccount.annotations | object | `{}` |  |
| gateway.serviceAccount.automount | bool | `true` |  |
| gateway.serviceAccount.create | bool | `true` |  |
| gateway.serviceAccount.name | string | `""` |  |
| gateway.tolerations | list | `[]` |  |
| gateway.volumeMounts | list | `[]` |  |
| gateway.volumes | list | `[]` |  |
| imagePullSecrets | list | `[]` |  |
| nameOverride | string | `""` |  |
| oidc.adminGroups | list | `[]` |  |
| oidc.clientId | string | `""` |  |
| oidc.clientSecret | string | `""` |  |
| oidc.defaultRole | string | `""` |  |
| oidc.domains | list | `[]` |  |
| oidc.enabled | bool | `false` |  |
| oidc.existingSecret | string | `""` |  |
| oidc.existingSecretKey | string | `"clientSecret"` |  |
| oidc.groupsClaim | string | `""` |  |
| oidc.issuer | string | `""` |  |
| oidc.label | string | `""` |  |
| oidc.name | string | `"sso"` |  |
| oidc.operatorGroups | list | `[]` |  |
| oidc.providers | list | `[]` |  |
| oidc.scopes | list | `[]` |  |
| oidc.signup | bool | `false` |  |
| operators | list | `[]` |  |
| passkeys | bool | `false` | Lets administrators create accounts that sign in with a passkey, with or without OIDC. Requires publicUrl with its scheme, which has to be https (or http on localhost) and not an IP address, or the install fails. A passkey belongs to that host name, so changing it later breaks every passkey. See https://github.com/bespinian/keera-gateway/blob/main/docs/sso.md#passkeys. |
| publicUrl | string | `""` |  |
| upstreamPrivate | string | `""` |  |
