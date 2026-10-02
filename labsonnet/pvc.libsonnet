// PVC resource builder — wraps helpers/pvc.libsonnet with labsonnet naming conventions.

local helpers = import 'helpers/pvc.libsonnet';

{
  volumeName(serviceName, mountPath, pvConfig)::
    if std.objectHas(pvConfig, 'name') then pvConfig.name
    else '%s-%s' % [serviceName, std.strReplace(std.lstripChars(mountPath, '/'), '/', '-')],

  new(name, namespace, config, labels)::
    helpers.new(
      name,
      namespace,
      config.size,
      accessModes=if std.objectHas(config, 'accessModes') then config.accessModes else ['ReadWriteOnce'],
      storageClassName=if std.objectHas(config, 'storageClassName') then config.storageClassName else null,
      labels=labels,
    ),
}
