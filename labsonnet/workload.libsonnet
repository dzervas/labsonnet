// Workload builder — assembles a Deployment or StatefulSet.

local affinity = import './helpers/affinity.libsonnet';
local k = import 'k.libsonnet';
local pvcLib = import 'pvc.libsonnet';

local container = k.core.v1.container;
local envVar = k.core.v1.envVar;
local port = k.core.v1.containerPort;
local volume = k.core.v1.volume;
local volumeMount = k.core.v1.volumeMount;

{
  new(name, image, cfg)::
    local workload = if cfg.type == 'Deployment' then k.apps.v1.deployment else k.apps.v1.statefulSet;
    local imagePullPolicy = if std.endsWith(image, ':latest') || std.length(std.findSubstr(':', image)) == 0 then 'Always' else 'IfNotPresent';

    local pvVolumes = std.map(
      function(mountPath)
        local volName = pvcLib.volumeName(name, mountPath, cfg.pvs[mountPath]);
        if std.objectHas(cfg.pvs[mountPath], 'emptyDir') && cfg.pvs[mountPath].emptyDir then
          volume.fromEmptyDir(volName)
        else
          volume.fromPersistentVolumeClaim(volName, volName),
      std.objectFields(cfg.pvs)
    );

    local pvVolumeMounts = std.map(
      function(mountPath)
        local volName = pvcLib.volumeName(name, mountPath, cfg.pvs[mountPath]);
        local readOnly = std.objectHas(cfg.pvs[mountPath], 'readOnly') && cfg.pvs[mountPath].readOnly;
        volumeMount.new(volName, mountPath, readOnly),
      std.objectFields(cfg.pvs)
    );

    local secretVolumes = std.map(
      function(mountPath) volume.fromSecret(cfg.secrets[mountPath].name, cfg.secrets[mountPath].name),
      std.objectFields(cfg.secrets)
    );

    local secretVolumeMounts = std.map(
      function(mountPath)
        local s = cfg.secrets[mountPath];
        volumeMount.new(s.name, mountPath, if std.objectHas(s, 'readOnly') then s.readOnly else true),
      std.objectFields(cfg.secrets)
    );

    // External secrets mounted as volumes
    local extSecretNames = std.objectFields(cfg.externalSecretMounts);
    local extSecretVolumes = std.map(
      function(secretName)
        volume.fromSecret(secretName, secretName),
      extSecretNames
    );
    local extSecretVolumeMounts = std.map(
      function(secretName)
        local esm = cfg.externalSecretMounts[secretName];
        local readOnly = if std.objectHas(esm, 'readOnly') then esm.readOnly else true;
        volumeMount.new(secretName, esm.mountPath, readOnly),
      extSecretNames
    );

    local allVolumes = pvVolumes + secretVolumes + extSecretVolumes;
    local podVolumes = if cfg.type == 'Deployment' then allVolumes
    else std.filter(function(v) !std.objectHas(v, 'persistentVolumeClaim'), allVolumes);

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
      + container.withVolumeMounts(pvVolumeMounts + secretVolumeMounts + extSecretVolumeMounts)
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

    // Build default pod security context, then merge user overrides
    local defaultPodSecCtx =
      workload.spec.template.spec.securityContext.withFsGroup(cfg.runAsUser)
      + workload.spec.template.spec.securityContext.withRunAsNonRoot(true);
    local podSecCtxOverride =
      if std.length(std.objectFields(cfg.podSecurityContext)) > 0
      then { spec+: { template+: { spec+: { securityContext+: cfg.podSecurityContext } } } }
      else {};

    workload.new(name=name, replicas=cfg.replicas, containers=[ctr])
    + workload.spec.template.spec.withVolumes(podVolumes)
    + (if cfg.type == 'StatefulSet' then
         workload.spec.withVolumeClaimTemplates(pvcLib.build(name, cfg.namespace, cfg.pvs, cfg.labels))
         + (if cfg.serviceName != null then workload.spec.withServiceName(cfg.serviceName) else {})
         + (if cfg.podManagementPolicy != null then workload.spec.withPodManagementPolicy(cfg.podManagementPolicy) else {})
       else {})
    + configMapMounts
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
    + defaultPodSecCtx
    + podSecCtxOverride
    + workload.spec.template.metadata.withLabelsMixin(cfg.labels)
    + (if std.length(std.objectFields(cfg.podLabels)) > 0
       then workload.spec.template.metadata.withLabelsMixin(cfg.podLabels)
       else {})
    + (if std.length(std.objectFields(cfg.podAnnotations)) > 0
       then workload.spec.template.metadata.withAnnotationsMixin(cfg.podAnnotations)
       else {})
    + workload.spec.selector.withMatchLabelsMixin(cfg.labels),
}
