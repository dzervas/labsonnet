// PVC resource builder — wraps helpers/pvc.libsonnet with labsonnet naming conventions.

local helpers = import 'helpers/pvc.libsonnet';

{
  volumeName(serviceName, mountPath, pvConfig)::
    if std.objectHas(pvConfig, 'name') then pvConfig.name
    else '%s-%s' % [serviceName, std.strReplace(std.lstripChars(mountPath, '/'), '/', '-')],

  new(name, namespace, mountPath, pvcConfig, labels)::
    local pvcName = $.volumeName(name, mountPath, pvcConfig);

    helpers.new(
      pvcName,
      namespace,
      pvcConfig.size,
      accessModes=if std.objectHas(pvcConfig, 'accessModes') then pvcConfig.accessModes else ['ReadWriteOnce'],
      storageClassName=if std.objectHas(pvcConfig, 'storageClassName') then pvcConfig.storageClassName else null,
      labels=labels,
    ),

  build(name, namespace, pvs, labels)::
    std.filterMap(
      function(mountPath) !(std.objectHas(pvs[mountPath], 'emptyDir') && pvs[mountPath].emptyDir),
      function(mountPath) $.new(name, namespace, mountPath, pvs[mountPath], labels),
      std.objectFields(pvs)
    ),
}
