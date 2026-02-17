// Standalone PersistentVolumeClaim resource builder.

local k = import 'k.libsonnet';
local pvcK = k.core.v1.persistentVolumeClaim;

{
  new(name, namespace, size, accessModes=['ReadWriteOnce'], storageClassName=null, labels={})::
    pvcK.new(name)
    + pvcK.metadata.withNamespace(namespace)
    + pvcK.spec.withAccessModes(accessModes)
    + pvcK.spec.resources.withRequests({ storage: size })
    + (if std.length(labels) > 0 then pvcK.metadata.withLabels(labels) else {})
    + (if storageClassName != null then pvcK.spec.withStorageClassName(storageClassName) else {}),
}
