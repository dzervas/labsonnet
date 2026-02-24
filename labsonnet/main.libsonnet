// labsonnet — Compositional Kubernetes service builder using + operator.
// Build workload + service + routes + pvcs + external secrets with with*() functions.

local d = import 'github.com/jsonnet-libs/docsonnet/doc-util/main.libsonnet';
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
    _initContainers:: [],
    _runAsUser:: 1000,
    _serviceType:: 'ClusterIP',
    _headlessService:: false,
    _headlessPublishNotReady:: true,
    _serviceName:: null,
    _podManagementPolicy:: null,
    _fieldRefEnvs:: {},
    _secretEnvs:: {},
    _ports:: [],
    _pvs:: {},
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
    local routedPorts = std.filter(function(pp) pp.routingKey != null, processedPorts),

    assert std.length(portNames) == std.length(std.set(portNames)) :
           "labsonnet '%s': duplicate port name in ports" % me._name,
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

    // Kubernetes Secrets
    assert std.all(std.map(
      function(mountPath) std.isObject(me._secrets[mountPath]) && std.objectHas(me._secrets[mountPath], 'name'),
      std.objectFields(me._secrets)
    )) : "labsonnet '%s': each secrets entry must be an object with a 'name' field" % me._name,

    // ExternalSecrets
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
    ) + std.map(
      function(envName)
        local ref = me._secretEnvs[envName];
        { name: envName, secret: ref.name, key: ref.key },
      std.objectFields(me._secretEnvs)
    ),
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

    // Persistent Volumes
    local hasRealPvs = std.length(std.filter(
      function(mountPath) !(std.objectHas(me._pvs[mountPath], 'emptyDir') && me._pvs[mountPath].emptyDir),
      std.objectFields(me._pvs)
    )) > 0,
    assert std.all(std.map(
      function(mountPath)
        local pv = me._pvs[mountPath];
        (std.objectHas(pv, 'emptyDir') && pv.emptyDir) || std.objectHas(pv, 'size'),
      std.objectFields(me._pvs)
    )) : "labsonnet '%s': all pvs entries must have a 'size' field (unless 'emptyDir' is true)" % me._name,

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
      initContainers: me._initContainers,
      runAsUser: me._runAsUser,
      serviceType: me._serviceType,
      headlessPublishNotReady: me._headlessPublishNotReady,
      serviceName: effectiveServiceName,
      podManagementPolicy: me._podManagementPolicy,
      fieldRefEnvs: me._fieldRefEnvs,
      ports: uniquePorts,
      pvs: me._pvs,
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
    help='Set the number of replicas for the app',
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
  '#withInitContainer':: d.fn(
    help='Add an init container to the app',
    args=[d.arg('container', d.T.object)],
  ),
  withInitContainer(container):: { _initContainers+:: [container] },
  '#withRunAsUser':: d.fn(
    help='Set the UID & GID for the app',
    args=[d.arg('uid', d.T.number)],
  ),
  withRunAsUser(uid):: { _runAsUser:: uid },
  '#withAffinity':: d.fn(
    help='Set the affinity for the app - for more affinities check helpers/affinity.libsonnet',
    args=[d.arg('affinity', d.T.object)],
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
    help='Set whether to create a headless service',
    args=[d.arg('headless', d.T.boolean, true)],
  ),
  withHeadlessService(publishNotReadyAddresses=true):: {
    _headlessService:: true,
    _headlessPublishNotReady:: publishNotReadyAddresses,
  },
  '#withServiceName':: d.fn(
    help='Set the name for the new kubernetes service',
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
    help='Set the pod-level security context overrides',
    args=[d.arg('ctx', d.T.object)],
  ),
  withPodSecurityContext(ctx):: { _podSecurityContext:: ctx },

  // --- Merge/append accumulators ---

  '#withPort':: d.fn(
    help='Add a port to the app',
    args=[d.arg('portEntry', d.T.object)],
  ),
  withPort(portEntry):: { _ports+:: [portEntry] },
  '#withPV':: d.fn(
    help='Add a persistent volume mount to the app',
    args=[
      d.arg('mountPath', d.T.string),
      d.arg('pvConfig', d.T.object),
    ],
  ),
  withPV(mountPath, pvConfig):: { _pvs+:: { [mountPath]: pvConfig } },
  '#withEmptyDir':: d.fn(
    help='Add an emptyDir volume mount to the app',
    args=[d.arg('mountPath', d.T.string)],
  ),
  withEmptyDir(mountPath):: { _pvs+:: { [mountPath]: { emptyDir: true } } },
  '#withConfigMapMount':: d.fn(
    help='Add a configMap volume mount to the app',
    args=[
      d.arg('mountPath', d.T.string),
      d.arg('name', d.T.string),
      d.arg('readOnly', d.T.boolean, true),
    ],
  ),
  withConfigMapMount(mountPath, name, readOnly=true):: {
    _configMapMounts+:: { [mountPath]: { name: name, readOnly: readOnly } },
  },
  '#withSecretMount':: d.fn(
    help='Add a secret volume mount to the app',
    args=[
      d.arg('mountPath', d.T.string),
      d.arg('name', d.T.string),
      d.arg('readOnly', d.T.boolean, true),
    ],
  ),
  withSecretMount(mountPath, name, readOnly=true):: {
    _secrets+:: { [mountPath]: { name: name, readOnly: readOnly } },
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
  '#withExternalSecret':: d.fn(
    help='Add an external secret to the app',
    args=[
      d.arg('suffix', d.T.string),
      d.arg('cfg', d.T.object),
    ],
  ),
  withExternalSecret(suffix, cfg):: { _externalSecrets+:: { [suffix]: cfg } },
  '#withExternalSecretMount':: d.fn(
    help='Add an external secret mount to the app',
    args=[
      d.arg('suffix', d.T.string),
      d.arg('mountPath', d.T.string),
      d.arg('readOnly', d.T.boolean, default=true),
    ],
  ),
  withExternalSecretMount(suffix, mountPath, readOnly=true):: {
    _externalSecretMounts+:: { [suffix]: { mountPath: mountPath, readOnly: readOnly } },
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
    help=|||
      Add ServiceMonitor for Prometheus/VictoriaMetrics scraping.
      portName must match a port name from withPort(). name defaults to portName.
    |||,
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
