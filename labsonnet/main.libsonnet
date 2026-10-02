// labsonnet — Compositional Kubernetes service builder using + operator.
// Build workload + service + routes + pvcs + external secrets with with*() functions.

local d = import 'github.com/jsonnet-libs/docsonnet/doc-util/main.libsonnet';
local k = import 'k.libsonnet';
local nsLib = k.core.v1.namespace;

local storageLib = import 'storage.libsonnet';
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

local declareVolume(v) = { _volumes+:: [v] };


local portRoutingKeys(port) = std.filter(function(rk) std.objectHas(port, rk), routingKeys);

local addPort(portEntry, headless) =
  assert std.isObject(portEntry) : 'each port entry must be an object';
  assert !std.objectHas(portEntry, 'service') && !std.objectHas(portEntry, 'headlessService') :
         'use withPort() or withHeadlessPort() to choose Service exposure';
  { _ports+:: [portEntry { service: !headless, headlessService: headless }] };

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
    normalized: {
      port: port.port,
      protocol: protocol,
      name: portName,
      service: port.service,
      headlessService: port.headlessService,
    },
    routingKey: routingKey,
    routingCfg: routingCfg,
    portName: portName,
    fqdn: routeFqdn,
  };

local dedupBy(entries, keyFor) =
  std.foldl(
    function(acc, p)
      local key = keyFor(p);
      if std.member(acc.seen, key) then acc
      else { seen: acc.seen + [key], result: acc.result + [p] },
    entries,
    { seen: [], result: [] }
  ).result;

local dedupPorts(ports) = dedupBy(ports, function(p) '%d/%s' % [p.port, p.protocol]);
local dedupRoutes(routes) = dedupBy(routes, function(r) r.portName);

{
  '#':: d.pkg(
    name='labsonnet',
    url='https://github.com/dzervas/labsonnet',
    help='Commonly used components to define a Kubernetes workload, mainly from a bare docker image',
    filename=std.thisFile,
    version='main'
  ),

  '#new':: d.fn(
    help=|||
      Main entrypoint for labsonnet, defines a new "app".
      The `name` is used for most of the resources, namespace, service name, etc.

      The rest of the functions work on top of this to alter various aspects of the app.

      Example:

      ```jsonnet
      labsonnet.new('hello-world', 'nginx:latest')
      + labsonnet.withEnv('MY_VAR', 'my-value')
      ```
    |||,
    args=[
      d.arg('name', d.T.string),
      d.arg('image', d.T.string),
    ]
  ),
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
    _containers:: [],
    _initContainers:: [],
    _runAsUser:: 1000,
    _serviceType:: 'ClusterIP',
    _headlessService:: false,
    _headlessServiceName:: null,
    _headlessPublishNotReady:: true,
    _serviceName:: null,
    _podManagementPolicy:: null,
    _fieldRefEnvs:: {},
    _secretEnvs:: {},
    _ports:: [],
    _claimTemplates:: [],
    _volumes:: [],
    _volumeMounts:: {},
    _mountPaths:: [],
    _configMapMounts:: {},
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

    // Service ports
    assert std.length(me._ports) > 0 : "labsonnet '%s': at least one port is required" % me._name,
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

    local processedPorts = std.map(processPort, me._ports),
    assert std.all(std.map(
      function(pp)
        !(pp.routingKey != null && routingMeta[pp.routingKey].layer == 'L7')
        || pp.fqdn != null || me._fqdn != null,
      processedPorts
    )) : "labsonnet '%s': 'fqdn' is required for each L7 route (set per-route or service-level via withFqdn)" % me._name,

    local normalizedPorts = std.map(function(pp) pp.normalized, processedPorts),
    local portNames = std.map(function(p) p.name, normalizedPorts),

    local uniquePorts = dedupPorts(normalizedPorts),
    // Each Service deduplicates its own declarations independently.
    local servicePorts = dedupPorts(std.filter(function(p) p.service, normalizedPorts)),
    local headlessServicePorts = dedupPorts(std.filter(function(p) p.headlessService, normalizedPorts)),
    local routeEntries = std.filter(function(pp) pp.routingKey != null, processedPorts),
    local routedPorts = dedupRoutes(routeEntries),

    assert std.all([
      p.name != q.name || (p.port == q.port && p.protocol == q.protocol)
      for p in normalizedPorts
      for q in normalizedPorts
    ]) : "labsonnet '%s': duplicate port name must reference the same port/protocol pair" % me._name,
    assert std.all([
      p.portName != q.portName || (p.routingKey == q.routingKey && p.routingCfg == q.routingCfg)
      for p in routeEntries
      for q in routeEntries
    ]) : "labsonnet '%s': conflicting routing configurations for the same port name" % me._name,

    assert std.all(std.map(
      function(pp) std.length(std.filter(
        function(p) p.port == pp.normalized.port && p.protocol == pp.normalized.protocol,
        servicePorts
      )) > 0,
      routedPorts
    )) : "labsonnet '%s': each route must reference a port exposed by the ordinary Service" % me._name,

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

    // Workload Type
    assert me._type == 'Deployment' || me._type == 'StatefulSet' :
           "labsonnet '%s': unsupported type '%s' (must be 'Deployment' or 'StatefulSet')" % [me._name, me._type],
    assert me._podManagementPolicy == null
           || (me._type == 'StatefulSet' && (me._podManagementPolicy == 'OrderedReady' || me._podManagementPolicy == 'Parallel')) :
           "labsonnet '%s': 'podManagementPolicy' must be 'OrderedReady' or 'Parallel' and requires StatefulSet type" % me._name,
    assert std.isNumber(me._replicas) && me._replicas >= 0 && std.floor(me._replicas) == me._replicas :
           "labsonnet '%s': 'replicas' must be a non-negative integer" % me._name,
    assert std.isNumber(me._runAsUser) :
           "labsonnet '%s': 'runAsUser' must be a number" % me._name,

    // Kubernetes Secrets
    assert std.all(std.map(
      function(mountPath) std.isObject(me._secrets[mountPath]) && std.objectHas(me._secrets[mountPath], 'name'),
      std.objectFields(me._secrets)
    )) : "labsonnet '%s': each secrets entry must be an object with a 'name' field" % me._name,

    // ExternalSecrets
    local esNames = std.objectFields(me._externalSecrets),
    local esMountNames = [m.name for m in std.objectValues(me._externalSecretMounts)],
    local secretEnvs = std.flatMap(
      function(secretName)
        local es = me._externalSecrets[secretName];
        local envs = if std.objectHas(es, 'envs') then es.envs else {};
        std.map(
          function(envName) { name: envName, secret: secretName, key: envs[envName] },
          std.objectFields(envs)
        ),
      esNames
    ) + std.map(
      function(envName)
        local ref = me._secretEnvs[envName];
        { name: envName, secret: ref.name, key: ref.key },
      std.objectFields(me._secretEnvs)
    ),
    assert std.all(std.map(
      function(secretName)
        local es = me._externalSecrets[secretName];
        local hasEnvs = std.objectHas(es, 'envs') && std.isObject(es.envs) && std.length(std.objectFields(es.envs)) > 0;
        local hasMount = std.member(esMountNames, secretName);
        std.objectHas(es, 'store') && std.isString(es.store) && std.length(es.store) > 0
        && (hasEnvs || hasMount),
      esNames
    )) : "labsonnet '%s': each externalSecrets entry must have a non-empty 'store' string and either non-empty 'envs' object or a corresponding mount" % me._name,
    assert std.all(std.map(
      function(envName)
        local ref = me._secretEnvs[envName];
        std.isObject(ref)
        && std.objectHas(ref, 'name') && std.isString(ref.name) && std.length(ref.name) > 0
        && std.objectHas(ref, 'key') && std.isString(ref.key) && std.length(ref.key) > 0,
      std.objectFields(me._secretEnvs)
    )) : "labsonnet '%s': each withSecretEnv entry must be { ENV_NAME: { name: secretName, key: secretKey } }" % me._name,

    // ConfigMaps
    assert std.all(std.map(
      function(mountPath) std.isObject(me._configMapMounts[mountPath]) && std.objectHas(me._configMapMounts[mountPath], 'name'),
      std.objectFields(me._configMapMounts)
    )) : "labsonnet '%s': each configMapMounts entry must be an object with a 'name' field" % me._name,

    // Affinity (validate the final composed value)
    local aff = me._affinity,
    assert aff == null || std.isObject(aff) :
           "labsonnet '%s': 'affinity' must be null or an object" % me._name,
    local affinityFields = if std.isObject(aff) then std.objectFields(aff) else [],
    assert !std.isObject(aff) || std.length(affinityFields) > 0 || std.length(std.objectFieldsAll(aff)) == 0 :
           "labsonnet '%s': 'affinity' has only hidden fields; pass a concrete affinity object, or null or {} for unrestricted placement" % me._name,
    local unknownAffinityFields = std.filter(
      function(field) !std.member(['nodeAffinity', 'podAffinity', 'podAntiAffinity'], field),
      affinityFields
    ),
    assert std.length(unknownAffinityFields) == 0 :
           "labsonnet '%s': 'affinity' has unknown visible fields: %s (allowed: nodeAffinity, podAffinity, podAntiAffinity)" % [me._name, std.join(', ', unknownAffinityFields)],
    local invalidAffinityFields = std.filter(function(field) !std.isObject(aff[field]), affinityFields),
    assert std.length(invalidAffinityFields) == 0 :
           "labsonnet '%s': 'affinity' fields must contain objects: %s" % [me._name, std.join(', ', invalidAffinityFields)],

    // Probes
    assert me._livenessProbe == null || std.isObject(me._livenessProbe) :
           "labsonnet '%s': 'livenessProbe' must be an object" % me._name,
    assert me._readinessProbe == null || std.isObject(me._readinessProbe) :
           "labsonnet '%s': 'readinessProbe' must be an object" % me._name,
    assert me._startupProbe == null || std.isObject(me._startupProbe) :
           "labsonnet '%s': 'startupProbe' must be an object" % me._name,

    // Service Monitors
    assert std.all(std.map(
      function(monitorName)
        local mon = me._serviceMonitors[monitorName];
        std.member(portNames, mon.portName),
      std.objectFields(me._serviceMonitors)
    )) : "labsonnet '%s': each serviceMonitor must reference a valid port name" % me._name,

    // Custom resources
    assert me._resources == null || std.isObject(me._resources) :
           "labsonnet '%s': 'resources' must be an object with 'requests' and/or 'limits'" % me._name,

    local effectiveHeadlessServiceName =
      if me._headlessServiceName != null then me._headlessServiceName
      else me._name + '-headless',

    // Auto-derive StatefulSet serviceName from the generated headless Service.
    local effectiveStatefulSetServiceName =
      if me._serviceName != null then me._serviceName
      else if me._headlessService then effectiveHeadlessServiceName
      else null,

    local cfg = {
      type: me._type,
      namespace: me._namespace,
      replicas: me._replicas,
      fqdn: me._fqdn,
      affinity: me._affinity,
      command: me._command,
      args: me._args,
      containers: me._containers,
      initContainers: me._initContainers,
      runAsUser: me._runAsUser,
      serviceType: me._serviceType,
      headlessPublishNotReady: me._headlessPublishNotReady,
      serviceName: effectiveStatefulSetServiceName,
      podManagementPolicy: me._podManagementPolicy,
      fieldRefEnvs: me._fieldRefEnvs,
      ports: uniquePorts,
      servicePorts: servicePorts,
      headlessServicePorts: headlessServicePorts,
      claimTemplates: me._claimTemplates,
      volumes: me._volumes,
      volumeMounts: me._volumeMounts,
      mountPaths: me._mountPaths,
      configMapMounts: me._configMapMounts,
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

    local storage = storageLib.resolve(cfg),

    namespace:
      if me._createNamespace then
        nsLib.new(me._namespace)
        + nsLib.metadata.withLabels(me._namespaceLabels)
        + (if std.length(std.objectFields(me._namespaceAnnotations)) > 0
           then nsLib.metadata.withAnnotations(me._namespaceAnnotations)
           else {})
      else {},

    workload: workloadLib.new(me._name, me._image, cfg { storage: storage }),
    service: if std.length(servicePorts) > 0 then serviceLib.new(me._name, cfg) else {},
    headlessService: if me._headlessService then serviceLib.newHeadless(effectiveHeadlessServiceName, cfg) else {},

    routing: {
      [entry.portName]:
        // Resolve fqdn: per-route takes precedence over service-level default.
        local effectiveFqdn = if entry.fqdn != null then entry.fqdn else me._fqdn;
        local resourceName =
          if std.objectHas(entry.routingCfg, 'name') then entry.routingCfg.name
          else '%s-%s' % [me._name, entry.portName];
        if std.member(gatewayLib.routeKeys, entry.routingKey) then
          local rawGw = if std.objectHas(entry.routingCfg, 'gateway') then entry.routingCfg.gateway else {};
          local gwDefaults = if routingMeta[entry.routingKey].layer == 'L7' then { sectionName: 'https' } else {};
          local merged = { gateway: gwDefaults + rawGw } + entry.routingCfg;
          gatewayLib.build(
            entry.routingKey,
            resourceName,
            me._name,
            me._namespace,
            effectiveFqdn,
            entry.normalized.port,
            merged
          )
        else
          ingressLib.new(
            resourceName,
            me._name,
            me._namespace,
            effectiveFqdn,
            entry.normalized.port,
            entry.routingCfg
          )
      for entry in routedPorts
    },

    pvc: if me._type == 'Deployment' then storage.claims else null,

    externalSecrets: {
      [secretName]:
        local es = me._externalSecrets[secretName];
        externalSecretLib.new(
          name=secretName,
          namespace=me._namespace,
          storeName=es.store,
          storeKind=if std.objectHas(es, 'storeKind') then es.storeKind else 'ClusterSecretStore',
          remoteKey=if std.objectHas(es, 'remoteKey') then es.remoteKey else null,
          refreshInterval=if std.objectHas(es, 'refreshInterval') then es.refreshInterval else null,
          refreshPolicy=if std.objectHas(es, 'refreshPolicy') then es.refreshPolicy else null,
          creationPolicy=if std.objectHas(es, 'creationPolicy') then es.creationPolicy else null,
          deletionPolicy=if std.objectHas(es, 'deletionPolicy') then es.deletionPolicy else null,
        )
      for secretName in esNames
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

  '#withFqdn':: d.fn(
    help='Set the FQDN for the app',
    args=[d.arg('fqdn', d.T.string)],
  ),
  withFqdn(fqdn):: { _fqdn:: fqdn },
  '#withType':: d.fn(
    help='Set the workload type of the app (Deployment or StatefulSet)',
    args=[d.arg('type', d.T.string)],
  ),
  withType(type):: { _type:: type },
  '#withReplicas':: d.fn(
    help='Set the number of replicas for the app (a non-negative integer)',
    args=[d.arg('replicas', d.T.number)],
  ),
  withReplicas(n):: { _replicas:: n },
  '#withCommand':: d.fn(
    help='Set the command for the app',
    args=[d.arg('command', d.T.array)],
  ),
  withCommand(cmd):: { _command:: cmd },
  '#withArgs':: d.fn(
    help='Set the arguments for the app',
    args=[d.arg('args', d.T.array)],
  ),
  withArgs(args):: { _args:: args },
  '#withContainer':: d.fn(
    help='Add an additional container to the app - pass a standard k.core.v1.container object',
    args=[d.arg('container', d.T.object)],
  ),
  withContainer(container):: { _containers+:: [container] },
  '#withInitContainer':: d.fn(
    help='Add an init container to the app - pass a standard k.core.v1.container object',
    args=[d.arg('container', d.T.object)],
  ),
  withInitContainer(container):: { _initContainers+:: [container] },
  '#withRunAsUser':: d.fn(
    help='Set the UID & GID for the app',
    args=[d.arg('uid', d.T.number)],
  ),
  withRunAsUser(uid):: { _runAsUser:: uid },
  '#withAffinity':: d.fn(
    help='Set workload affinity with nodeAffinity, podAffinity, or podAntiAffinity object fields (see helpers/affinity.libsonnet)',
    args=[d.arg('affinity', 'object | null')],
  ),
  withAffinity(aff):: { _affinity:: aff },
  '#withServiceType':: d.fn(
    help='Set the service type for the app (ClusterIP, NodePort, LoadBalancer, ExternalName)',
    args=[d.arg('type', d.T.string)],
  ),
  withServiceType(t):: { _serviceType:: t },
  '#withCreateNamespace':: d.fn(
    help='Set whether to create the namespace',
    args=[d.arg('create', d.T.boolean, true)],
  ),
  withCreateNamespace(create=true):: { _createNamespace:: create },
  '#withNamespace':: d.fn(
    help='Set the namespace for the app',
    args=[d.arg('ns', d.T.string)],
  ),
  withNamespace(ns):: { _namespace:: ns },
  '#withHeadlessService':: d.fn(
    help='Create a headless Service for a Deployment or StatefulSet, optionally setting its name and publishing not-ready addresses. The name defaults to `<workload>-headless` and supplies StatefulSet serviceName unless overridden.',
    args=[
      d.arg('name', d.T.string, null),
      d.arg('publishNotReadyAddresses', d.T.boolean, true),
    ],
  ),
  withHeadlessService(name=null, publishNotReadyAddresses=true):: {
    _headlessService:: true,
    _headlessServiceName:: if std.isBoolean(name) then null else name,
    _headlessPublishNotReady:: if std.isBoolean(name) then name else publishNotReadyAddresses,
  },
  '#withServiceName':: d.fn(
    help='Override the StatefulSet serviceName, taking precedence over the headless Service name.',
    args=[d.arg('name', d.T.string)],
  ),
  withServiceName(name):: { _serviceName:: name },
  '#withPodManagementPolicy':: d.fn(
    help='Set the pod management policy for the app',
    args=[d.arg('policy', d.T.string)],
  ),
  withPodManagementPolicy(policy):: { _podManagementPolicy:: policy },

  '#withResources':: d.fn(
    help='Set the resource requirements for the app - `{ requests: { cpu, memory }, limits: { cpu, memory } }`',
    args=[d.arg('resources', d.T.object)],
  ),
  withResources(resources):: { _resources:: resources },

  '#withLivenessProbe':: d.fn(
    help="Set the liveness probe for the app - e.g. `{ httpGet: { path: '/healthz', port: 8080 }, initialDelaySeconds: 10, periodSeconds: 30 }`",
    args=[d.arg('probe', d.T.object)],
  ),
  withLivenessProbe(probe):: { _livenessProbe:: probe },
  '#withReadinessProbe':: d.fn(
    help="Set the readiness probe for the app - e.g. `{ httpGet: { path: '/readyz', port: 8080 }, initialDelaySeconds: 10, periodSeconds: 30 }`",
    args=[d.arg('probe', d.T.object)],
  ),
  withReadinessProbe(probe):: { _readinessProbe:: probe },
  '#withStartupProbe':: d.fn(
    help="Set the startup probe for the app - e.g. `{ httpGet: { path: '/startupz', port: 8080 }, initialDelaySeconds: 10, periodSeconds: 30 }`",
    args=[d.arg('probe', d.T.object)],
  ),
  withStartupProbe(probe):: { _startupProbe:: probe },

  // Security context overrides (merged with defaults)
  '#withSecurityContext':: d.fn(
    help='Set the security context for the app - runAsNonRoot, runAsUser, capabilities, etc.',
    args=[d.arg('ctx', d.T.object)],
  ),
  withSecurityContext(ctx):: { _securityContext:: ctx },
  // Pod-level: overrides fsGroup, runAsNonRoot, supplementalGroups, etc.
  '#withPodSecurityContext':: d.fn(
    help='Set pod-level security context overrides. Top-level fields set to null are omitted from the final context, so use values such as { fsGroup: null, fsGroupChangePolicy: null } to remove those defaults. As with other scalar hidden fields, the last withPodSecurityContext() call supplies the overrides.',
    args=[d.arg('ctx', d.T.object)],
  ),
  withPodSecurityContext(ctx):: { _podSecurityContext:: ctx },

  // --- Merge/append accumulators ---

  '#withPort':: d.fn(
    help='Add a container port exposed on the ordinary Service. Routing configs accept `name` to override the resource name while keeping output keys based on port names.',
    args=[d.arg('portEntry', d.T.object)],
  ),
  withPort(portEntry):: addPort(portEntry, false),
  '#withHeadlessPort':: d.fn(
    help='Add a container port exposed on the headless Service. Use withHeadlessService() to enable headless Service generation.',
    args=[d.arg('portEntry', d.T.object)],
  ),
  withHeadlessPort(portEntry):: addPort(portEntry, true),
  '#withPV':: d.fn(
    help=|||
      Convenience wrapper over storage declaration and withVolumeMount, declaring managed storage and mounting it in one call. pvConfig supports name, size, accessModes, storageClassName, readOnly (default false), subPath (default null), and emptyDir. Persistent storage requires StatefulSet. Names default to `<workload>-<mount-path-with-dashes>`; storage defaults are ReadWriteOnce and no explicit storage class. Each mount path may be declared only once across all mount APIs, including identical repeats. Use withVolumeMount at another path to mount its named volume again.
    |||,
    args=[
      d.arg('mountPath', d.T.string),
      d.arg('pvConfig', d.T.object),
    ],
  ),
  withPV(mountPath, pvConfig)::
    assert std.isObject(pvConfig) : 'labsonnet: pvConfig must be an object';
    local emptyDir = std.objectHas(pvConfig, 'emptyDir') && pvConfig.emptyDir;
    local config = {
      [field]: pvConfig[field]
      for field in ['size', 'accessModes', 'storageClassName']
      if std.objectHas(pvConfig, field)
    };
    {
      // Resolve convenience names against the final workload name, as before.
      local volumeName = pvcLib.volumeName(self._name, mountPath, pvConfig),
      local declaration = if emptyDir then declareVolume(k.core.v1.volume.fromEmptyDir(volumeName))
      else $.withClaimTemplate(volumeName, config),
      local mount = $.withVolumeMount(
        mountPath,
        volumeName,
        readOnly=if std.objectHas(pvConfig, 'readOnly') then pvConfig.readOnly else false,
        subPath=if std.objectHas(pvConfig, 'subPath') then pvConfig.subPath else null
      ),
      _claimTemplates+:: if emptyDir then [] else [
        entry { mountPath: mountPath } for entry in declaration._claimTemplates
      ],
      _volumes+:: if emptyDir then declaration._volumes else [],
      _volumeMounts+:: mount._volumeMounts,
      _mountPaths+:: mount._mountPaths,
    },
  '#withClaimTemplate':: d.fn(
    help=|||
      Declare managed StatefulSet storage without mounting it. config accepts size (required), accessModes (default ['ReadWriteOnce']), and storageClassName (default null). The name is the claim-template and volume name and must be a Kubernetes volume name. Repeated equal definitions deduplicate; conflicting definitions fail. Templates declared here render in alphabetical name order; withPV templates retain alphabetical mount-path order. Mount it with withVolumeMount. Declarations and references resolve against the final composed configuration, so their order does not matter.

      ```jsonnet
      labsonnet.new('probe', 'example:1')
      + labsonnet.withType('StatefulSet')
      + labsonnet.withPort({ port: 8080 })
      + labsonnet.withClaimTemplate('state', { size: '2Gi', storageClassName: 'fast' })
      + labsonnet.withVolumeMount('/config', 'state', subPath='config')
      + labsonnet.withVolumeMount('/data', 'state', subPath='data')
      ```
    |||,
    args=[d.arg('name', d.T.string), d.arg('config', d.T.object)],
  ),
  withClaimTemplate(name, config):: { _claimTemplates+:: [{ name: name, config: config }] },
  '#withExistingPVC':: d.fn(
    help=|||
      Declare a volume referencing an existing PVC in the workload namespace, without creating or managing that claim. Works with Deployment and StatefulSet. volumeName must be a Kubernetes volume name; claimName is independent and may be a longer or dotted PVC name. Repeated equal definitions deduplicate; conflicting definitions fail. This API does not add a mount.

      ```jsonnet
      labsonnet.new('reader', 'example:1')
      + labsonnet.withPort({ port: 8080 })
      + labsonnet.withExistingPVC('media', 'shared-media')
      + labsonnet.withVolumeMount('/movies', 'media', readOnly=true, subPath='movies')
      + labsonnet.withVolumeMount('/series', 'media', readOnly=true, subPath='series')
      ```
    |||,
    args=[d.arg('volumeName', d.T.string), d.arg('claimName', d.T.string)],
  ),
  withExistingPVC(volumeName, claimName)::
    declareVolume(k.core.v1.volume.fromPersistentVolumeClaim(volumeName, claimName)),
  '#withVolumeMount':: d.fn(
    help='Mount a declared volume or claim template. References resolve after composition, so declarations can appear before or after mounts. Also accepts volume names supplied by withPV, withEmptyDir, withSecretMount, withConfigMapMount, or withExternalSecretMount. Each mount has independent readOnly and subPath; null subPath omits the field. Different paths accumulate. Each mount path may be declared only once across all mount APIs, including identical repeats. Unknown references and conflicting volume definitions fail.',
    args=[
      d.arg('mountPath', d.T.string),
      d.arg('volumeName', d.T.string),
      d.arg('readOnly', d.T.boolean, false),
      d.arg('subPath', d.T.string, null),
    ],
  ),
  withVolumeMount(mountPath, volumeName, readOnly=false, subPath=null):: {
    _volumeMounts+:: { [mountPath]: { name: volumeName, readOnly: readOnly, subPath: subPath } },
    _mountPaths+:: [mountPath],
  },
  '#withEmptyDir':: d.fn(
    help='Add an emptyDir volume mount to the app. Duplicate mount paths across all mount APIs fail, including identical repeats.',
    args=[d.arg('mountPath', d.T.string)],
  ),
  withEmptyDir(mountPath):: $.withPV(mountPath, { emptyDir: true }),
  '#withConfigMapMount':: d.fn(
    help='Add a configMap volume mount to the app. Duplicate mount paths across all mount APIs fail, including identical repeats.',
    args=[
      d.arg('mountPath', d.T.string),
      d.arg('name', d.T.string),
      d.arg('readOnly', d.T.boolean, true),
    ],
  ),
  withConfigMapMount(mountPath, name, readOnly=true):: {
    _configMapMounts+:: { [mountPath]: { name: name, readOnly: readOnly } },
    _mountPaths+:: [mountPath],
  },
  '#withSecretMount':: d.fn(
    help='Add a secret volume mount to the app. Duplicate mount paths across all mount APIs fail, including identical repeats.',
    args=[
      d.arg('mountPath', d.T.string),
      d.arg('name', d.T.string),
      d.arg('readOnly', d.T.boolean, true),
    ],
  ),
  withSecretMount(mountPath, name, readOnly=true):: {
    _secrets+:: { [mountPath]: { name: name, readOnly: readOnly } },
    _mountPaths+:: [mountPath],
  },
  '#withEnv':: d.fn(
    help='Add environment variables to the app',
    args=[d.arg('env', d.T.object)],
  ),
  withEnv(env):: { _env+:: env },
  '#withFieldRefEnv':: d.fn(
    help='Add environment variable references to the app',
    args=[d.arg('envs', d.T.object)],
  ),
  withFieldRefEnv(envs):: { _fieldRefEnvs+:: envs },
  '#withSecretEnv':: d.fn(
    help='Add environment variables from existing Kubernetes Secrets',
    args=[d.arg('envs', d.T.object)],
  ),
  withSecretEnv(envs):: { _secretEnvs+:: envs },
  '#withExternalSecretEnvs':: d.fn(
    help='Add an external secret with environment variable mappings. cfg = { store: string, storeKind?: string, remoteKey?: string, refreshInterval?: string, refreshPolicy?: string, creationPolicy?: string, deletionPolicy?: string }',
    args=[
      d.arg('name', d.T.string),
      d.arg('envs', d.T.object),
      d.arg('cfg', d.T.object),
    ],
  ),
  withExternalSecretEnvs(name, envs, cfg):: { _externalSecrets+:: { [name]+: cfg { envs: envs } } },
  '#withExternalSecretMount':: d.fn(
    help='Add an external secret mounted as a volume. Duplicate mount paths across all mount APIs fail, including identical repeats; the same secret may be mounted at different paths. cfg = { store: string, storeKind?: string, remoteKey?: string, refreshInterval?: string, refreshPolicy?: string, creationPolicy?: string, deletionPolicy?: string }',
    args=[
      d.arg('name', d.T.string),
      d.arg('mountPath', d.T.string),
      d.arg('cfg', d.T.object),
      d.arg('readOnly', d.T.boolean, default=true),
    ],
  ),
  withExternalSecretMount(name, mountPath, cfg, readOnly=true):: {
    _externalSecrets+:: { [name]+: cfg },
    _externalSecretMounts+:: { [mountPath]: { name: name, mountPath: mountPath, readOnly: readOnly } },
    _mountPaths+:: [mountPath],
  },
  '#withImagePullSecrets':: d.fn(
    help='Add image pull secrets to the app',
    args=[d.arg('secrets', d.T.array)],
  ),
  withImagePullSecrets(secrets):: { _imagePullSecrets+:: secrets },
  '#withNamespaceLabels':: d.fn(
    help='Add namespace labels to the app',
    args=[d.arg('labels', d.T.object)],
  ),
  withNamespaceLabels(labels):: { _namespaceLabels+:: labels },
  '#withNamespaceAnnotations':: d.fn(
    help='Add namespace annotations to the app',
    args=[d.arg('annotations', d.T.object)],
  ),
  withNamespaceAnnotations(annotations):: { _namespaceAnnotations+:: annotations },

  // Pod template labels/annotations (distinct from namespace labels/annotations)
  '#withPodLabels':: d.fn(
    help='Add pod labels to the app',
    args=[d.arg('labels', d.T.object)],
  ),
  withPodLabels(l):: { _podLabels+:: l },
  '#withPodAnnotations':: d.fn(
    help='Add pod annotations to the app',
    args=[d.arg('annotations', d.T.object)],
  ),
  withPodAnnotations(annotations):: { _podAnnotations+:: annotations },

  '#withServiceMonitor':: d.fn(
    help='Add a ServiceMonitor for Prometheus/VictoriaMetrics scraping. portName must match an exposed Service port name after deduplication; name defaults to portName.',
    args=[
      d.arg('portName', d.T.string),
      d.arg('path', d.T.string),
      d.arg('interval', d.T.string),
      d.arg('name', d.T.string),
    ],
  ),
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
