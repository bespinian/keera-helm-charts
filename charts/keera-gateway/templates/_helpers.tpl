{{/*
Expand the name of the chart.
*/}}
{{- define "keera-gateway.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "keera-gateway.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "keera-gateway.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "keera-gateway.labels" -}}
helm.sh/chart: {{ include "keera-gateway.chart" . }}
{{ include "keera-gateway.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "keera-gateway.selectorLabels" -}}
app.kubernetes.io/name: {{ include "keera-gateway.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "keera-gateway.serviceAccountName" -}}
{{- if .Values.gateway.serviceAccount.create }}
{{- default (include "keera-gateway.fullname" .) .Values.gateway.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.gateway.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Name of the Secret holding the credentials
*/}}
{{- define "keera-gateway.credentials.secretName" -}}
{{- default (include "keera-gateway.fullname" .) .Values.credentials.existingSecret.name }}
{{- end }}

{{/*
Name of the internal database resources
*/}}
{{- define "keera-gateway.database.fullname" -}}
{{- printf "%s-database" (include "keera-gateway.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Internal database labels
*/}}
{{- define "keera-gateway.database.labels" -}}
helm.sh/chart: {{ include "keera-gateway.chart" . }}
{{ include "keera-gateway.database.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Internal database selector labels
Distinct from the gateway selector labels so the gateway Service does not select database pods
*/}}
{{- define "keera-gateway.database.selectorLabels" -}}
app.kubernetes.io/name: {{ include "keera-gateway.name" . }}-database
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: database
{{- end }}

{{/*
Name of the Secret holding the internal database password
*/}}
{{- define "keera-gateway.database.passwordSecretName" -}}
{{- default (include "keera-gateway.database.fullname" .) .Values.database.internal.existingSecret }}
{{- end }}

{{/*
Key in the Secret holding the internal database password
*/}}
{{- define "keera-gateway.database.passwordSecretKey" -}}
{{- if .Values.database.internal.existingSecret }}
{{- .Values.database.internal.existingSecretPasswordKey }}
{{- else -}}
password
{{- end }}
{{- end }}

{{/*
Escapes a URL user or path segment. urlquery escapes for a query string, where a space becomes "+"
*/}}
{{- define "keera-gateway.database.urlEscape" -}}
{{- urlquery . | replace "+" "%20" }}
{{- end }}

{{/*
Internal database connection URL
The password is not part of the URL, the gateway reads it from PGPASSWORD
*/}}
{{- define "keera-gateway.database.url" -}}
{{- $internal := .Values.database.internal }}
{{- printf "postgres://%s@%s:5432/%s?sslmode=disable" (include "keera-gateway.database.urlEscape" $internal.username) (include "keera-gateway.database.fullname" .) (include "keera-gateway.database.urlEscape" $internal.database) }}
{{- end }}

{{/*
Name of the Secret holding the OIDC client secrets the chart owns
*/}}
{{- define "keera-gateway.oidc.secretName" -}}
{{- printf "%s-oidc" (include "keera-gateway.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Environment variable segment of an OIDC provider name
*/}}
{{- define "keera-gateway.oidc.segment" -}}
{{- upper (replace "-" "_" .) }}
{{- end }}

{{/*
The OIDC providers, the single-directory fields becoming one provider named oidc.name
Groups, claim, role, scopes, domains and signup are shared by all providers, a
provider may override them with its own, even with an empty value. The gateway shares nothing between
providers, so each gets its own copy.
Returns YAML: providers: [...]
*/}}
{{- define "keera-gateway.oidc.providers" -}}
{{- $oidc := .Values.oidc }}
{{- $shared := pick $oidc "adminGroups" "operatorGroups" "groupsClaim" "defaultRole" "scopes" "domains" "signup" }}
{{- $providers := list }}
{{- if $oidc.providers }}
{{- range $p := $oidc.providers }}
{{- $provider := deepCopy $p }}
{{- range $k, $v := $shared }}
{{- if not (hasKey $provider $k) }}
{{- $_ := set $provider $k $v }}
{{- end }}
{{- end }}
{{- $providers = append $providers $provider }}
{{- end }}
{{- else }}
{{- $p := pick $oidc "name" "label" "issuer" "clientId" "clientSecret" "existingSecret" "existingSecretKey" }}
{{- $providers = append $providers (merge $p $shared) }}
{{- end }}
{{- toYaml (dict "providers" $providers) }}
{{- end }}

{{/*
Fails on a partial OIDC configuration, the gateway refuses to start with one
*/}}
{{- define "keera-gateway.oidc.validate" -}}
{{- if .Values.oidc.enabled }}
{{- if not .Values.publicUrl }}
{{- fail "publicUrl is required when oidc.enabled is true" }}
{{- end }}
{{- $providers := (include "keera-gateway.oidc.providers" . | fromYaml).providers }}
{{- range $p := $providers }}
{{- if not (regexMatch "^[a-z0-9][a-z0-9-]*$" (default "" $p.name)) }}
{{- fail (printf "oidc provider name %q must be lower-case letters, digits and hyphens" (default "" $p.name)) }}
{{- end }}
{{- range $k := list "issuer" "clientId" }}
{{- if not (get $p $k) }}
{{- fail (printf "oidc provider %s: %s is required" $p.name $k) }}
{{- end }}
{{- end }}
{{- if and (not $p.clientSecret) (not $p.existingSecret) }}
{{- fail (printf "oidc provider %s: clientSecret or existingSecret is required" $p.name) }}
{{- end }}
{{- if and (gt (len $providers) 1) (not $p.domains) }}
{{- fail (printf "oidc provider %s: domains is required with several providers, [\"*\"] for any" $p.name) }}
{{- end }}
{{- end }}
{{- $signUp := list }}
{{- $adminGroups := list }}
{{- range $p := $providers }}
{{- if $p.signup }}{{ $signUp = append $signUp $p.name }}{{ end }}
{{- if $p.adminGroups }}{{ $adminGroups = append $adminGroups $p.name }}{{ end }}
{{- end }}
{{- if and $signUp $adminGroups }}
{{- fail (printf "oidc: signup (%s) and adminGroups (%s) cannot both be set, whoever creates an organisation would lose the administrator role at their next sign-in" (join "," $signUp) (join "," $adminGroups)) }}
{{- end }}
{{- if and $signUp (not .Values.upstreamPrivate) }}
{{- fail "upstreamPrivate is required with oidc.signup, such as keera-engine, or none or all" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
OIDC environment variables of the gateway container
*/}}
{{- define "keera-gateway.oidc.env" -}}
{{- if .Values.oidc.enabled }}
{{- $secretName := include "keera-gateway.oidc.secretName" . }}
{{- $providers := (include "keera-gateway.oidc.providers" . | fromYaml).providers }}
{{- $names := list }}
{{- range $p := $providers }}{{ $names = append $names $p.name }}{{ end }}
- name: KEERA_OIDC_PROVIDERS
  value: {{ join "," $names | quote }}
{{- range $p := $providers }}
{{- $seg := include "keera-gateway.oidc.segment" $p.name }}
- name: KEERA_OIDC_{{ $seg }}_ISSUER
  value: {{ $p.issuer | quote }}
- name: KEERA_OIDC_{{ $seg }}_CLIENT_ID
  value: {{ $p.clientId | quote }}
- name: KEERA_OIDC_{{ $seg }}_CLIENT_SECRET
  valueFrom:
    secretKeyRef:
      {{- if $p.existingSecret }}
      name: {{ $p.existingSecret }}
      key: {{ default "clientSecret" $p.existingSecretKey }}
      {{- else }}
      name: {{ $secretName }}
      key: KEERA_OIDC_{{ $seg }}_CLIENT_SECRET
      {{- end }}
{{- with $p.label }}
- name: KEERA_OIDC_{{ $seg }}_LABEL
  value: {{ . | quote }}
{{- end }}
{{- with $p.adminGroups }}
- name: KEERA_OIDC_{{ $seg }}_ADMIN_GROUPS
  value: {{ join "," . | quote }}
{{- end }}
{{- with $p.operatorGroups }}
- name: KEERA_OIDC_{{ $seg }}_OPERATOR_GROUPS
  value: {{ join "," . | quote }}
{{- end }}
{{- with $p.groupsClaim }}
- name: KEERA_OIDC_{{ $seg }}_GROUPS_CLAIM
  value: {{ . | quote }}
{{- end }}
{{- with $p.defaultRole }}
- name: KEERA_OIDC_{{ $seg }}_DEFAULT_ROLE
  value: {{ . | quote }}
{{- end }}
{{- with $p.scopes }}
- name: KEERA_OIDC_{{ $seg }}_SCOPES
  value: {{ join "," . | quote }}
{{- end }}
{{- with $p.domains }}
- name: KEERA_OIDC_{{ $seg }}_DOMAINS
  value: {{ join "," . | quote }}
{{- end }}
{{- if $p.signup }}
- name: KEERA_OIDC_{{ $seg }}_SIGNUP
  value: "true"
{{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Fails on a publicUrl that passkeys cannot use, the gateway refuses to start
with one. Browsers allow WebAuthn only in a secure context, and never on an IP
address.
*/}}
{{- define "keera-gateway.passkeys.validate" -}}
{{- if .Values.passkeys }}
{{- $url := urlParse (default "" .Values.publicUrl) }}
{{- if not $url.host }}
{{- fail (printf "passkeys needs publicUrl with a scheme and host, such as https://keera.example.ch, not %q" (default "" .Values.publicUrl)) }}
{{- end }}
{{- $host := $url.hostname }}
{{- if not (or (eq $url.scheme "https") (and (eq $url.scheme "http") (or (eq $host "localhost") (hasSuffix ".localhost" $host)))) }}
{{- fail (printf "passkeys needs publicUrl to be https, or http on localhost; %s is neither" .Values.publicUrl) }}
{{- end }}
{{- if or (contains ":" $host) (regexMatch "^[0-9.]+$" $host) }}
{{- fail (printf "passkeys needs a host name in publicUrl, not an address; browsers refuse %s" $host) }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Fails on a missing or malformed setting, the gateway refuses to start with one
*/}}
{{- define "keera-gateway.validate" -}}
{{- include "keera-gateway.oidc.validate" . }}
{{- include "keera-gateway.passkeys.validate" . }}
{{- end }}
