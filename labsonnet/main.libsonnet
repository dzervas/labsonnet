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
local imageVolumeHelper = import 'helpers/imagevolume.libsonnet';

// Combined routing metadata: Gateway API routes + ingress.
// Used for protocol inference, layer classification, and validation.
local routingMeta = gatewayLib.meta + ingressLib.meta;
local routingKeys = std.objectFields(routingMeta);

// Context deliberately excludes accumulators and rendered resources: callbacks
// depend only on final identity, never on the field currently being resolved.
local serviceContext(service) = { name: service._name, namespace: service._namespace };
local resolveObject(value, ctx, helper) =
  local result = if std.isFunction(value) then value(ctx) else value;
  assert std.isObject(result) : 'labsonnet: %s requires an object or a callback returning an object' % helper;
  result;

local declareVolume(v) = { _volumes+:: [v] };


local portRoutingKeys(port) = std.filter(function(rk) std.objectHas(port, rk), routingKeys);

local addPort(portEntry, headless) = {
  local helper = if headless then 'withHeadlessPort' else 'withPort',
  local entry = resolveObject(portEntry, serviceContext(self), helper),
  _ports+::
    assert !std.objectHas(entry, 'service') && !std.objectHas(entry, 'headlessService') :
           'use withPort() or withHeadlessPort() to choose Service exposure';
    [entry { service: !headless, headlessService: headless }],
};

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
          help=|||
            Build Kubernetes workloads for Tanka from container images. Add settings with `+`.

            ## Tanka setup

            In your Tanka project, install the library:

            ```bash
            jb install github.com/dzervas/labsonnet/labsonnet@main
            ```

            Create these one-line import files under `lib/`:

            | File                             | Contents                                                                                 |
            | -------------------------------- | ---------------------------------------------------------------------------------------- |
            | `lib/k.libsonnet`                | `import 'github.com/jsonnet-libs/k8s-libsonnet/1.33/main.libsonnet'`                     |
            | `lib/gateway-api.libsonnet`      | `import 'github.com/jsonnet-libs/gateway-api-libsonnet/1.1-experimental/main.libsonnet'` |
            | `lib/external-secrets.libsonnet` | `import 'github.com/jsonnet-libs/external-secrets-libsonnet/1.0/main.libsonnet'`         |

            Use versions available in your `vendor/` directory. Tanka includes `lib/` and
            `vendor/` in its import paths, so the library can use these short aliases.

            ## Quick start

            Add this to `environments/dashboard/main.jsonnet` in a configured Tanka environment:

            ```jsonnet
            local lab = import 'labsonnet/main.libsonnet';
            {
              dashboard:
                lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
                + lab.withNamespace('apps')
                + lab.withCreateNamespace()
                + lab.withPort({ port: 8080, name: 'http' })
                + lab.withEnv({ TZ: 'Europe/Athens' }),
            }
            ```

            Preview, compare, and apply from the project root:

            ```bash
            tk show environments/dashboard
            tk diff environments/dashboard
            tk apply environments/dashboard
            ```

            Each app groups resources under `workload`, `service`, `headlessService`,
            `namespace`, `routing`, `pvc`, `externalSecrets`, and `monitors`.
            Tanka finds the Kubernetes resources in these nested objects. Unused groups
            may be empty or null. Select `.workload` if you only need the workload resource.

            Defaults: Deployment, one replica, ClusterIP Service, and namespace equal to
            the app name. The namespace is not created unless you call `withCreateNamespace()`.
            At least one port is required. Containers run as UID/GID 1000, without privilege
            escalation, and with all capabilities dropped. Choose an image that supports this
            or set the security context explicitly.

            Examples below use `lab` from the import above. Settings such as replica counts
            use the last value; ports, mounts, containers, and environment entries accumulate. For maps,
            later values replace matching keys.
            Replace example image references with images you use.

            ## Routes, secrets, and storage

            ```jsonnet
            local lab = import 'labsonnet/main.libsonnet';
            {
              photos:
                lab.new('photos', 'ghcr.io/example/photos:1.0')
                + lab.withNamespace('apps')
                + lab.withType('StatefulSet')
                + lab.withPort({
                  port: 8080,
                  name: 'http',
                  httpRoute: {
                    fqdn: 'photos.example.com',
                    gateway: { name: 'edge', namespace: 'network', sectionName: 'https' },
                  },
                })
                + lab.withPV('/data', { size: '10Gi', storageClassName: 'fast' })
                + lab.withExternalSecretEnvs('photos-login', { API_TOKEN: 'token' }, {
                  store: 'password-store', remoteKey: 'photos', refreshPolicy: 'CreatedOnce',
                })
                + lab.withPort({ port: 9090, name: 'metrics' })
                + lab.withServiceMonitor(),
            }
            ```

            The Gateway, storage class, and secret store must already exist. Routes, external
            secrets, and monitors need their matching controllers and CRDs.

            ## Choosing a volume

            | Need                                         | Use                                                                                        |
            | -------------------------------------------- | ------------------------------------------------------------------------------------------ |
            | New persistent storage for a StatefulSet     | [`withPV`](#fn-withpv)                                                                     |
            | One StatefulSet PVC mounted at several paths | [`withClaimTemplate`](#fn-withclaimtemplate) + [`withVolumeMount`](#fn-withvolumemount)    |
            | An existing PVC                              | [`withExistingPVC`](#fn-withexistingpvc) + [`withVolumeMount`](#fn-withvolumemount)        |
            | Temporary files                              | [`withEmptyDir`](#fn-withemptydir)                                                         |
            | An existing ConfigMap or Secret              | [`withConfigMapMount`](#fn-withconfigmapmount) or [`withSecretMount`](#fn-withsecretmount) |
            | Files from an OCI image                      | [`withImageVolume`](#fn-withimagevolume) + [`withVolumeMount`](#fn-withvolumemount)        |
            | Files from a secret store                    | [`withExternalSecretMount`](#fn-withexternalsecretmount)                                   |

            A volume provides storage; a mount chooses where it appears in the container.
            Each mount path must be unique. A volume can have multiple mounts. Repeating
            a volume definition is allowed only when the definitions match.

            ## Reusable defaults

            See [downstream helpers and overrides](downstream.md) for re-exporting
            helpers, setting local defaults, and adding checks after composition.

            Wrap the library to share placement or monitoring settings between apps:

            ```jsonnet
            local lab = import 'labsonnet/main.libsonnet';
            local affinity = import 'labsonnet/helpers/affinity.libsonnet';
            local site = lab {
              new(name, image)::
                super.new(name, image)
                + lab.withAffinity(affinity.requireNodeLabel('pool', ['apps'])),
              withMetrics(port=9090)::
                lab.withPort({ port: port, name: 'metrics' }) + lab.withServiceMonitor(),
            };
            {
              dashboard:
                site.new('dashboard', 'ghcr.io/example/dashboard:1.0')
                + site.withPort({ port: 8080 })
                + site.withMetrics(),
            }
            ```

            ## Lazy configuration callbacks

            Use a callback when a setting needs the final app name or namespace:

            ```jsonnet
            local lab = import 'labsonnet/main.libsonnet';
            {
              worker:
                lab.new('worker', 'ghcr.io/example/worker:1.0')
                + lab.withPort({ port: 8080 })
                + lab.withEnv(function(ctx) { APP_NAME: ctx.name, APP_NAMESPACE: ctx.namespace })
                + lab.withNamespace('apps'),
            }
            ```

            `ctx` contains only `name` and `namespace`. The namespace defaults to the app
            name; callbacks see later `withNamespace` calls too. `withServiceName` does not
            change `ctx.name`.

            Supported by `withPort`, `withHeadlessPort`, `withEnv`, `withFieldRefEnv`,
            `withSecretEnv`, `withPV`'s `pvConfig`, and `withClaimTemplate`'s `config`.
            Return an object with the normal helper fields. Nested callbacks are not
            resolved. Keep callbacks pure and use `ctx` or captured values; reading the app
            being built can cause a cycle.
          |||,
          filename=std.thisFile,
          version='main'
        ) + d.package.withInstallTemplate('jb install github.com/dzervas/labsonnet/labsonnet@main')
        + d.package.withUsageTemplate("local labsonnet = import 'labsonnet/main.libsonnet'"),

  '#new':: d.fn(
    help=|||
      Create an app. Add at least one port before rendering. The name also sets the default namespace and Service name.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 }),
      }
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
        std.member([p.name for p in servicePorts], mon.portName),
      std.objectFields(me._serviceMonitors)
    )) : "labsonnet '%s': each serviceMonitor must reference a port exposed by the ordinary Service" % me._name,

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
    help=|||
      Set the default hostname for HTTP, gRPC, and Ingress routes. A route can override it with its own `fqdn`.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withFqdn('dashboard.example.com'),
      }
      ```
    |||,
    args=[d.arg('fqdn', d.T.string)],
  ),
  withFqdn(fqdn):: { _fqdn:: fqdn },
  '#withType':: d.fn(
    help=|||
      Choose `Deployment` (default) or `StatefulSet`. Managed persistent storage requires a StatefulSet.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withType('StatefulSet'),
      }
      ```
    |||,
    args=[d.arg('type', d.T.string)],
  ),
  withType(type):: { _type:: type },
  '#withReplicas':: d.fn(
    help=|||
      Set the replica count, a non-negative integer. The default is 1.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withReplicas(2),
      }
      ```
    |||,
    args=[d.arg('replicas', d.T.number)],
  ),
  withReplicas(n):: { _replicas:: n },
  '#withCommand':: d.fn(
    help=|||
      Set the container entrypoint as an array of strings.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withCommand(['/app/server']),
      }
      ```
    |||,
    args=[d.arg('command', d.T.array)],
  ),
  withCommand(cmd):: { _command:: cmd },
  '#withArgs':: d.fn(
    help=|||
      Set arguments passed to the container entrypoint.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withArgs(['--listen', ':8080']),
      }
      ```
    |||,
    args=[d.arg('args', d.T.array)],
  ),
  withArgs(args):: { _args:: args },
  '#withContainer':: d.fn(
    help=|||
      Add a sidecar container using a Kubernetes container object. It inherits the main container's environment, mounts, and security settings.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withContainer({ name: 'worker', image: 'ghcr.io/example/worker:1.0' }),
      }
      ```
    |||,
    args=[d.arg('container', d.T.object)],
  ),
  withContainer(container):: { _containers+:: [container] },
  '#withInitContainer':: d.fn(
    help=|||
      Add a container that runs before the app starts. It inherits the main container's environment, mounts, and security settings.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withInitContainer({ name: 'prepare', image: 'busybox:1.37', command: ['sh', '-c', 'echo ready'] }),
      }
      ```
    |||,
    args=[d.arg('container', d.T.object)],
  ),
  withInitContainer(container):: { _initContainers+:: [container] },
  '#withRunAsUser':: d.fn(
    help=|||
      Set the container UID and GID, plus the default pod `fsGroup`. The default is 1000.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withRunAsUser(65532),
      }
      ```
    |||,
    args=[d.arg('uid', d.T.number)],
  ),
  withRunAsUser(uid):: { _runAsUser:: uid },
  '#withAffinity':: d.fn(
    help=|||
      Set pod placement rules. Use the affinity helper to build them; pass `null` or `{}` to remove placement rules.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withAffinity((import 'labsonnet/helpers/affinity.libsonnet').requireNodeLabel('pool', ['apps'])),
      }
      ```
    |||,
    args=[d.arg('affinity', 'object | null')],
  ),
  withAffinity(aff):: { _affinity:: aff },
  '#withServiceType':: d.fn(
    help=|||
      Set the ordinary Service type. The default is `ClusterIP`; use `LoadBalancer` for direct network access.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withServiceType('LoadBalancer'),
      }
      ```
    |||,
    args=[d.arg('type', d.T.string)],
  ),
  withServiceType(t):: { _serviceType:: t },
  '#withCreateNamespace':: d.fn(
    help=|||
      Create the app namespace when true. Namespace creation is disabled by default.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withCreateNamespace(),
      }
      ```
    |||,
    args=[d.arg('create', d.T.boolean, true)],
  ),
  withCreateNamespace(create=true):: { _createNamespace:: create },
  '#withNamespace':: d.fn(
    help=|||
      Set the namespace for the app and its namespaced resources. The default is the app name.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withNamespace('apps'),
      }
      ```
    |||,
    args=[d.arg('ns', d.T.string)],
  ),
  withNamespace(ns):: { _namespace:: ns },
  '#withHeadlessService':: d.fn(
    help=|||
      Create a headless Service for peer discovery. Its name defaults to `<app>-headless`; it also supplies the StatefulSet `serviceName`. Not-ready addresses are published by default. Add ports with `withHeadlessPort`.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withType('StatefulSet')
          + lab.withHeadlessService(publishNotReadyAddresses=false)
          + lab.withHeadlessPort({ port: 7000, name: 'peer' }),
      }
      ```
    |||,
    args=[
      d.argument.fromSchema('name', { type: ['string', 'null'], default: null }),
      d.arg('publishNotReadyAddresses', d.T.boolean, true),
    ],
  ),
  withHeadlessService(name=null, publishNotReadyAddresses=true):: {
    _headlessService:: true,
    _headlessServiceName:: if std.isBoolean(name) then null else name,
    _headlessPublishNotReady:: if std.isBoolean(name) then name else publishNotReadyAddresses,
  },
  '#withServiceName':: d.fn(
    help=|||
      Set the StatefulSet `serviceName`. This overrides the generated headless Service reference; it does not rename the ordinary Service or create another Service.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withType('StatefulSet')
          + lab.withServiceName('existing-peers'),
      }
      ```
    |||,
    args=[d.arg('name', d.T.string)],
  ),
  withServiceName(name):: { _serviceName:: name },
  '#withPodManagementPolicy':: d.fn(
    help=|||
      Set the StatefulSet pod management policy to `OrderedReady` or `Parallel`.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withType('StatefulSet')
          + lab.withPodManagementPolicy('Parallel'),
      }
      ```
    |||,
    args=[d.arg('policy', d.T.string)],
  ),
  withPodManagementPolicy(policy):: { _podManagementPolicy:: policy },

  '#withResources':: d.fn(
    help=|||
      Set CPU and memory requests and limits using a Kubernetes resources object.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withResources({ requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '512Mi' } }),
      }
      ```
    |||,
    args=[d.arg('resources', d.T.object)],
  ),
  withResources(resources):: { _resources:: resources },

  '#withLivenessProbe':: d.fn(
    help=|||
      Set a probe that restarts an unhealthy container.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withLivenessProbe({ httpGet: { path: '/healthz', port: 8080 }, periodSeconds: 30 }),
      }
      ```
    |||,
    args=[d.arg('probe', d.T.object)],
  ),
  withLivenessProbe(probe):: { _livenessProbe:: probe },
  '#withReadinessProbe':: d.fn(
    help=|||
      Set a probe that controls when the pod receives Service traffic.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withReadinessProbe({ httpGet: { path: '/readyz', port: 8080 } }),
      }
      ```
    |||,
    args=[d.arg('probe', d.T.object)],
  ),
  withReadinessProbe(probe):: { _readinessProbe:: probe },
  '#withStartupProbe':: d.fn(
    help=|||
      Set a probe that allows slow startup before liveness and readiness checks begin.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withStartupProbe({ httpGet: { path: '/healthz', port: 8080 }, failureThreshold: 30, periodSeconds: 10 }),
      }
      ```
    |||,
    args=[d.arg('probe', d.T.object)],
  ),
  withStartupProbe(probe):: { _startupProbe:: probe },

  // Security context overrides (merged with defaults)
  '#withSecurityContext':: d.fn(
    help=|||
      Override container security defaults. Each call replaces the previous override object.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withSecurityContext({ readOnlyRootFilesystem: true }),
      }
      ```
    |||,
    args=[d.arg('ctx', d.T.object)],
  ),
  withSecurityContext(ctx):: { _securityContext:: ctx },
  // Pod-level: overrides fsGroup, runAsNonRoot, supplementalGroups, etc.
  '#withPodSecurityContext':: d.fn(
    help=|||
      Override pod security defaults. Top-level null values remove fields. Each call replaces the previous override object.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withPodSecurityContext({ fsGroup: null, fsGroupChangePolicy: null }),
      }
      ```
    |||,
    args=[d.arg('ctx', d.T.object)],
  ),
  withPodSecurityContext(ctx):: { _podSecurityContext:: ctx },

  // --- Merge/append accumulators ---

  '#withPort':: d.fn(
    help=|||
      Expose a container port through the app's Service.

      | Field      | Meaning                                                                          |
      | ---------- | -------------------------------------------------------------------------------- |
      | `port`     | Required port number.                                                            |
      | `name`     | Optional Service port name; defaults to `<protocol>-<port>`, such as `tcp-8080`. |
      | `protocol` | Defaults to `TCP`; use `UDP` for a UDP port.                                     |

      For a route, add one of `httpRoute`, `grpcRoute`, `tcpRoute`, `udpRoute`, or
      `ingress`. HTTP, gRPC, and Ingress need a hostname (`fqdn` in the route or
      `withFqdn`). Routes select TCP, except `udpRoute`, which selects UDP.

      See the [routing example](#routes-secrets-and-storage) and the
      [Gateway](helpers/gateway.md) or [Ingress](helpers/ingress.md) options.
      `name` inside a route config overrides the resource name.

      Repeated number/protocol pairs keep the first Service port. Use different
      port names to attach several routes to one port. Accepts an object or callback.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080, name: 'http' }),
      }
      ```
    |||,
    args=[d.arg('portEntry', 'object | function(ctx) object')],
  ),
  withPort(portEntry):: addPort(portEntry, false),
  '#withHeadlessPort':: d.fn(
    help=|||
      Expose a port through the headless Service for peer discovery. Enable it
      with `withHeadlessService()`. Uses the same fields as `withPort` and accepts
      an object or callback.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withHeadlessService()
          + lab.withHeadlessPort({ port: 7000, name: 'peer' }),
      }
      ```
    |||,
    args=[d.arg('portEntry', 'object | function(ctx) object')],
  ),
  withHeadlessPort(portEntry):: addPort(portEntry, true),
  '#withPV':: d.fn(
    help=|||
      Create a PVC and mount it in one call. Requires a StatefulSet and `size`.

      Set `storageClassName` to choose a storage class; otherwise Kubernetes uses
      its default. Optional fields: `name`, `accessModes` (default
      `['ReadWriteOnce']`), `readOnly`, and `subPath` (see `withVolumeMount`).
      Accepts an object or callback.

      For another mount of this volume, give it a `name` and use `withVolumeMount`.
      For temporary storage, use `withEmptyDir` (or `emptyDir: true`).

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withType('StatefulSet')
          + lab.withPV('/data', { name: 'data', size: '10Gi', storageClassName: 'fast' }),
      }
      ```
    |||,
    args=[
      d.arg('mountPath', d.T.string),
      d.arg('pvConfig', 'object | function(ctx) object'),
    ],
  ),
  withPV(mountPath, pvConfig):: {
    local pv = resolveObject(pvConfig, serviceContext(self), 'withPV'),
    local emptyDir = std.objectHas(pv, 'emptyDir') && pv.emptyDir,
    local config = {
      [field]: pv[field]
      for field in ['size', 'accessModes', 'storageClassName']
      if std.objectHas(pv, field)
    },
    // Resolve convenience names against the final workload name, as before.
    local volumeName = pvcLib.volumeName(self._name, mountPath, pv),
    local declaration = if emptyDir then declareVolume(k.core.v1.volume.fromEmptyDir(volumeName))
    else $.withClaimTemplate(volumeName, config),
    local mount = $.withVolumeMount(
      mountPath,
      volumeName,
      readOnly=if std.objectHas(pv, 'readOnly') then pv.readOnly else false,
      subPath=if std.objectHas(pv, 'subPath') then pv.subPath else null
    ),
    _claimTemplates+:: if emptyDir then [] else [
      entry { mountPath: mountPath }
      for entry in declaration._claimTemplates
    ],
    _volumes+:: if emptyDir then declaration._volumes else [],
    _volumeMounts+:: mount._volumeMounts,
    _mountPaths+:: mount._mountPaths,
  },
  '#withClaimTemplate':: d.fn(
    help=|||
      Create a StatefulSet PVC by volume name, then mount it separately.
      Use this when one PVC needs several mounts. `config` accepts `size`
      (required), `accessModes`, and `storageClassName`, as in `withPV`.
      Accepts an object or callback.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withType('StatefulSet')
          + lab.withClaimTemplate('data', { size: '10Gi', storageClassName: 'fast' })
          + lab.withVolumeMount('/config', 'data', subPath='config')
          + lab.withVolumeMount('/data', 'data', subPath='data'),
      }
      ```
    |||,
    args=[d.arg('name', d.T.string), d.arg('config', 'object | function(ctx) object')],
  ),
  withClaimTemplate(name, config):: {
    local resolved = resolveObject(config, serviceContext(self), 'withClaimTemplate'),
    _claimTemplates+:: [{ name: name, config: resolved }],
  },
  '#withExistingPVC':: d.fn(
    help=|||
      Use a PVC that already exists in the app namespace. `volumeName` names
      the volume in the pod; `claimName` identifies the existing PVC. Add mounts
      with `withVolumeMount`. Works with Deployment and StatefulSet.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withExistingPVC('media', 'shared-media')
          + lab.withVolumeMount('/movies', 'media', readOnly=true, subPath='movies'),
      }
      ```
    |||,
    args=[d.arg('volumeName', d.T.string), d.arg('claimName', d.T.string)],
  ),
  withExistingPVC(volumeName, claimName)::
    declareVolume(k.core.v1.volume.fromPersistentVolumeClaim(volumeName, claimName)),
  '#withImageVolume':: d.fn(
    help=|||
      Use files from an OCI image. Add a mount with `readOnly=true`.
      Requires cluster support for image volumes. Optional `pullPolicy`:
      `Always`, `IfNotPresent`, or `Never`; null leaves it to Kubernetes.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withImageVolume('assets', 'ghcr.io/example/assets:1.0')
          + lab.withVolumeMount('/assets', 'assets', readOnly=true),
      }
      ```
    |||,
    args=[
      d.arg('name', d.T.string),
      d.arg('image', d.T.string),
      d.argument.fromSchema('pullPolicy', { type: ['string', 'null'], default: null }),
    ],
  ),
  withImageVolume(name, image, pullPolicy=null)::
    declareVolume(imageVolumeHelper.new(name, image, pullPolicy)),
  '#withVolumeMount':: d.fn(
    help=|||
      Mount a volume created by another helper. `volumeName` must match the
      declared volume or claim template; declaration order does not matter.

      `readOnly` defaults to false. `subPath` selects a file or folder inside the volume;
      null mounts the whole volume. Image volumes require `readOnly=true`.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withExistingPVC('media', 'shared-media')
          + lab.withVolumeMount('/movies', 'media', readOnly=true, subPath='movies')
          + lab.withVolumeMount('/series', 'media', readOnly=true, subPath='series'),
      }
      ```
    |||,
    args=[
      d.arg('mountPath', d.T.string),
      d.arg('volumeName', d.T.string),
      d.arg('readOnly', d.T.boolean, false),
      d.argument.fromSchema('subPath', { type: ['string', 'null'], default: null }),
    ],
  ),
  withVolumeMount(mountPath, volumeName, readOnly=false, subPath=null):: {
    _volumeMounts+:: { [mountPath]: { name: volumeName, readOnly: readOnly, subPath: subPath } },
    _mountPaths+:: [mountPath],
  },
  '#withEmptyDir':: d.fn(
    help=|||
      Mount temporary storage. Data lasts only for the lifetime of the pod.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withEmptyDir('/tmp'),
      }
      ```
    |||,
    args=[d.arg('mountPath', d.T.string)],
  ),
  withEmptyDir(mountPath):: $.withPV(mountPath, { emptyDir: true }),
  '#withConfigMapMount':: d.fn(
    help=|||
      Mount an existing ConfigMap from the app namespace. Read-only by default.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withConfigMapMount('/etc/app', 'dashboard-config'),
      }
      ```
    |||,
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
    help=|||
      Mount an existing Kubernetes Secret from the app namespace. Read-only by default.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withSecretMount('/run/credentials', 'dashboard-login'),
      }
      ```
    |||,
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
    help=|||
      Add plain environment variables as a map. Accepts an object or callback.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withEnv({ TZ: 'Europe/Athens', LOG_LEVEL: 'info' }),
      }
      ```
    |||,
    args=[d.arg('env', 'object | function(ctx) object')],
  ),
  withEnv(env):: { _env+:: resolveObject(env, serviceContext(self), 'withEnv') },
  '#withFieldRefEnv':: d.fn(
    help=|||
      Add environment variables from pod fields using the downward API. Map variable names to field paths. Accepts an object or callback.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withFieldRefEnv({ POD_NAME: 'metadata.name', POD_NAMESPACE: 'metadata.namespace' }),
      }
      ```
    |||,
    args=[d.arg('envs', 'object | function(ctx) object')],
  ),
  withFieldRefEnv(envs):: { _fieldRefEnvs+:: resolveObject(envs, serviceContext(self), 'withFieldRefEnv') },
  '#withSecretEnv':: d.fn(
    help=|||
      Read environment variables from existing Kubernetes Secrets in the app namespace. Map variables to `{ name: secretName, key: secretKey }`. Accepts an object or callback.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withSecretEnv({ API_TOKEN: { name: 'dashboard-login', key: 'token' } }),
      }
      ```
    |||,
    args=[d.arg('envs', 'object | function(ctx) object')],
  ),
  withSecretEnv(envs):: { _secretEnvs+:: resolveObject(envs, serviceContext(self), 'withSecretEnv') },
  '#withExternalSecretEnvs':: d.fn(
    help=|||
      Create an ExternalSecret and read its keys as environment variables. Map variable names to keys in the extracted remote object. `cfg.store` is required; `storeKind` defaults to `ClusterSecretStore` and `remoteKey` to the secret name.

      Optional fields: `refreshInterval`, `refreshPolicy`, `creationPolicy`, `deletionPolicy`. Omitted policy fields use controller defaults. Requires External Secrets Operator and an existing store.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withExternalSecretEnvs('dashboard-login', { API_TOKEN: 'token' }, {
            store: 'password-store', remoteKey: 'dashboard', refreshPolicy: 'CreatedOnce',
          }),
      }
      ```
    |||,
    args=[
      d.arg('name', d.T.string),
      d.arg('envs', d.T.object),
      d.arg('cfg', d.T.object),
    ],
  ),
  withExternalSecretEnvs(name, envs, cfg):: { _externalSecrets+:: { [name]+: cfg { envs: envs } } },
  '#withExternalSecretMount':: d.fn(
    help=|||
      Create an ExternalSecret and mount the resulting Secret read-only by default. Uses the same `cfg` fields as `withExternalSecretEnvs`. Extracts the whole remote object. A secret can be mounted at multiple distinct paths.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withExternalSecretMount('dashboard-login', '/run/credentials', { store: 'password-store', remoteKey: 'dashboard' }),
      }
      ```
    |||,
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
    help=|||
      Add names of existing image pull Secrets in the app namespace.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withImagePullSecrets(['registry-login']),
      }
      ```
    |||,
    args=[d.arg('secrets', d.T.array)],
  ),
  withImagePullSecrets(secrets):: { _imagePullSecrets+:: secrets },
  '#withNamespaceLabels':: d.fn(
    help=|||
      Add namespace labels. Call `withCreateNamespace()` to emit the Namespace resource.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withCreateNamespace()
          + lab.withNamespaceLabels({ 'pod-security.kubernetes.io/enforce': 'restricted' }),
      }
      ```
    |||,
    args=[d.arg('labels', d.T.object)],
  ),
  withNamespaceLabels(labels):: { _namespaceLabels+:: labels },
  '#withNamespaceAnnotations':: d.fn(
    help=|||
      Add namespace annotations. Call `withCreateNamespace()` to emit the Namespace resource.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withCreateNamespace()
          + lab.withNamespaceAnnotations({ owner: 'platform' }),
      }
      ```
    |||,
    args=[d.arg('annotations', d.T.object)],
  ),
  withNamespaceAnnotations(annotations):: { _namespaceAnnotations+:: annotations },

  // Pod template labels/annotations (distinct from namespace labels/annotations)
  '#withPodLabels':: d.fn(
    help=|||
      Add pod labels. Labels used by the workload selector cannot be changed.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withPodLabels({ component: 'dashboard' }),
      }
      ```
    |||,
    args=[d.arg('labels', d.T.object)],
  ),
  withPodLabels(l):: { _podLabels+:: l },
  '#withPodAnnotations':: d.fn(
    help=|||
      Add annotations to the pod template.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withPodAnnotations({ 'reloader.stakater.com/auto': 'true' }),
      }
      ```
    |||,
    args=[d.arg('annotations', d.T.object)],
  ),
  withPodAnnotations(annotations):: { _podAnnotations+:: annotations },

  '#withServiceMonitor':: d.fn(
    help=|||
      Create a ServiceMonitor for an ordinary Service port. `portName` must match the final Service port name. Defaults: `metrics`, `/metrics`, `30s`, and a monitor name matching `portName`. Requires a monitoring operator and the ServiceMonitor CRD.

      ```jsonnet
      {
        dashboard:
          lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
          + lab.withPort({ port: 8080 })
          + lab.withPort({ port: 9090, name: 'metrics' })
          + lab.withServiceMonitor(),
      }
      ```
    |||,
    args=[
      d.arg('portName', d.T.string, 'metrics'),
      d.arg('path', d.T.string, '/metrics'),
      d.arg('interval', d.T.string, '30s'),
      d.argument.fromSchema('name', { type: ['string', 'null'], default: null }),
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
