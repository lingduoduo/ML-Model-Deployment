{{/*
Expand the name of the chart.
*/}}
{{- define "model-deployment.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "model-deployment.fullname" -}}
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
{{- define "model-deployment.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "model-deployment.labels" -}}
helm.sh/chart: {{ include "model-deployment.chart" . }}
{{ include "model-deployment.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "model-deployment.selectorLabels" -}}
app.kubernetes.io/name: {{ include "model-deployment.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "model-deployment.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "model-deployment.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Validate selectable values. Fails rendering with a clear message on bad input.
Extended by later tasks (rolloutStrategy, catalog/environment, modelGate.mode).
*/}}
{{- define "model-deployment.validate" -}}
{{- $allowedPatterns := list "deploy-code" "deploy-models" -}}
{{- if not (has .Values.deploymentPattern $allowedPatterns) -}}
{{- fail (printf "deploymentPattern must be one of [%s], got %q" (join ", " $allowedPatterns) (toString .Values.deploymentPattern)) -}}
{{- end -}}
{{- if and .Values.modelStore.catalog .Values.environment -}}
{{- $catMap := dict "dev" "dev" "staging" "staging" "production" "prod" -}}
{{- $expected := index $catMap .Values.environment -}}
{{- if and $expected (ne .Values.modelStore.catalog $expected) -}}
{{- fail (printf "modelStore.catalog %q does not match environment %q (expected %q)" .Values.modelStore.catalog .Values.environment $expected) -}}
{{- end -}}
{{- end -}}
{{- end -}}
