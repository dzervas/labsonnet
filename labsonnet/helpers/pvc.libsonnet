// Standalone PersistentVolumeClaim resource builder.

local d = import 'github.com/jsonnet-libs/docsonnet/doc-util/main.libsonnet';

local k = import 'k.libsonnet';
local pvcK = k.core.v1.persistentVolumeClaim;

{
  '#':: d.pkg(
    name='pvc',
    url='https://github.com/dzervas/labsonnet',
    filename=std.thisFile,
    version='main',
    help='Create PersistentVolumeClaim resources.',
  ) + d.package.withInstallTemplate('jb install github.com/dzervas/labsonnet/labsonnet@main')
    + d.package.withUsageTemplate("local pvc = import 'labsonnet/helpers/pvc.libsonnet'"),

  '#new':: d.fn(|||
    Create a PersistentVolumeClaim. The storage class is omitted when null, so Kubernetes may use its default class. A named class must have a provisioner in the cluster.

    Example:

    ```jsonnet
    local p = import 'labsonnet/helpers/pvc.libsonnet';
    {
      pvc: p.new('media', 'apps', '20Gi', storageClassName='fast',
        labels={ app: 'media' }),
    }
    ```
  |||, [
    d.arg('name', d.T.string),
    d.arg('namespace', d.T.string),
    d.arg('size', d.T.string),
    d.arg('accessModes', d.T.array, ['ReadWriteOnce']),
    d.argument.fromSchema('storageClassName', { type: ['string', 'null'], default: null }),
    d.arg('labels', d.T.object, {}),
  ]),

  new(name, namespace, size, accessModes=['ReadWriteOnce'], storageClassName=null, labels={})::
    pvcK.new(name)
    + pvcK.metadata.withNamespace(namespace)
    + pvcK.spec.withAccessModes(accessModes)
    + pvcK.spec.resources.withRequests({ storage: size })
    + (if std.length(labels) > 0 then pvcK.metadata.withLabels(labels) else {})
    + (if storageClassName != null then pvcK.spec.withStorageClassName(storageClassName) else {}),
}
