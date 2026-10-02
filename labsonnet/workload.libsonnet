// Workload builder — assembles a Deployment or StatefulSet.

local affinity = import './helpers/affinity.libsonnet';
local k = import 'k.libsonnet';

local container = k.core.v1.container;
local envVar = k.core.v1.envVar;
local port = k.core.v1.containerPort;
local volume = k.core.v1.volume;
local volumeMount = k.core.v1.volumeMount;

{
  new(name, image, cfg)::
    local workload = if cfg.type == 'Deployment' then k.apps.v1.deployment else k.apps.v1.statefulSet;
    local imagePullPolicy = if std.endsWith(image, ':latest') || std.length(std.findSubstr(':', image)) == 0 then 'Always' else 'IfNotPresent';

    local secretVolumeMounts = std.map(
      function(mountPath)
        local s = cfg.secrets[mountPath];
        volumeMount.new(s.name, mountPath, if std.objectHas(s, 'readOnly') then s.readOnly else true),
      std.objectFields(cfg.secrets)
    );

    // External secrets mounted as volumes, keyed by mount path.
    local extSecretVolumeMounts = std.map(
      function(mountPath)
        local esm = cfg.externalSecretMounts[mountPath];
        local readOnly = if std.objectHas(esm, 'readOnly') then esm.readOnly else true;
        volumeMount.new(esm.name, mountPath, readOnly),
      std.objectFields(cfg.externalSecretMounts)
    );

    local secretEnvVars = std.map(
      function(entry)
        envVar.withName(entry.name)
        + envVar.valueFrom.secretKeyRef.withName(entry.secret)
        + envVar.valueFrom.secretKeyRef.withKey(entry.key),
      cfg.secretEnvs
    );

    local fieldRefEnvVars = std.map(
      function(name)
        envVar.fromFieldPath(name, cfg.fieldRefEnvs[name]),
      std.objectFields(cfg.fieldRefEnvs)
    );

    // Build default container security context, then merge user overrides
    local defaultSecCtx =
      container.securityContext.withRunAsNonRoot(true)
      + container.securityContext.withRunAsUser(cfg.runAsUser)
      + container.securityContext.withRunAsGroup(cfg.runAsUser)
      + container.securityContext.withAllowPrivilegeEscalation(false)
      + container.securityContext.capabilities.withDrop(['ALL']);
    local secCtxOverride =
      if std.length(std.objectFields(cfg.securityContext)) > 0
      then { securityContext+: cfg.securityContext }
      else {};

    local ctr =
      container.new(name, image)
      + container.withImagePullPolicy(imagePullPolicy)
      + container.withPorts(std.map(
        function(p) port.new(p.port) + port.withProtocol(p.protocol) + port.withName(p.name),
        cfg.ports
      ))
      + container.withVolumeMounts(cfg.storage.mounts + secretVolumeMounts + extSecretVolumeMounts)
      + container.withEnv(secretEnvVars + fieldRefEnvVars)
      + container.withEnvMap(cfg.env)
      + (if cfg.command != null then container.withCommand(cfg.command) else {})
      + (if cfg.args != null then container.withArgs(cfg.args) else {})
      + defaultSecCtx
      + secCtxOverride
      + (if cfg.resources != null then { resources: cfg.resources } else {})
      + (if cfg.livenessProbe != null then { livenessProbe: cfg.livenessProbe } else {})
      + (if cfg.readinessProbe != null then { readinessProbe: cfg.readinessProbe } else {})
      + (if cfg.startupProbe != null then { startupProbe: cfg.startupProbe } else {});

    local inheritedInitContainers =
      if std.objectHas(cfg, 'initContainers') && std.length(cfg.initContainers) > 0 then
        std.map(
          function(ic)
            ic {
              volumeMounts:
                (if std.objectHas(ctr, 'volumeMounts') then ctr.volumeMounts else [])
                + (if std.objectHas(ic, 'volumeMounts') then ic.volumeMounts else []),
              env:
                (if std.objectHas(ctr, 'env') then ctr.env else [])
                + (if std.objectHas(ic, 'env') then ic.env else []),
            } + defaultSecCtx + secCtxOverride,
          cfg.initContainers
        )
      else [];

    local inheritedContainers =
      if std.objectHas(cfg, 'containers') && std.length(cfg.containers) > 0 then
        std.map(
          function(ic)
            ic {
              volumeMounts:
                (if std.objectHas(ctr, 'volumeMounts') then ctr.volumeMounts else [])
                + (if std.objectHas(ic, 'volumeMounts') then ic.volumeMounts else []),
              env:
                (if std.objectHas(ctr, 'env') then ctr.env else [])
                + (if std.objectHas(ic, 'env') then ic.env else []),
            } + defaultSecCtx + secCtxOverride,
          cfg.containers
        )
      else [];

    local configMapMounts = std.foldl(
      function(prev, mountPath)
        local cm = cfg.configMapMounts[mountPath];
        local readOnly = if std.objectHas(cm, 'readOnly') then cm.readOnly else true;
        prev + workload.configVolumeMount(
          cm.name,
          mountPath,
          volumeMountMixin=volumeMount.withReadOnly(readOnly),
          volumeMixin=volume.configMap.withDefaultMode(std.parseOctal(if readOnly then '444' else '666'))
        ),
      std.objectFields(cfg.configMapMounts),
      {}
    );

    // Merge overrides into the defaults, then omit explicit top-level nulls.
    // Filtering the final value lets callers remove defaults while retaining
    // false, zero, empty arrays, and empty objects as intentional values.
    local mergedPodSecCtx = {
      fsGroup: cfg.runAsUser,
      fsGroupChangePolicy: 'OnRootMismatch',
      runAsNonRoot: true,
    } + cfg.podSecurityContext;
    local finalPodSecCtx = {
      [field]: mergedPodSecCtx[field]
      for field in std.objectFields(mergedPodSecCtx)
      if mergedPodSecCtx[field] != null
    };
    local podSecCtxMixin =
      if std.length(std.objectFields(finalPodSecCtx)) > 0
      then { spec+: { template+: { spec+: { securityContext: finalPodSecCtx } } } }
      else {};

    workload.new(name=name, replicas=cfg.replicas, containers=[ctr])
    + workload.spec.template.spec.withVolumes(cfg.storage.volumes)
    + (if cfg.type == 'StatefulSet' then
         workload.spec.withVolumeClaimTemplates(cfg.storage.claims)
         + (if cfg.serviceName != null then workload.spec.withServiceName(cfg.serviceName) else {})
         + (if cfg.podManagementPolicy != null then workload.spec.withPodManagementPolicy(cfg.podManagementPolicy) else {})
       else {})
    + configMapMounts
    // ConfigMap mixins add their mounts; use the centrally resolved volumes.
    + { spec+: { template+: { spec+: { volumes: cfg.storage.volumes } } } }
    + (if cfg.affinity != null then affinity.withWorkloadAffinity(cfg.affinity) else {})
    + workload.metadata.withNamespace(cfg.namespace)
    + (if std.length(cfg.imagePullSecrets) > 0
       then workload.spec.template.spec.withImagePullSecrets(
         std.map(function(s) { name: s }, cfg.imagePullSecrets)
       )
       else {})
    + (if std.length(inheritedInitContainers) > 0
       then { spec+: { template+: { spec+: { initContainers: inheritedInitContainers } } } }
       else {})
    + (if std.length(inheritedContainers) > 0
       then { spec+: { template+: { spec+: { containers+: inheritedContainers } } } }
       else {})
    + podSecCtxMixin
    + workload.spec.template.metadata.withLabelsMixin(cfg.labels)
    + (if std.length(std.objectFields(cfg.podLabels)) > 0
       then workload.spec.template.metadata.withLabelsMixin(cfg.podLabels)
       else {})
    + (if std.length(std.objectFields(cfg.podAnnotations)) > 0
       then workload.spec.template.metadata.withAnnotationsMixin(cfg.podAnnotations)
       else {})
    + workload.spec.selector.withMatchLabelsMixin(cfg.labels),
}
