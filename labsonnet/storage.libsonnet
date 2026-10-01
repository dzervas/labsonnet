// Resolve final storage declarations and mount references.
local k = import 'k.libsonnet';
local pvc = import 'pvc.libsonnet';
local volume = k.core.v1.volume;
local volumeMount = k.core.v1.volumeMount;

local validVolumeName(name) =
  std.isString(name) && std.length(name) > 0 && std.length(name) <= 63
  && std.all([std.member(std.stringChars('abcdefghijklmnopqrstuvwxyz0123456789-'), c) for c in std.stringChars(name)])
  && name[0] != '-' && name[std.length(name) - 1] != '-';

local dedupDefinitions(entries) = std.foldl(
  function(acc, entry)
    local previous = std.filter(function(e) e.name == entry.name, acc);
    assert std.length(previous) == 0 || previous[0] == entry :
      "labsonnet: conflicting definitions for volume '%s'" % entry.name;
    if std.length(previous) == 0 then acc + [entry] else acc,
  entries,
  []
);

{
  resolve(cfg)::
    assert std.all([validVolumeName(c.name) && std.isObject(c.config)
                   && std.objectHas(c.config, 'size')
                   && std.all([std.member(['size', 'accessModes', 'storageClassName'], f) for f in std.objectFields(c.config)])
                   for c in cfg.claimTemplates]) :
      'labsonnet: claim templates require a valid volume name and config with size, optional accessModes and storageClassName';
    assert std.length(cfg.claimTemplates) == 0 || cfg.type == 'StatefulSet' :
      'labsonnet: managed claim templates require StatefulSet type';
    assert std.all([std.isObject(v) && std.objectHas(v, 'name') && validVolumeName(v.name)
                   && (!std.objectHas(v, 'persistentVolumeClaim')
                       || (std.isString(v.persistentVolumeClaim.claimName) && std.length(v.persistentVolumeClaim.claimName) > 0))
                   for v in cfg.volumes]) :
      'labsonnet: volumes require a valid name; existing PVC references require a non-empty claimName';

    // Maps retain final values; the call journal preserves duplicate paths that
    // composition would otherwise overwrite. Check final maps for direct overrides too.
    local actualPaths = std.objectFields(cfg.secrets)
                      + std.objectFields(cfg.configMapMounts) + std.objectFields(cfg.externalSecretMounts)
                      + std.objectFields(cfg.volumeMounts);
    local duplicatePaths = [
      path for path in std.set(cfg.mountPaths + actualPaths)
      if std.length(std.filter(function(p) p == path, cfg.mountPaths)) > 1
         || std.length(std.filter(function(p) p == path, actualPaths)) > 1
    ];
    assert std.length(duplicatePaths) == 0 :
      'labsonnet: duplicate volume mount paths: %s' % std.join(', ', duplicatePaths);

    local definitions = dedupDefinitions(
      [{ name: c.name, kind: 'claimTemplate', claim: pvc.new(c.name, cfg.namespace, c.config, cfg.labels) }
       for c in cfg.claimTemplates]
      + [{ name: v.name, kind: 'volume', volume: v } for v in cfg.volumes]
      + [{ name: s.name, kind: 'volume', volume: volume.fromSecret(s.name, s.name) }
         for s in std.objectValues(cfg.secrets)]
      + [{ name: s.name, kind: 'volume', volume: volume.fromSecret(s.name, s.name) }
         for s in std.objectValues(cfg.externalSecretMounts)]
      + [local c = cfg.configMapMounts[path];
         local readOnly = if std.objectHas(c, 'readOnly') then c.readOnly else true;
         { name: c.name, kind: 'volume', volume: volume.fromConfigMap(c.name, c.name)
           + volume.configMap.withDefaultMode(std.parseOctal(if readOnly then '444' else '666')) }
         for path in std.objectFields(cfg.configMapMounts)]
    );
    local mounts = cfg.volumeMounts;
    local declaredNames = [v.name for v in definitions];
    assert std.all([std.isObject(m) && std.objectHas(m, 'name') && std.isString(m.name)
                   && std.objectHas(m, 'readOnly') && std.isBoolean(m.readOnly)
                   && std.objectHas(m, 'subPath') && (m.subPath == null || std.isString(m.subPath))
                   for m in std.objectValues(mounts)]) :
      'labsonnet: volume mounts require a volume name, boolean readOnly and string or null subPath';
    local unknownNames = [m.name for m in std.objectValues(mounts) if !std.member(declaredNames, m.name)];
    assert std.length(unknownNames) == 0 :
      'labsonnet: unknown volume mount references: %s' % std.join(', ', unknownNames);

    {
      claims: [v.claim for v in definitions if v.kind == 'claimTemplate'],
      volumes: [
        if v.kind == 'claimTemplate' then volume.fromPersistentVolumeClaim(v.name, v.name) else v.volume
        for v in definitions
        if cfg.type == 'Deployment' || v.kind != 'claimTemplate'
      ],
      mounts: [
        local m = mounts[path];
        volumeMount.new(m.name, path, m.readOnly)
        + (if m.subPath != null then { subPath: m.subPath } else {})
        for path in std.objectFields(mounts)
      ],
    },
}
