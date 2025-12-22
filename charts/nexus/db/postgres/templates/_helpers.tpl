{{/*
Return upload command based on provider
*/}}
{{- define "backup.uploadCommand" -}}
{{- if eq .Values.objectStorage.provider "aws" }}
aws s3 cp ${BACKUP_FILE}.gz s3://{{ .Values.objectStorage.bucket }}/{{ .Values.objectStorage.prefix }}/
{{- else if eq .Values.objectStorage.provider "gcp" }}
gsutil cp ${BACKUP_FILE}.gz gs://{{ .Values.objectStorage.bucket }}/{{ .Values.objectStorage.prefix }}/
{{- else if eq .Values.objectStorage.provider "azure" }}
az storage blob upload \
  --container-name {{ .Values.objectStorage.bucket }} \
  --file ${BACKUP_FILE}.gz \
  --name {{ .Values.objectStorage.prefix }}/$(basename ${BACKUP_FILE}.gz)
{{- end }}
{{- end }}
