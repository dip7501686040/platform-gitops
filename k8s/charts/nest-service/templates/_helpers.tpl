{{- define "nest-service.labels" -}}
app.kubernetes.io/name: {{ .Release.Name }}
app.kubernetes.io/part-of: ai-notification-system
{{- end -}}
