# LGTM (meta-monitoring)

Stack LGTM via chart [grafana/meta-monitoring](https://github.com/grafana/meta-monitoring-chart).  
Storage: StorageClass `truenas-nfs` (democratic-csi) — configurada em `values.yaml` para MinIO e subcharts.

## Se o pod do MinIO (ou outros) ficar em FailedScheduling por "unbound PersistentVolumeClaims"

PVCs criados **antes** de existir `storageClassName: truenas-nfs` nos values ficam Pending e não podem ser alterados (spec é imutável). É preciso apagá-los e deixar o chart recriar com os values atuais.

**Passos (no cluster):**

```bash
# 1. Listar PVCs no namespace do LGTM
kubectl get pvc -n monitoring

# 2. Escalar o Deployment do MinIO para 0 (para poder apagar o PVC)
kubectl scale deployment -n monitoring lgtm-minio --replicas=0

# 3. Apagar o PVC em Pending (nome: lgtm-minio)
kubectl delete pvc -n monitoring lgtm-minio

# 4. Dar sync no app platforms-lgtm no Argo CD (ou aguardar o sync automático).
#    O chart recriará o PVC com storageClassName: truenas-nfs e o Deployment voltará a subir.
```

**Nota:** Apagar o PVC apaga os dados desse volume. Para instalação nova ou sem dados importantes, isso é aceitável.

## Se Mimir/Loki/Tempo reportam "The specified bucket does not exist"

O MinIO principal (`lgtm-minio`) precisa ter os buckets criados (loki-chunks, loki-ruler, tempo, mimir-ruler, mimir-tsdb). Eles estão em `values.yaml`; o chart cria os buckets na subida do MinIO. Se os componentes subiram antes dos buckets existirem, reinicie o MinIO para rodar a criação de buckets de novo:

```bash
kubectl rollout restart deployment -n monitoring lgtm-minio
```

Aguarde o pod ficar Ready e os outros pods (Mimir, Loki, Tempo) devem conseguir conectar ao object storage.

**Se os buckets ainda não existirem**, crie-os à mão dentro do pod do MinIO (a imagem já traz o cliente `mc`):

```bash
# Entrar no pod do MinIO e criar os buckets (credenciais vêm do secret "minio")
kubectl exec -it deployment/lgtm-minio -n monitoring -- bash -c '
  mc alias set myminio http://localhost:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"
  for b in loki-chunks loki-ruler tempo mimir-ruler mimir-tsdb; do mc mb myminio/$b --ignore-existing 2>/dev/null || true; done
'
```

Depois disso, os pods do Mimir (e dos outros) devem conseguir conectar ao object storage.
