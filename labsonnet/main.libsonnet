// labsonnet — Compositional Kubernetes service builder using + operator.
// Build workload + service + routes + pvcs + external secrets with with*() functions.

local k = import 'k.libsonnet';
local nsLib = k.core.v1.namespace;

local pvcLib = import 'pvc.libsonnet';
local workloadLib = import 'workload.libsonnet';
local serviceLib = import 'service.libsonnet';
local ingressLib = import 'ingress.libsonnet';
local gatewayLib = import 'gateway.libsonnet';
local externalSecretLib = import 'externalsecret.libsonnet';
local serviceMonitorHelper = import 'helpers/servicemonitor.libsonnet';

// Combined routing metadata: Gateway API routes + ingress.
// Used for protocol inference, layer classification, and validation.
local routingMeta = gatewayLib.meta + ingressLib.meta;
local routingKeys = std.objectFields(routingMeta);


local portRoutingKeys(port) = std.filter(function(rk) std.objectHas(port, rk), routingKeys);

local processPort(port) =
  local rkeys = portRoutingKeys(port);
  local routingKey = if std.length(rkeys) > 0 then rkeys[0] else null;
  local routingCfg = if routingKey != null then port[routingKey] else null;
  local protocol =
    if routingKey != null then routingMeta[routingKey].protocol
    else if std.objectHas(port, 'protocol') then port.protocol
    else 'TCP';
  local portName =
    if std.objectHas(port, 'name') then port.name
    else '%s-%d' % [std.asciiLower(protocol), port.port];
  local routeFqdn =
    if routingCfg != null && std.objectHas(routingCfg, 'fqdn') then routingCfg.fqdn
    else null;
  {
    normalized: { port: port.port, protocol: protocol, name: portName },
    routingKey: routingKey,
    routingCfg: routingCfg,
    portName: portName,
    fqdn: routeFqdn,
  };

local dedupPorts(ports) =
  // Create scalar key to easily identify duplicates based on port+protocol
  local portKey(p) = '%d/%s' % [p.port, p.protocol];
  std.foldl(
    function(acc, p)
      local key = portKey(p);
      if std.member(acc.seen, key) then acc
      else { seen: acc.seen + [key], result: acc.result + [p] },
    ports,
    { seen: [], result: [] }
  ).result;

{
  new(name, image):: {
    _name:: name,
    _image:: image,
    _type:: 'Deployment',
    _namespace:: name,
    _createNamespace:: false,
    _replicas:: 1,
    _fqdn:: null,
    _affinity:: null,
    _command:: null,
    _args:: null,
    _runAsUser:: 1000,
    _serviceType:: 'ClusterIP',
    _headlessService:: false,
    _headlessPublishNotReady:: true,
    _serviceName:: null,
    _podManagementPolicy:: null,
    _fieldRefEnvs:: {},
    _ports:: [],
    _pvs:: {},
    _configMaps:: {},
    _secrets:: {},
    _env:: {},
    _externalSecrets:: {},
    _externalSecretMounts:: {},
    _imagePullSecrets:: [],
    _namespaceLabels:: {},
    _namespaceAnnotations:: {},
    _resources:: null,
    _livenessProbe:: null,
    _readinessProbe:: null,
    _startupProbe:: null,
    _securityContext:: {},
    _podSecurityContext:: {},
    _podLabels:: {},
    _podAnnotations:: {},
    _serviceMonitors:: {},
    _labels:: {
      app: name,
      'app.kubernetes.io/name': name,
    },

    local me = self,

    local processedPorts = std.map(processPort, me._ports),
    local normalizedPorts = std.map(function(pp) pp.normalized, processedPorts),
    local uniquePorts = dedupPorts(normalizedPorts),
    local routedPorts = std.filter(function(pp) pp.routingKey != null, processedPorts),

    local esSuffixes = std.objectFields(me._externalSecrets),
    local esMountSuffixes = std.objectFields(me._externalSecretMounts),
    local secretEnvs = std.flatMap(
      function(suffix)
        local es = me._externalSecrets[suffix];
        local envs = if std.objectHas(es, 'envs') then es.envs else {};
        local secretName = me._name + '-' + suffix;
        std.map(
          function(envName) { name: envName, secret: secretName, key: envs[envName] },
          std.objectFields(envs)
        ),
      esSuffixes
    ),

    local hasRealPvs = std.length(std.filter(
      function(mountPath) !(std.objectHas(me._pvs[mountPath], 'emptyDir') && me._pvs[mountPath].emptyDir),
      std.objectFields(me._pvs)
    )) > 0,

    assert std.length(me._ports) > 0 :
           "labsonnet '%s': at least one port is required" % me._name,

    assert std.all(std.map(
      function(p) std.isObject(p) && std.objectHas(p, 'port') && std.isNumber(p.port),
      me._ports
    )) : "labsonnet '%s': each port entry must be an object with a numeric 'port' field" % me._name,

    assert std.all(std.map(
      function(p) std.length(portRoutingKeys(p)) <= 1,
      me._ports
    )) : "labsonnet '%s': each port entry may have at most one routing type" % me._name,

    assert std.all(std.map(
      function(p)
        local rkeys = portRoutingKeys(p);
        !(std.length(rkeys) > 0 && std.objectHas(p, 'protocol')) || p.protocol == routingMeta[rkeys[0]].protocol,
      me._ports
    )) : "labsonnet '%s': explicit 'protocol' conflicts with routing type" % me._name,

    local portNames = std.map(function(p) p.name, normalizedPorts),
    assert std.length(portNames) == std.length(std.set(portNames)) :
           "labsonnet '%s': duplicate port name in ports" % me._name,

    assert me._type == 'Deployment' || me._type == 'StatefulSet' :
           "labsonnet '%s': unsupported type '%s' (must be 'Deployment' or 'StatefulSet')" % [me._name, me._type],
    assert !me._headlessService || me._type == 'StatefulSet' :
           "labsonnet '%s': 'headlessService' is only supported for StatefulSet workloads" % me._name,
    assert me._podManagementPolicy == null
           || (me._type == 'StatefulSet' && (me._podManagementPolicy == 'OrderedReady' || me._podManagementPolicy == 'Parallel')) :
           "labsonnet '%s': 'podManagementPolicy' must be 'OrderedReady' or 'Parallel' and requires StatefulSet type" % me._name,
    assert !hasRealPvs || me._type == 'StatefulSet' :
           "labsonnet '%s': 'type' must be 'StatefulSet' when pvs with persistent storage are defined" % me._name,
    assert std.isNumber(me._replicas) && me._replicas > 0 :
           "labsonnet '%s': 'replicas' must be a positive integer" % me._name,
    assert std.isNumber(me._runAsUser) :
           "labsonnet '%s': 'runAsUser' must be a number" % me._name,

    assert std.all(std.map(
      function(pp)
        !(pp.routingKey != null && routingMeta[pp.routingKey].layer == 'L7')
        || pp.fqdn != null || me._fqdn != null,
      processedPorts
    )) : "labsonnet '%s': 'fqdn' is required for each L7 route (set per-route or service-level via withFqdn)" % me._name,

    assert std.all(std.map(
      function(pp)
        if pp.routingKey != null && std.member(gatewayLib.routeKeys, pp.routingKey) then
          local gw = if std.objectHas(pp.routingCfg, 'gateway') then pp.routingCfg.gateway else {};
          std.objectHas(gw, 'name') && std.objectHas(gw, 'namespace')
        else true,
      processedPorts
    )) : "labsonnet '%s': gateway routes require 'gateway.name' and 'gateway.namespace'" % me._name,

    assert std.all(std.map(
      function(pp)
        if pp.routingKey != null && std.member(gatewayLib.routeKeys, pp.routingKey) && routingMeta[pp.routingKey].layer == 'L4' then
          local gw = if std.objectHas(pp.routingCfg, 'gateway') then pp.routingCfg.gateway else {};
          std.objectHas(gw, 'sectionName')
        else true,
      processedPorts
    )) : "labsonnet '%s': L4 routes (tcpRoute/udpRoute) require 'gateway.sectionName'" % me._name,

    assert std.all(std.map(
      function(mountPath) std.isObject(me._configMaps[mountPath]) && std.objectHas(me._configMaps[mountPath], 'name'),
      std.objectFields(me._configMaps)
    )) : "labsonnet '%s': each configMaps entry must be an object with a 'name' field" % me._name,

    assert std.all(std.map(
      function(mountPath) std.isObject(me._secrets[mountPath]) && std.objectHas(me._secrets[mountPath], 'name'),
      std.objectFields(me._secrets)
    )) : "labsonnet '%s': each secrets entry must be an object with a 'name' field" % me._name,

    assert std.all(std.map(
      function(mountPath)
        local pv = me._pvs[mountPath];
        (std.objectHas(pv, 'emptyDir') && pv.emptyDir) || std.objectHas(pv, 'size'),
      std.objectFields(me._pvs)
    )) : "labsonnet '%s': all pvs entries must have a 'size' field (unless 'emptyDir' is true)" % me._name,

    assert std.all(std.map(
      function(suffix)
        local es = me._externalSecrets[suffix];
        local hasEnvs = std.objectHas(es, 'envs') && std.isObject(es.envs) && std.length(std.objectFields(es.envs)) > 0;
        local hasMount = std.member(esMountSuffixes, suffix);
        std.objectHas(es, 'store') && std.isString(es.store) && std.length(es.store) > 0
        && (hasEnvs || hasMount),
      esSuffixes
    )) : "labsonnet '%s': each externalSecrets entry must have a non-empty 'store' string and either non-empty 'envs' object or a corresponding mount" % me._name,

    // Validate that every externalSecretMount suffix has a corresponding externalSecret
    assert std.all(std.map(
      function(suffix) std.member(esSuffixes, suffix),
      esMountSuffixes
    )) : "labsonnet '%s': each externalSecretMounts suffix must have a corresponding externalSecrets entry" % me._name,

    // Validate resources structure if provided
    assert me._resources == null || std.isObject(me._resources) :
           "labsonnet '%s': 'resources' must be an object with 'requests' and/or 'limits'" % me._name,

    // Validate probes are objects if provided
    assert me._livenessProbe == null || std.isObject(me._livenessProbe) :
           "labsonnet '%s': 'livenessProbe' must be an object" % me._name,
    assert me._readinessProbe == null || std.isObject(me._readinessProbe) :
           "labsonnet '%s': 'readinessProbe' must be an object" % me._name,
    assert me._startupProbe == null || std.isObject(me._startupProbe) :
           "labsonnet '%s': 'startupProbe' must be an object" % me._name,

    // Validate serviceMonitors reference existing port names
    assert std.all(std.map(
      function(monitorName)
        local mon = me._serviceMonitors[monitorName];
        std.member(portNames, mon.portName),
      std.objectFields(me._serviceMonitors)
    )) : "labsonnet '%s': each serviceMonitor must reference a valid port name" % me._name,

    // Auto-derive serviceName from headless service when not explicitly set.
    local effectiveServiceName =
      if me._serviceName != null then me._serviceName
      else if me._headlessService then me._name + '-headless'
      else null,

    local cfg = {
      type: me._type,
      namespace: me._namespace,
      replicas: me._replicas,
      fqdn: me._fqdn,
      affinity: me._affinity,
      command: me._command,
      args: me._args,
      runAsUser: me._runAsUser,
      serviceType: me._serviceType,
      headlessPublishNotReady: me._headlessPublishNotReady,
      serviceName: effectiveServiceName,
      podManagementPolicy: me._podManagementPolicy,
      fieldRefEnvs: me._fieldRefEnvs,
      ports: uniquePorts,
      pvs: me._pvs,
      configMaps: me._configMaps,
      secrets: me._secrets,
      env: me._env,
      externalSecrets: me._externalSecrets,
      externalSecretMounts: me._externalSecretMounts,
      imagePullSecrets: me._imagePullSecrets,
      labels: me._labels,
      secretEnvs: secretEnvs,
      resources: me._resources,
      livenessProbe: me._livenessProbe,
      readinessProbe: me._readinessProbe,
      startupProbe: me._startupProbe,
      securityContext: me._securityContext,
      podSecurityContext: me._podSecurityContext,
      podLabels: me._podLabels,
      podAnnotations: me._podAnnotations,
    },

    namespace:
      if me._createNamespace then
        nsLib.new(me._namespace)
        + nsLib.metadata.withLabels(me._namespaceLabels)
        + (if std.length(std.objectFields(me._namespaceAnnotations)) > 0
           then nsLib.metadata.withAnnotations(me._namespaceAnnotations)
           else {})
      else {},

    workload: workloadLib.new(me._name, me._image, cfg),
    service: serviceLib.new(me._name, cfg),
    headlessService: if me._headlessService then serviceLib.newHeadless(me._name, cfg) else {},

    routing: {
      [entry.portName]:
        // Resolve fqdn: per-route takes precedence over service-level default.
        local effectiveFqdn = if entry.fqdn != null then entry.fqdn else me._fqdn;
        if std.member(gatewayLib.routeKeys, entry.routingKey) then
          local rawGw = if std.objectHas(entry.routingCfg, 'gateway') then entry.routingCfg.gateway else {};
          local gwDefaults = if routingMeta[entry.routingKey].layer == 'L7' then { sectionName: 'https' } else {};
          local merged = { gateway: gwDefaults + rawGw } + entry.routingCfg;
          gatewayLib.build(
            entry.routingKey,
            '%s-%s' % [me._name, entry.portName],
            me._name,
            me._namespace,
            effectiveFqdn,
            entry.normalized.port,
            merged
          )
        else
          ingressLib.new(
            '%s-%s' % [me._name, entry.portName],
            me._name,
            me._namespace,
            effectiveFqdn,
            entry.normalized.port,
            entry.routingCfg
          )
      for entry in routedPorts
    },

    pvc: if me._type == 'Deployment' then pvcLib.build(me._name, me._namespace, me._pvs, me._labels) else null,

    externalSecrets: {
      [suffix]: externalSecretLib.new(
        name=me._name,
        namespace=me._namespace,
        suffix=suffix,
        storeName=me._externalSecrets[suffix].store,
        storeKind=if std.objectHas(me._externalSecrets[suffix], 'storeKind') then me._externalSecrets[suffix].storeKind else 'ClusterSecretStore',
        remoteKey=if std.objectHas(me._externalSecrets[suffix], 'remoteKey') then me._externalSecrets[suffix].remoteKey else null,
      )
      for suffix in esSuffixes
    },

    monitors: {
      [monitorName]: serviceMonitorHelper.new(
        '%s-%s' % [me._name, monitorName],
        me._namespace,
        portName=me._serviceMonitors[monitorName].portName,
        path=me._serviceMonitors[monitorName].path,
        interval=me._serviceMonitors[monitorName].interval,
        labels=me._labels,
        selector=me._labels,
      )
      for monitorName in std.objectFields(me._serviceMonitors)
    },
  },

  // --- Scalar overrides (last writer wins) ---

  withFqdn(fqdn):: { _fqdn:: fqdn },
  withType(type):: { _type:: type },
  withReplicas(n):: { _replicas:: n },
  withCommand(cmd):: { _command:: cmd },
  withArgs(args):: { _args:: args },
  withRunAsUser(uid):: { _runAsUser:: uid },
  withAffinity(aff):: { _affinity:: aff },
  withServiceType(t):: { _serviceType:: t },
  withCreateNamespace(create=true):: { _createNamespace:: create },
  withNamespace(ns):: { _namespace:: ns },
  withHeadlessService(publishNotReadyAddresses=true):: {
    _headlessService:: true,
    _headlessPublishNotReady:: publishNotReadyAddresses,
  },
  withServiceName(name):: { _serviceName:: name },
  withPodManagementPolicy(policy):: { _podManagementPolicy:: policy },

  // Resources: { requests: { cpu, memory }, limits: { cpu, memory } }
  withResources(resources):: { _resources:: resources },

  // Probes: raw Kubernetes probe objects
  // e.g. { httpGet: { path: '/healthz', port: 8080 }, initialDelaySeconds: 10, periodSeconds: 30 }
  withLivenessProbe(probe):: { _livenessProbe:: probe },
  withReadinessProbe(probe):: { _readinessProbe:: probe },
  withStartupProbe(probe):: { _startupProbe:: probe },

  // Security context overrides (merged with defaults)
  // Container-level: overrides runAsNonRoot, runAsUser, capabilities, etc.
  withSecurityContext(ctx):: { _securityContext:: ctx },
  // Pod-level: overrides fsGroup, runAsNonRoot, supplementalGroups, etc.
  withPodSecurityContext(ctx):: { _podSecurityContext:: ctx },

  // --- Merge/append accumulators ---

  withPort(portEntry):: { _ports+:: [portEntry] },
  withPV(mountPath, pvConfig):: { _pvs+:: { [mountPath]: pvConfig } },
  withEmptyDir(mountPath):: { _pvs+:: { [mountPath]: { emptyDir: true } } },
  withConfigMap(mountPath, name, readOnly=true):: {
    _configMaps+:: { [mountPath]: { name: name, readOnly: readOnly } },
  },
  withSecretMount(mountPath, name, readOnly=true):: {
    _secrets+:: { [mountPath]: { name: name, readOnly: readOnly } },
  },
  withEnv(env):: { _env+:: env },
  withFieldRefEnv(envs):: { _fieldRefEnvs+:: envs },
  withExternalSecret(suffix, cfg):: { _externalSecrets+:: { [suffix]: cfg } },
  withExternalSecretMount(suffix, mountPath, readOnly=true):: {
    _externalSecretMounts+:: { [suffix]: { mountPath: mountPath, readOnly: readOnly } },
  },
  withImagePullSecrets(s):: { _imagePullSecrets+:: s },
  withNamespaceLabels(l):: { _namespaceLabels+:: l },
  withNamespaceAnnotations(a):: { _namespaceAnnotations+:: a },

  // Pod template labels/annotations (distinct from namespace labels/annotations)
  withPodLabels(l):: { _podLabels+:: l },
  withPodAnnotations(a):: { _podAnnotations+:: a },

  // ServiceMonitor for Prometheus/VictoriaMetrics scraping.
  // portName must match a port name from withPort(). name defaults to portName.
  withServiceMonitor(portName='metrics', path='/metrics', interval='30s', name=null):: {
    _serviceMonitors+:: {
      [if name != null then name else portName]: {
        portName: portName,
        path: path,
        interval: interval,
      },
    },
  },
}
