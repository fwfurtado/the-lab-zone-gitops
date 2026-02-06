# democratic-csi

CSI driver for TrueNAS/FreeNAS (NFS). Provisioning uses a driver config that includes the TrueNAS API key; that config is synced from 1Password via External Secrets.

## 1Password setup

1. Create an item in your 1Password vault (e.g. **"TrueNAS Democratic CSI"**).
2. In the **Notes** field (or a custom field), put the **full driver config** as YAML. The ExternalSecret expects the ref `TrueNAS Democratic CSI/notes`; if you use another item name or field, edit `templates/truenas-driver-config-external-secret.yaml` and set `remoteRef.key` to `"Your Item Name/field"`.

Example YAML for the 1Password notes (replace host, shareHost and apiKey with your values):

```yaml
driver: freenas-api-nfs
httpConnection:
  protocol: https
  host: YOUR_TRUENAS_IP
  port: 443
  allowInsecure: true
  apiKey: YOUR_TRUENAS_API_KEY
zfs:
  datasetParentName: main/k8s/platform/volumes
  detachedSnapshotsDatasetParentName: main/k8s/platform/snapshots
  datasetProperties:
    org.freenas:description: "{{ parameters.[csi.storage.k8s.io/pvc/namespace] }}/{{ parameters.[csi.storage.k8s.io/pvc/name] }}"
nfs:
  shareHost: YOUR_TRUENAS_IP
  shareAlldirs: false
  shareAllowedHosts: []
  shareAllowedNetworks:
    - 192.168.0.0/16
  shareMaprootUser: root
  shareMaprootGroup: root
```

3. After the first sync, the Secret `truenas-driver-config` will exist in the `democratic-csi` namespace with key `driver-config-file.yaml`, and the chart will use it via `driver.existingConfigSecret`.

## Addresses

If you get timeouts, check that `host` and `shareHost` in the 1Password config are correct and reachable from the cluster (same IP you use for the TrueNAS UI, or the hostname if DNS resolves).
