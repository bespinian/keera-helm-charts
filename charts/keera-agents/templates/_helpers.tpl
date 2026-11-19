{{/*
Expand the name of the chart.
*/}}
{{- define "keera-agents.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "keera-agents.fullname" -}}
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
{{- define "keera-agents.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "keera-agents.labels" -}}
helm.sh/chart: {{ include "keera-agents.chart" . }}
{{ include "keera-agents.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "keera-agents.selectorLabels" -}}
app.kubernetes.io/name: {{ include "keera-agents.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "keera-agents.serviceAccountName" -}}
{{- if .Values.controlPlane.serviceAccount.create }}
{{- default (include "keera-agents.fullname" .) .Values.controlPlane.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.controlPlane.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Name of the Secret holding the credentials
*/}}
{{- define "keera-agents.credentials.secretName" -}}
{{- default (include "keera-agents.fullname" .) .Values.credentials.existingSecret.name }}
{{- end }}

{{/*
Namespace agents and workspaces run in
*/}}
{{- define "keera-agents.agents.namespace" -}}
{{- default (printf "%s-agents" .Release.Namespace) .Values.agents.namespace.name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
keera-agents as agents reach it: the in-cluster Service
*/}}
{{- define "keera-agents.runtimeUrl" -}}
{{- $port := int .Values.controlPlane.service.port }}
{{- printf "http://%s.%s.svc%s" (include "keera-agents.fullname" .) .Release.Namespace (ternary "" (printf ":%d" $port) (eq $port 80)) }}
{{- end }}

{{/*
Name of the internal database resources
*/}}
{{- define "keera-agents.database.fullname" -}}
{{- printf "%s-database" (include "keera-agents.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Internal database labels
*/}}
{{- define "keera-agents.database.labels" -}}
helm.sh/chart: {{ include "keera-agents.chart" . }}
{{ include "keera-agents.database.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Internal database selector labels
Distinct from the keera-agents selector labels so its Service does not select database pods
*/}}
{{- define "keera-agents.database.selectorLabels" -}}
app.kubernetes.io/name: {{ include "keera-agents.name" . }}-database
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: database
{{- end }}

{{/*
Name of the Secret holding the internal database password
*/}}
{{- define "keera-agents.database.passwordSecretName" -}}
{{- default (include "keera-agents.database.fullname" .) .Values.database.internal.existingSecret }}
{{- end }}

{{/*
Key in the Secret holding the internal database password
*/}}
{{- define "keera-agents.database.passwordSecretKey" -}}
{{- if .Values.database.internal.existingSecret }}
{{- .Values.database.internal.existingSecretPasswordKey }}
{{- else -}}
password
{{- end }}
{{- end }}

{{/*
Internal database connection URL
The password is not part of the URL, keera-agents reads it from PGPASSWORD
*/}}
{{- define "keera-agents.database.url" -}}
{{- $internal := .Values.database.internal }}
{{- printf "postgres://%s@%s:5432/%s?sslmode=disable" ($internal.username | urlquery) (include "keera-agents.database.fullname" .) $internal.database }}
{{- end }}

{{/*
Fails on an unknown database type
*/}}
{{- define "keera-agents.database.validate" -}}
{{- if not (has .Values.database.type (list "internal" "external")) }}
{{- fail (printf "database.type must be internal or external, not %q" .Values.database.type) }}
{{- end }}
{{- end }}

{{/*
Fails on a missing or malformed setting, keera-agents refuses to start with one
*/}}
{{- define "keera-agents.validate" -}}
{{- include "keera-agents.database.validate" . }}
{{- if not .Values.gateway.url }}
{{- fail "gateway.url is required, Keera Gateway as a browser reaches it" }}
{{- end }}
{{- if eq (include "keera-agents.agents.namespace" .) .Release.Namespace }}
{{- fail "agents.namespace.name must differ from the release namespace, whoever reads pods there reads agents' runtime tokens" }}
{{- end }}
{{- with .Values.agents.minIsolation }}
{{- if not (has . (list "standard" "isolated" "vm")) }}
{{- fail (printf "agents.minIsolation must be standard, isolated or vm, not %q" .) }}
{{- end }}
{{- end }}
{{- with .Values.credentials }}
{{- if not .existingSecret.name }}
{{- if lt (len .serviceKey) 32 }}
{{- fail "credentials.serviceKey must be at least 32 characters, or set credentials.existingSecret.name" }}
{{- end }}
{{- if lt (len .secretKey) 16 }}
{{- fail "credentials.secretKey must be at least 16 characters, or set credentials.existingSecret.name" }}
{{- end }}
{{- if and .metricsToken (lt (len .metricsToken) 16) }}
{{- fail "credentials.metricsToken must be at least 16 characters" }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
