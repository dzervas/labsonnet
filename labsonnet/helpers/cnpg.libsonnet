// Generic CloudNativePG builders using labsonnet's resource helpers.
local d = import 'github.com/jsonnet-libs/docsonnet/doc-util/main.libsonnet';
local externalSecret = import './externalsecret.libsonnet';
local cloudnativePg = import 'cloudnative-pg.libsonnet';

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
  '#':: d.pkg(
    name='cnpg',
    url='https://github.com/dzervas/labsonnet',
    filename=std.thisFile,
    version='main',
    help=|||
      Build CloudNativePG databases, roles, and tenant credentials. Requires CloudNativePG and External Secrets Operator CRDs.

      `cluster` re-exports the upstream [cloudnative-pg-libsonnet](https://github.com/jsonnet-libs/cloudnative-pg-libsonnet) Cluster builder unchanged. It returns the resource itself; set instances, storage, and placement explicitly. Cluster defaults belong in downstream configuration.

      To use `cnpg.cluster`, install the upstream dependency in your Tanka project:

      ```bash
      jb install github.com/jsonnet-libs/cloudnative-pg-libsonnet@main
      ```

      You must also create `lib/cloudnative-pg.libsonnet` with a one-line import selecting your upstream schema version, for example:

      ```jsonnet
      import 'github.com/jsonnet-libs/cloudnative-pg-libsonnet/1.27.0/main.libsonnet'
      ```

      Choose a version available in your `vendor/` directory and compatible with your operator. Tanka includes `lib/` and `vendor/` in its import paths; when using the Jsonnet CLI, pass `-J lib -J vendor`. The downstream import selects the schema version, and your project's `jsonnetfile.lock.json` pins the dependency revision.

      ```jsonnet
      local cnpg = import 'labsonnet/helpers/cnpg.libsonnet';
      local cluster = cnpg.cluster;
      {
        postgres:
          cluster.new('postgres')
          + cluster.metadata.withNamespace('database')
          + cluster.spec.withInstances(3)
          + cluster.spec.storage.withSize('50Gi'),
      }
      ```
    |||,
  ) + d.package.withInstallTemplate('jb install github.com/dzervas/labsonnet/labsonnet@main')
    + d.package.withUsageTemplate("local cnpg = import 'labsonnet/helpers/cnpg.libsonnet'"),

  // Preserve the upstream API and let the downstream lib import choose its version.
  cluster:: cloudnativePg.postgresql.v1.cluster,

  '#remoteCredentials':: d.fn(|||
    Describe credentials that an ExternalSecret reads from a SecretStore. Use this object as the `credentials` value for `newTenant`.

    Example:

    ```jsonnet
    local cnpg = import 'labsonnet/helpers/cnpg.libsonnet';
    {
      credentials: cnpg.remoteCredentials('app-secrets', 'catalog-password'),
    }
    ```
  |||, [d.arg('store', d.T.string), d.arg('remoteKey', d.T.string),
       d.arg('storeKind', d.T.string, 'ClusterSecretStore'),
       d.argument.fromSchema('property', { type: ['string', 'null'], default: null })]),
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

  '#generatedCredentials':: d.fn(|||
    Describe generated credentials for `newTenant`. A replication store is needed when the app Secret lives outside the database namespace.

    Example:

    ```jsonnet
    local cnpg = import 'labsonnet/helpers/cnpg.libsonnet';
    {
      credentials: cnpg.generatedCredentials('postgres-password', 'postgres-credentials'),
    }
    ```
  |||, [d.arg('generatorName', d.T.string),
       d.argument.fromSchema('replicationStore', { type: ['string', 'null'], default: null }),
       d.arg('replicationStoreKind', d.T.string, 'ClusterSecretStore')]),
  generatedCredentials(generatorName, replicationStore=null, replicationStoreKind='ClusterSecretStore')::
    assert nonEmptyString(generatorName) : 'labsonnet CNPG: generated credentials require a non-empty generatorName';
    assert replicationStore == null || nonEmptyString(replicationStore) : 'labsonnet CNPG: generated credentials replicationStore must be a non-empty string or null';
    assert replicationStoreKind == null || nonEmptyString(replicationStoreKind) : 'labsonnet CNPG: generated credentials replicationStoreKind must be a non-empty string or null';
    {
      mode: 'generated',
      generatorName: generatorName,
      [if replicationStore != null then 'replicationStore']: replicationStore,
      [if replicationStore != null && replicationStoreKind != null then 'replicationStoreKind']: replicationStoreKind,
    },

  // Build the shared External Secrets resources used for generated credentials.
  // The replication Store is cluster-scoped and the password generator lives in
  // the source namespace. The reader ServiceAccount namespace is configurable.
  '#newCredentialInfrastructure':: d.fn(|||
    Create a Password generator, reader ServiceAccount, and ClusterSecretStore for generated credentials.
    The generator name defaults to `<name>-password`; the reader ServiceAccount namespace defaults to the `namespace` argument.

    If a local wrapper overrides `serviceAccountName` or `serviceAccountNamespace`,
    keep `newCredentialReadGrant` configured for that same reader. Its RoleBinding
    must target the ServiceAccount used by the store to read Secrets.

    Example:

    ```jsonnet
    local cnpg = import 'labsonnet/helpers/cnpg.libsonnet';
    {
      infrastructure: cnpg.newCredentialInfrastructure('postgres-credentials', 'database',
        generatorName='postgres-password',
        passwordSpec={ length: 40, allowRepeat: true }),
    }
    ```
  |||, [d.arg('name', d.T.string),
       d.arg('namespace', d.T.string, 'default'),
       d.argument.fromSchema('generatorName', { type: ['string', 'null'], default: null }),
       d.arg('passwordSpec', d.T.object, {}),
       d.argument.fromSchema('serviceAccountName', { type: ['string', 'null'], default: null }),
       d.arg('serviceAccountNamespace', d.T.string)]),
  newCredentialInfrastructure(name, namespace='default', generatorName=null, passwordSpec={}, serviceAccountName=null, serviceAccountNamespace=namespace)::
    local actualGeneratorName = if generatorName == null then name + '-password' else generatorName;
    local store = externalSecret.newKubernetesReplicationStore(
      name,
      namespace,
      serviceAccountName=serviceAccountName,
      serviceAccountNamespace=serviceAccountNamespace
    );
    {
      passwordGenerator: externalSecret.newPasswordGenerator(actualGeneratorName, namespace, passwordSpec),
      credentialReader: store.credentialReader,
      credentialStore: store.credentialStore,
    },

  // Standalone CNPG Database. Set reclaimPolicy=null to omit the field.
  '#newDatabase':: d.fn(|||
    Create a Database resource. `ownerName` and `resourceName` default to `name`; `namespace` defaults to `default`; `reclaimPolicy` defaults to `retain`. Set `reclaimPolicy=null` to omit it.

    Example:

    ```jsonnet
    local cnpg = import 'labsonnet/helpers/cnpg.libsonnet';
    {
      database: cnpg.newDatabase('catalog', 'postgres', namespace='database'),
    }
    ```
  |||, [d.arg('name', d.T.string), d.arg('clusterName', d.T.string),
       d.arg('ownerName', d.T.string),
       d.arg('namespace', d.T.string, 'default'),
       d.arg('reclaimPolicy', d.T.string, 'retain'),
       d.arg('spec', d.T.object, {}),
       d.argument.fromSchema('resourceName', { type: ['string', 'null'], default: null })]),
  newDatabase(name, clusterName, ownerName=name, namespace='default', reclaimPolicy='retain', spec={}, resourceName=null)::
    databaseResource(if resourceName == null then name else resourceName, name, clusterName, ownerName, namespace, reclaimPolicy, spec),

  // CNPG 1.30+ standalone DatabaseRole. These resources are namespace-scoped
  // with their Cluster and password Secret.
  '#newRole':: d.fn(|||
    Create a DatabaseRole with login enabled and a password Secret reference. Requires CloudNativePG 1.30 or later, which provides the DatabaseRole CRD. `roleName` defaults to `name`; `namespace` defaults to `default`; `reclaimPolicy` defaults to `retain`.

    Example:

    ```jsonnet
    local cnpg = import 'labsonnet/helpers/cnpg.libsonnet';
    {
      role: cnpg.newRole('catalog', 'postgres', 'catalog-postgres', namespace='database'),
    }
    ```
  |||, [d.arg('name', d.T.string), d.arg('clusterName', d.T.string),
       d.arg('secretName', d.T.string), d.arg('namespace', d.T.string, 'default'),
       d.arg('roleName', d.T.string),
       d.arg('reclaimPolicy', d.T.string, 'retain'), d.arg('spec', d.T.object, {})]),
  newRole(name, clusterName, secretName, namespace='default', roleName=name, reclaimPolicy='retain', spec={})::
    roleResource(name, clusterName, secretName, namespace, roleName, reclaimPolicy, spec),

  // Project wrappers supply the shared reader identity through this helper's
  // default arguments. Generic tenants emit no grant until a reader is supplied.
  '#newCredentialReadGrant':: d.fn(|||
    Allow a ServiceAccount to read the password Secret referenced by a DatabaseRole. The ServiceAccount namespace defaults to the role namespace. If `serviceAccountName` is null, return an empty object.

    Use the same ServiceAccount name and namespace as `newCredentialInfrastructure`,
    including any overrides in your local wrapper.

    Example:

    ```jsonnet
    local cnpg = import 'labsonnet/helpers/cnpg.libsonnet';
    local role = cnpg.newRole('app', 'postgres', 'app-postgres', namespace='database');
    {
      credentialReadGrant: cnpg.newCredentialReadGrant(role, 'app-reader'),
    }
    ```
  |||, [d.arg('role', d.T.object),
       d.argument.fromSchema('serviceAccountName', { type: ['string', 'null'], default: null }),
       d.arg('serviceAccountNamespace', d.T.string)]),
  newCredentialReadGrant(role, serviceAccountName=null, serviceAccountNamespace=role.metadata.namespace)::
    if serviceAccountName == null then {}
    else externalSecret.newSecretReadGrant(
      role.metadata.name,
      role.metadata.namespace,
      [role.spec.passwordSecret.name],
      serviceAccountName,
      serviceAccountNamespace
    ),

  // Emit a tenant's Database, DatabaseRole, and credentials ExternalSecrets.
  // credentials is either {mode:'remote', store, storeKind?, remoteKey, property?}
  // or {mode:'generated', generatorName, generatorKind?, replicationStore?, replicationStoreKind?}.
  '#newTenant':: d.fn(|||
    Create a tenant Database, DatabaseRole, and ExternalSecret credentials. Build `credentials` with `remoteCredentials` or `generatedCredentials`, or pass an equivalent object. The application namespace defaults to the tenant name; resource and Secret names default to `<cluster>-<tenant>` and `<tenant>-postgres`. Generated credentials need a replication store when the application and database namespaces differ. Create it with `newCredentialInfrastructure`, then grant its reader access with `newCredentialReadGrant(tenant.role, infrastructure.credentialReader.metadata.name, infrastructure.credentialReader.metadata.namespace)`; the generator and store names must match.

    Example:

    ```jsonnet
    local cnpg = import 'labsonnet/helpers/cnpg.libsonnet';
    {
      tenant: cnpg.newTenant(
        'catalog', 'postgres', 'database',
        credentials=cnpg.generatedCredentials('postgres-password', 'postgres-credentials')),
    }
    ```
  |||, [d.arg('name', d.T.string), d.arg('clusterName', d.T.string),
       d.arg('clusterNamespace', d.T.string), d.arg('appNamespace', d.T.string),
       d.argument.fromSchema('credentials', { type: ['object', 'null'], default: null }),
       d.argument.fromSchema('resourceName', { type: ['string', 'null'], default: null }),
       d.argument.fromSchema('secretName', { type: ['string', 'null'], default: null }),
       d.arg('databaseSpec', d.T.object, {}),
       d.arg('roleSpec', d.T.object, {})]),
  newTenant(name, clusterName, clusterNamespace, appNamespace=name, credentials=null, resourceName=null, secretName=null, databaseSpec={}, roleSpec={})::
    assert std.isObject(databaseSpec) && std.isObject(roleSpec) : 'labsonnet CNPG: tenant spec overrides must be objects';
    assert std.all([!std.objectHas(databaseSpec, key) for key in ['name', 'owner', 'cluster']])
           : 'labsonnet CNPG: tenant databaseSpec must not override name, owner, or cluster';
    assert std.all([!std.objectHas(roleSpec, key) for key in ['name', 'cluster', 'passwordSecret']])
           : 'labsonnet CNPG: tenant roleSpec must not override name, cluster, or passwordSecret';
    local remote = credentials.mode == 'remote';
    local sameNamespace = appNamespace == clusterNamespace;
    local tenantResourceName = if resourceName == null then clusterName + '-' + name else resourceName;
    local tenantSecretName = if secretName == null then name + '-postgres' else secretName;
    local host = clusterName + '-rw.' + clusterNamespace + '.svc';
    local roleTemplate = roleSecretTemplate(name, name, host, sameNamespace);
    local role = roleResource(tenantResourceName, clusterName, tenantSecretName, clusterNamespace, name, 'retain', roleSpec);
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
    {
      role: role,
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
    } + (if !remote && !sameNamespace then self.newCredentialReadGrant(role) else {}),
}
