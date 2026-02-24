// ExternalSecret resource builder — wraps helpers/externalsecret.libsonnet.

local externalSecretHelper = import 'helpers/externalsecret.libsonnet';

{
  new(name, namespace, storeName, storeKind='ClusterSecretStore', remoteKey=null)::
    local key = if remoteKey != null then remoteKey else name;

    externalSecretHelper.new(name,
                             namespace,
                             storeName,
                             storeKind,
                             dataFrom=[{ extract: { key: key } }]),
}
