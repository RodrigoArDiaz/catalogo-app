{{/*
Namespace de la release (helm install -n catalogo-app).
*/}}
{{- define "catalogo-app.namespace" -}}
{{- .Release.Namespace -}}
{{- end -}}