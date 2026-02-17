// ExternalSecret resource builder — wraps helpers/externalsecret.libsonnet with labsonnet naming.

local externalSecretHelper = import 'helpers/externalsecret.libsonnet';

{
  new(name, namespace, suffix, storeName, storeKind='ClusterSecretStore', remoteKey=null)::
    local secretName = name + '-' + suffix;
    local key = if remoteKey != null then remoteKey else name;

    externalSecretHelper.new(secretName,
                             namespace,
                             storeName,
                             storeKind,
                             dataFrom=[{ extract: { key: key } }]),
}
