// Generic CloudNativePG builders using labsonnet's resource helpers.
local externalSecret = import './externalsecret.libsonnet';
local imageVolume = import './imagevolume.libsonnet';

local mergeObjects(base, overrides) =
  if std.isObject(base) && std.isObject(overrides) then
    std.foldl(
      function(result, key)
        result {
          [key]:
            if std.objectHas(result, key)
               && std.isObject(result[key])
               && std.isObject(overrides[key])
            then mergeObjects(result[key], overrides[key])
            else overrides[key],
        },
      std.objectFields(overrides),
      base
    )
  else overrides;

local nonEmptyString(value) = std.isString(value) && std.length(value) > 0;
local validDnsLabel(value) =
  nonEmptyString(value)
  && std.length(value) <= 63
  && std.member(std.stringChars('abcdefghijklmnopqrstuvwxyz0123456789'), value[0])
  && std.member(std.stringChars('abcdefghijklmnopqrstuvwxyz0123456789'), value[std.length(value) - 1])
  && std.all([
    std.member(std.stringChars('abcdefghijklmnopqrstuvwxyz0123456789-'), char)
    for char in std.stringChars(value)
  ]);
local validDnsSubdomain(value) =
  nonEmptyString(value)
  && std.length(value) <= 253
  && std.all([validDnsLabel(label) for label in std.split(value, '.')]);
local validExtensionName(value) =
  nonEmptyString(value)
  && std.length(value) <= 59
  // Reuse validDnsLabel after replacing underscores with dashes
  && validDnsLabel(std.strReplace(value, '_', '-'));
local unique(items) = std.foldl(
  function(result, item) if std.member(result, item) then result else result + [item],
  items,
  []
);
local sqlName(value) = nonEmptyString(value) && std.length(std.encodeUTF8(value)) <= 63;
local tenantConnectionName(value) =
  nonEmptyString(value)
  && std.length(value) <= 63
  && std.all([
    std.member(std.stringChars('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._~-'), char)
    for char in std.stringChars(value)
  ]);

// Add the CNPG credential target to the shared ExternalSecret builder.
local credentialsSecret(name, namespace, storeName, storeKind, targetTemplate, data, dataFrom, refreshPolicy, refreshInterval) =
  externalSecret.new(
    name,
    namespace,
    storeName,
    storeKind=storeKind,
    data=if data == null then [] else data,
    dataFrom=if dataFrom == null then [] else dataFrom,
    refreshPolicy=refreshPolicy,
    refreshInterval=refreshInterval,
    creationPolicy='Owner'
  ) + { spec+: { target+: { name: name, template: targetTemplate } } };

local appSecretData(roleName, databaseName, host) = {
  user: roleName,
  username: roleName,
  password: '{{ .password }}',
  database: databaseName,
  dbname: databaseName,
  host: host,
  port: '5432',
  // Tenant names are restricted to URI-unreserved ASCII characters.
  // urlquery encodes reserved password characters; replace converts its space
  // encoding from '+' to the URI-safe '%20'.
  uri: 'postgresql://' + roleName + ':{{ .password | urlquery | replace "+" "%20" }}@' + host + ':5432/' + databaseName,
};

local roleSecretTemplate(roleName, databaseName, host, includeAppCredentials) = {
  engineVersion: 'v2',
  type: 'kubernetes.io/basic-auth',
  metadata: {
    labels: { 'cnpg.io/reload': 'true' },
  },
  data:
    if includeAppCredentials then appSecretData(roleName, databaseName, host)
    else { user: roleName, username: roleName, password: '{{ .password }}' },
};

local appSecretTemplate(roleName, databaseName, host) = {
  engineVersion: 'v2',
  data: appSecretData(roleName, databaseName, host),
};

local validReclaimPolicy(policy) =
  policy == null || std.member(['retain', 'delete'], policy);

local databaseResource(resourceName, databaseName, clusterName, ownerName, namespace, reclaimPolicy, spec) =
  assert validDnsSubdomain(resourceName) : 'labsonnet CNPG: Database resource name must be a valid DNS subdomain';
  assert sqlName(databaseName) : 'labsonnet CNPG: database name must be a non-empty string up to 63 characters';
  assert validDnsLabel(clusterName) : 'labsonnet CNPG: cluster name must be a valid DNS label';
  assert sqlName(ownerName) : 'labsonnet CNPG: database owner must be a non-empty string up to 63 characters';
  assert validDnsLabel(namespace) : 'labsonnet CNPG: namespace must be a valid DNS label';
  assert validReclaimPolicy(reclaimPolicy) : 'labsonnet CNPG: Database reclaimPolicy must be retain, delete, or null';
  assert std.isObject(spec) : 'labsonnet CNPG: Database spec override must be an object';
  {
    apiVersion: 'postgresql.cnpg.io/v1',
    kind: 'Database',
    metadata: { name: resourceName, namespace: namespace },
    spec: mergeObjects(
      {
        name: databaseName,
        owner: ownerName,
        cluster: { name: clusterName },
      } + (if reclaimPolicy != null then { databaseReclaimPolicy: reclaimPolicy } else {}),
      spec
    ),
  };

local roleResource(resourceName, clusterName, secretName, namespace, roleName, reclaimPolicy, spec) =
  assert validDnsSubdomain(resourceName) : 'labsonnet CNPG: DatabaseRole resource name must be a valid DNS subdomain';
  assert validDnsLabel(clusterName) : 'labsonnet CNPG: cluster name must be a valid DNS label';
  assert validDnsLabel(namespace) : 'labsonnet CNPG: namespace must be a valid DNS label';
  assert validDnsSubdomain(secretName) : 'labsonnet CNPG: DatabaseRole secretName must be a valid DNS subdomain';
  assert sqlName(roleName) : 'labsonnet CNPG: role name must be a non-empty string up to 63 characters';
  assert validReclaimPolicy(reclaimPolicy) : 'labsonnet CNPG: DatabaseRole reclaimPolicy must be retain, delete, or null';
  assert std.isObject(spec) : 'labsonnet CNPG: DatabaseRole spec override must be an object';
  {
    apiVersion: 'postgresql.cnpg.io/v1',
    kind: 'DatabaseRole',
    metadata: { name: resourceName, namespace: namespace },
    spec: mergeObjects(
      {
        cluster: { name: clusterName },
        name: roleName,
        login: true,
        superuser: false,
        passwordSecret: { name: secretName },
      } + (if reclaimPolicy != null then { databaseRoleReclaimPolicy: reclaimPolicy } else {}),
      spec
    ),
  };

{
  remoteCredentials(store, remoteKey, storeKind='ClusterSecretStore', property=null)::
    assert nonEmptyString(store) : 'labsonnet CNPG: remote credentials require a non-empty store';
    assert nonEmptyString(remoteKey) : 'labsonnet CNPG: remote credentials require a non-empty remoteKey';
    assert nonEmptyString(storeKind) : 'labsonnet CNPG: remote credentials storeKind must be a non-empty string';
    assert property == null || nonEmptyString(property) : 'labsonnet CNPG: remote credentials property must be a non-empty string or null';
    {
      mode: 'remote',
      store: store,
      storeKind: storeKind,
      remoteKey: remoteKey,
      [if property != null then 'property']: property,
    },

  generatedCredentials(generatorName, replicationStore=null, replicationStoreKind='ClusterSecretStore', replicationServiceAccount=null, replicationNamespace=null)::
    assert nonEmptyString(generatorName) : 'labsonnet CNPG: generated credentials require a non-empty generatorName';
    assert replicationStore == null || nonEmptyString(replicationStore) : 'labsonnet CNPG: generated credentials replicationStore must be a non-empty string or null';
    assert replicationStoreKind == null || nonEmptyString(replicationStoreKind) : 'labsonnet CNPG: generated credentials replicationStoreKind must be a non-empty string or null';
    assert replicationServiceAccount == null || std.isObject(replicationServiceAccount)
           : 'labsonnet CNPG: generated credentials replicationServiceAccount must be an object or null';
    assert replicationNamespace == null || nonEmptyString(replicationNamespace)
           : 'labsonnet CNPG: generated credentials replicationNamespace must be a non-empty string or null';
    {
      mode: 'generated',
      generatorName: generatorName,
      [if replicationStore != null then 'replicationStore']: replicationStore,
      [if replicationStore != null && replicationStoreKind != null then 'replicationStoreKind']: replicationStoreKind,
      [if replicationServiceAccount != null then 'replicationServiceAccount']: replicationServiceAccount,
      [if replicationNamespace != null then 'replicationNamespace']: replicationNamespace,
    },

  // Create a CNPG Cluster. Defaults are intentionally small and portable;
  // image and storage class are left to operator/cluster defaults.
  newCluster(name):: {
    _name:: name,
    _namespace:: 'default',
    _instances:: 1,
    _storageSize:: '5Gi',
    _storageClass:: null,
    _image:: null,
    _affinity:: null,
    _roles:: [],
    _extensions:: [],
    _preloadLibraries:: [],
    _clusterSpecs:: [],

    local cfg = self,
    cluster:
      local nodeAffinity =
        if cfg._affinity == null then null
        else if std.isObject(cfg._affinity) && std.objectHas(cfg._affinity, 'nodeAffinity')
        then cfg._affinity.nodeAffinity
        else cfg._affinity;
      local defaults = {
                         instances: cfg._instances,
                         storage: {
                           size: cfg._storageSize,
                           [if cfg._storageClass != null then 'storageClass']: cfg._storageClass,
                         },
                         affinity: {
                           enablePodAntiAffinity: true,
                           podAntiAffinityType: 'required',
                           topologyKey: 'kubernetes.io/hostname',
                           [if nodeAffinity != null then 'nodeAffinity']: nodeAffinity,
                         },
                       }
                       + (if cfg._image != null then { imageName: cfg._image } else {})
                       + (if std.length(cfg._roles) > 0 then {
                            managed: {
                              roles: [
                                {
                                  name: role.name,
                                  ensure: 'present',
                                  login: true,
                                  superuser: false,
                                  passwordSecret: { name: role.secretName },
                                }
                                for role in cfg._roles
                              ],
                            },
                          } else {});
      local extensionSpec =
        if std.length(cfg._extensions) == 0 then {}
        else {
          postgresql: {
            extensions: [
              mergeObjects(
                { name: extension.name }
                + (if extension.image != null then {
                     image: imageVolume.source(
                       extension.image,
                       if std.objectHas(extension.config, 'image') && std.objectHas(extension.config.image, 'pullPolicy')
                       then extension.config.image.pullPolicy
                       else null
                     ),
                   } else {}),
                { [key]: extension.config[key] for key in std.objectFields(extension.config) if key != 'image' }
              )
              for extension in cfg._extensions
            ],
          },
        };
      local preloadSpec =
        if std.length(cfg._preloadLibraries) == 0 then {}
        else { postgresql: { shared_preload_libraries: unique(cfg._preloadLibraries) } };
      local customSpec = std.foldl(mergeObjects, cfg._clusterSpecs, {});
      local finalSpec = mergeObjects(mergeObjects(mergeObjects(defaults, extensionSpec), preloadSpec), customSpec);
      assert validDnsLabel(cfg._name) : 'labsonnet CNPG: cluster name must be a valid DNS label';
      assert validDnsLabel(cfg._namespace) : 'labsonnet CNPG: namespace must be a valid DNS label';
      assert std.isNumber(cfg._instances) && cfg._instances >= 1 && std.floor(cfg._instances) == cfg._instances
             : "labsonnet CNPG '%s': instances must be a positive integer" % cfg._name;
      assert nonEmptyString(cfg._storageSize)
             : "labsonnet CNPG '%s': storage size must be a non-empty string" % cfg._name;
      assert cfg._storageClass == null || nonEmptyString(cfg._storageClass)
             : "labsonnet CNPG '%s': storage class must be a non-empty string or null" % cfg._name;
      assert cfg._image == null || nonEmptyString(cfg._image)
             : "labsonnet CNPG '%s': image must be a non-empty string or null" % cfg._name;
      assert cfg._affinity == null || (std.isObject(cfg._affinity) && std.isObject(nodeAffinity))
             : "labsonnet CNPG '%s': withAffinity expects a nodeAffinity object or an object containing nodeAffinity" % cfg._name;
      assert std.all([std.isObject(spec) for spec in cfg._clusterSpecs])
             : "labsonnet CNPG '%s': cluster spec overrides must be objects" % cfg._name;
      assert std.all([nonEmptyString(role.name) && nonEmptyString(role.secretName) for role in cfg._roles])
             : "labsonnet CNPG '%s': role names and secret names must be non-empty strings" % cfg._name;
      assert std.length(std.set([role.name for role in cfg._roles])) == std.length(cfg._roles)
             : "labsonnet CNPG '%s': inline role names must be unique" % cfg._name;
      assert std.all([
        validExtensionName(extension.name)
        && (extension.image == null || nonEmptyString(extension.image))
        && std.isObject(extension.config)
        && (!std.objectHas(extension.config, 'image') || (
              extension.image != null
              &&
              std.isObject(extension.config.image)
              && std.all([key == 'pullPolicy' for key in std.objectFields(extension.config.image)])
            ))
        && !std.objectHas(extension.config, 'name')
        for extension in cfg._extensions
      ])
             : "labsonnet CNPG '%s': extension name, image reference, and config are invalid" % cfg._name;
      assert std.length(std.set([std.strReplace(extension.name, '_', '-') for extension in cfg._extensions])) == std.length(cfg._extensions)
             : "labsonnet CNPG '%s': extension names must be unique" % cfg._name;
      assert std.all([
        extension.image != null || std.objectHas(finalSpec, 'imageCatalogRef')
        for extension in cfg._extensions
      ]) : "labsonnet CNPG '%s': an imageCatalogRef is required when an extension image is omitted" % cfg._name;
      assert std.all([nonEmptyString(lib) for lib in cfg._preloadLibraries])
             : "labsonnet CNPG '%s': shared preload library names must be non-empty strings" % cfg._name;
      assert std.isNumber(finalSpec.instances) && finalSpec.instances >= 1 && std.floor(finalSpec.instances) == finalSpec.instances
             : "labsonnet CNPG '%s': final spec.instances must be a positive integer" % cfg._name;
      {
        apiVersion: 'postgresql.cnpg.io/v1',
        kind: 'Cluster',
        metadata: { name: cfg._name, namespace: cfg._namespace },
        spec: finalSpec,
      },
  },

  // Build the shared External Secrets resources used for generated credentials.
  // The replication Store is cluster-scoped, while its reader ServiceAccount and
  // password generator live in the source namespace.
  newCredentialInfrastructure(name, namespace='default', generatorName=null, passwordSpec={})::
    local actualGeneratorName = if generatorName == null then name + '-password' else generatorName;
    local store = externalSecret.newKubernetesReplicationStore(name, namespace);
    {
      passwordGenerator: externalSecret.newPasswordGenerator(actualGeneratorName, namespace, passwordSpec),
      credentialReader: store.credentialReader,
      credentialStore: store.credentialStore,
    },

  withNamespace(namespace):: { _namespace:: namespace },
  withInstances(instances):: { _instances:: instances },
  withStorageSize(size):: { _storageSize:: size },
  withStorageClass(storageClass):: { _storageClass:: storageClass },
  withImage(image):: { _image:: image },
  // Accept either a full affinity object with a nodeAffinity field (the shape
  // used by Kubernetes workload helpers) or the nodeAffinity value itself.
  withAffinity(affinity):: { _affinity:: affinity },
  withRole(name, secretName):: {
    _roles+:: [{ name: name, secretName: secretName }],
  },
  // Mount an extension image volume in the CNPG PostgreSQL container. `image`
  // may be null when the Cluster references an imageCatalogRef.
  withExtension(name, image=null, config={}):: {
    _extensions+:: [{ name: name, image: image, config: config }],
  },
  // Add PostgreSQL libraries that must be loaded at server startup.
  withSharedPreloadLibraries(libraries):: {
    _preloadLibraries+:: assert std.isArray(libraries)
                                : 'labsonnet CNPG: withSharedPreloadLibraries expects an array'; libraries,
  },
  // Raw CNPG fields deep-merge over generated fields and win on conflicts.
  withClusterSpec(spec):: {
    _clusterSpecs+:: [assert std.isObject(spec) : 'labsonnet CNPG: withClusterSpec expects an object'; spec],
  },

  // Standalone CNPG Database. Set reclaimPolicy=null to omit the field.
  newDatabase(name, clusterName, ownerName=name, namespace='default', reclaimPolicy='retain', spec={}, resourceName=null)::
    databaseResource(if resourceName == null then name else resourceName, name, clusterName, ownerName, namespace, reclaimPolicy, spec),

  // CNPG 1.30+ standalone DatabaseRole. These resources are namespace-scoped
  // with their Cluster and password Secret.
  newRole(name, clusterName, secretName, namespace='default', roleName=name, reclaimPolicy='retain', spec={})::
    roleResource(name, clusterName, secretName, namespace, roleName, reclaimPolicy, spec),

  // Emit a tenant's Database, DatabaseRole, and credentials ExternalSecrets.
  // credentials is either {mode:'remote', store, storeKind?, remoteKey, property?}
  // or {mode:'generated', generatorName, generatorKind?, replicationStore?, replicationStoreKind?}.
  newTenant(name, clusterName, clusterNamespace, appNamespace=name, credentials=null, resourceName=null, secretName=null, databaseSpec={}, roleSpec={})::
    assert std.isObject(databaseSpec) && std.isObject(roleSpec) : 'labsonnet CNPG: tenant spec overrides must be objects';
    assert std.all([!std.objectHas(databaseSpec, key) for key in ['name', 'owner', 'cluster']])
           : 'labsonnet CNPG: tenant databaseSpec must not override name, owner, or cluster';
    assert std.all([!std.objectHas(roleSpec, key) for key in ['name', 'cluster', 'passwordSecret']])
           : 'labsonnet CNPG: tenant roleSpec must not override name, cluster, or passwordSecret';
    local remote = credentials.mode == 'remote';
    local sameNamespace = appNamespace == clusterNamespace;
    local hasReplicationServiceAccount = std.isObject(credentials) && std.objectHas(credentials, 'replicationServiceAccount');
    local replicationServiceAccount = if hasReplicationServiceAccount then credentials.replicationServiceAccount else null;
    local replicationServiceAccountNamespace =
      if std.isObject(replicationServiceAccount) then std.get(replicationServiceAccount, 'namespace', clusterNamespace)
      else clusterNamespace;
    local tenantResourceName = if resourceName == null then clusterName + '-' + name else resourceName;
    local tenantSecretName = if secretName == null then name + '-postgres' else secretName;
    local host = clusterName + '-rw.' + clusterNamespace + '.svc';
    local roleTemplate = roleSecretTemplate(name, name, host, sameNamespace);
    assert tenantConnectionName(name) : 'labsonnet CNPG: tenant name must be at most 63 ASCII letters, digits, or URI-unreserved characters';
    assert validDnsLabel(clusterName) : 'labsonnet CNPG: cluster name must be a valid DNS label';
    assert validDnsLabel(clusterNamespace) : 'labsonnet CNPG: cluster namespace must be a valid DNS label';
    assert validDnsLabel(appNamespace) : 'labsonnet CNPG: application namespace must be a valid DNS label';
    assert std.isObject(credentials) : 'labsonnet CNPG: tenant credentials configuration is required';
    assert std.objectHas(credentials, 'mode') : 'labsonnet CNPG: credentials.mode is required';
    assert std.member(['remote', 'generated'], credentials.mode)
           : "labsonnet CNPG: credentials.mode must be 'remote' or 'generated'";
    assert validDnsSubdomain(tenantResourceName) : 'labsonnet CNPG: tenant resourceName must be a valid DNS subdomain';
    assert validDnsSubdomain(tenantSecretName) : 'labsonnet CNPG: tenant secretName must be a valid DNS subdomain';
    assert if remote then
      nonEmptyString(std.get(credentials, 'store'))
      && nonEmptyString(std.get(credentials, 'remoteKey'))
    else
      nonEmptyString(std.get(credentials, 'generatorName'))
      && (sameNamespace || nonEmptyString(std.get(credentials, 'replicationStore')))
           : "labsonnet CNPG '%s': remote credentials require store and remoteKey; generated credentials require generatorName and a replicationStore across namespaces" % name;
    assert !remote || std.get(credentials, 'property') == null || nonEmptyString(credentials.property)
           : 'labsonnet CNPG: credentials.property must be a non-empty string or null when supplied';
    local passwordRemoteRef = {
      key: credentials.remoteKey,
      [if std.get(credentials, 'property') != null then 'property']: credentials.property,
    };
    assert !std.objectHas(credentials, 'generatorKind') || (!remote && std.member(['Password', 'ClusterGenerator'], credentials.generatorKind))
           : "labsonnet CNPG '%s': generatorKind must be Password or ClusterGenerator for generated credentials" % name;
    assert !std.objectHas(credentials, 'storeKind') || (remote && nonEmptyString(credentials.storeKind))
           : "labsonnet CNPG '%s': storeKind is only valid as a non-empty remote credential option" % name;
    assert !std.objectHas(credentials, 'replicationStoreKind') || (!remote && nonEmptyString(credentials.replicationStoreKind))
           : "labsonnet CNPG '%s': replicationStoreKind is only valid as a non-empty generated credential option" % name;
    assert !hasReplicationServiceAccount || !remote
           : "labsonnet CNPG '%s': replicationServiceAccount is only valid for generated credentials" % name;
    assert !hasReplicationServiceAccount || replicationServiceAccount == null || (
      std.isObject(replicationServiceAccount)
      && validDnsLabel(std.get(replicationServiceAccount, 'name'))
      && validDnsLabel(replicationServiceAccountNamespace)
    ) : "labsonnet CNPG '%s': replicationServiceAccount requires a valid name and optional valid namespace" % name;
    assert !std.objectHas(credentials, 'replicationNamespace') || !remote
           : "labsonnet CNPG '%s': replicationNamespace is only valid for generated credentials" % name;
    assert !std.objectHas(credentials, 'replicationNamespace')
           || credentials.replicationNamespace == null
           || validDnsLabel(credentials.replicationNamespace)
           : "labsonnet CNPG '%s': replicationNamespace must be a valid namespace" % name;
    assert sameNamespace
           || std.get(credentials, 'replicationNamespace') == null
           || credentials.replicationNamespace == clusterNamespace
           : "labsonnet CNPG '%s': replicationNamespace must match clusterNamespace for cross-namespace credentials" % name;
    {
      role: roleResource(tenantResourceName, clusterName, tenantSecretName, clusterNamespace, name, 'retain', roleSpec),
      database: databaseResource(tenantResourceName, name, clusterName, name, clusterNamespace, 'retain', databaseSpec),
      roleCredentials:
        if remote then
          credentialsSecret(
            tenantSecretName,
            clusterNamespace,
            credentials.store,
            std.get(credentials, 'storeKind'),
            roleTemplate,
            [{ secretKey: 'password', remoteRef: passwordRemoteRef }],
            null,
            'Periodic',
            '1h'
          )
        else
          credentialsSecret(
            tenantSecretName,
            clusterNamespace,
            null,
            null,
            roleTemplate,
            null,
            [{ sourceRef: { generatorRef: {
              apiVersion: 'generators.external-secrets.io/v1alpha1',
              kind: std.get(credentials, 'generatorKind', 'Password'),
              name: credentials.generatorName,
            } } }],
            'OnChange',
            null
          ),
      applicationCredentials:
        if sameNamespace then {}
        else if remote then
          credentialsSecret(
            tenantSecretName,
            appNamespace,
            credentials.store,
            std.get(credentials, 'storeKind'),
            appSecretTemplate(name, name, host),
            [{ secretKey: 'password', remoteRef: passwordRemoteRef }],
            null,
            'Periodic',
            '1h'
          )
        else
          credentialsSecret(
            tenantSecretName,
            appNamespace,
            credentials.replicationStore,
            std.get(credentials, 'replicationStoreKind'),
            appSecretTemplate(name, name, host),
            [{ secretKey: 'password', remoteRef: { key: tenantSecretName, property: 'password' } }],
            null,
            'Periodic',
            '1m'
          ),
    } + (
      if hasReplicationServiceAccount && replicationServiceAccount != null && !remote && !sameNamespace then
        externalSecret.newSecretReadGrant(
          tenantResourceName,
          clusterNamespace,
          [tenantSecretName],
          replicationServiceAccount.name,
          serviceAccountNamespace=replicationServiceAccountNamespace
        )
      else {}
    ),
}
