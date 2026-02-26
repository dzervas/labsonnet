// Standalone ExternalSecret resource builder.

local externalSecrets = import 'external-secrets.libsonnet';
local externalSecret = externalSecrets.nogroup.v1.externalSecret;

{
  new(name, namespace, storeName, storeKind='ClusterSecretStore', dataFrom=[], data=[], refreshInterval=null)::
    externalSecret.new(name)
    + externalSecret.metadata.withNamespace(namespace)
    + externalSecret.spec.secretStoreRef.withKind(storeKind)
    + externalSecret.spec.secretStoreRef.withName(storeName)
    + (if std.length(dataFrom) > 0 then externalSecret.spec.withDataFrom(dataFrom) else {})
    + (if std.length(data) > 0 then externalSecret.spec.withData(data) else {})
    + (if refreshInterval != null then externalSecret.spec.withRefreshInterval(refreshInterval) else {}),
}
