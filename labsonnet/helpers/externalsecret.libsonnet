// Standalone ExternalSecret and External Secrets credential infrastructure builders.

local d = import 'github.com/jsonnet-libs/docsonnet/doc-util/main.libsonnet';

local externalSecrets = import 'external-secrets.libsonnet';
local externalSecret = externalSecrets.nogroup.v1.externalSecret;
local clusterSecretStore = externalSecrets.nogroup.v1.clusterSecretStore;

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

{
  '#':: d.pkg(
    name='externalsecret',
    url='https://github.com/dzervas/labsonnet',
    filename=std.thisFile,
    version='main',
    help='Build ExternalSecret, password generator, Kubernetes replication store, and narrow Secret read access resources. Requires the External Secrets Operator CRDs.',
  ) + d.package.withInstallTemplate('jb install github.com/dzervas/labsonnet/labsonnet@main')
    + d.package.withUsageTemplate("local externalsecret = import 'labsonnet/helpers/externalsecret.libsonnet'"),

  '#new':: d.fn(|||
    Create an ExternalSecret. `dataFrom` and `data` are omitted when empty. Store and refresh or target policies are omitted when null.

    Example:

    ```jsonnet
    local e = import 'labsonnet/helpers/externalsecret.libsonnet';
    {
      secret: e.new('api-token', 'apps', 'app-secrets',
        dataFrom=[{ extract: { key: 'api-token' } }]),
    }
    ```
  |||, [
    d.arg('name', d.T.string),
    d.arg('namespace', d.T.string),
    d.argument.fromSchema('storeName', { type: ['string', 'null'], default: null }),
    d.arg('storeKind', d.T.string, 'ClusterSecretStore'),
    d.arg('dataFrom', d.T.array, []),
    d.arg('data', d.T.array, []),
    d.argument.fromSchema('refreshInterval', { type: ['string', 'null'], default: null }),
    d.argument.fromSchema('refreshPolicy', { type: ['string', 'null'], default: null }),
    d.argument.fromSchema('creationPolicy', { type: ['string', 'null'], default: null }),
    d.argument.fromSchema('deletionPolicy', { type: ['string', 'null'], default: null }),
  ]),
  new(name, namespace, storeName=null, storeKind='ClusterSecretStore', dataFrom=[], data=[], refreshInterval=null, refreshPolicy=null, creationPolicy=null, deletionPolicy=null)::
    externalSecret.new(name)
    + externalSecret.metadata.withNamespace(namespace)
    + (if storeName != null then
         externalSecret.spec.secretStoreRef.withName(storeName)
         + (if storeKind != null then externalSecret.spec.secretStoreRef.withKind(storeKind) else {})
       else {})
    + (if std.length(dataFrom) > 0 then externalSecret.spec.withDataFrom(dataFrom) else {})
    + (if std.length(data) > 0 then externalSecret.spec.withData(data) else {})
    + (if refreshInterval != null then externalSecret.spec.withRefreshInterval(refreshInterval) else {})
    + (if refreshPolicy != null then externalSecret.spec.withRefreshPolicy(refreshPolicy) else {})
    + (if creationPolicy != null then externalSecret.spec.target.withCreationPolicy(creationPolicy) else {})
    + (if deletionPolicy != null then externalSecret.spec.target.withDeletionPolicy(deletionPolicy) else {}),

  // Create a namespaced Password generator. The caller owns its password policy.
  '#newPasswordGenerator':: d.fn(|||
    Create an External Secrets Password generator in a namespace. Pass the generator's policy in `spec`.

    Example:

    ```jsonnet
    local e = import 'labsonnet/helpers/externalsecret.libsonnet';
    {
      passwordGenerator: e.newPasswordGenerator('app-password', 'apps', { length: 40, allowRepeat: true }),
    }
    ```
  |||, [
    d.arg('name', d.T.string),
    d.arg('namespace', d.T.string),
    d.arg('spec', d.T.object, {}),
  ]),
  newPasswordGenerator(name, namespace, spec={})::
    assert validDnsSubdomain(name) : 'labsonnet ExternalSecret: Password generator name must be a valid DNS subdomain';
    assert validDnsLabel(namespace) : 'labsonnet ExternalSecret: Password generator namespace must be a valid DNS label';
    assert std.isObject(spec) : 'labsonnet ExternalSecret: Password generator spec must be an object';
    {
      apiVersion: 'generators.external-secrets.io/v1alpha1',
      kind: 'Password',
      metadata: { name: name, namespace: namespace },
      spec: spec,
    },

  // Create the ServiceAccount and ClusterSecretStore used to replicate secrets
  // from one namespace. The matching Role grants are intentionally separate.
  '#newKubernetesReplicationStore':: d.fn(|||
    Create a reader ServiceAccount and a ClusterSecretStore that reads Secrets from `namespace`. Add a separate Role and RoleBinding to grant access to specific Secrets.
    The reader name defaults to `name`; the reader namespace defaults to the source `namespace`.

    Example:

    ```jsonnet
    local e = import 'labsonnet/helpers/externalsecret.libsonnet';
    {
      replicationStore: e.newKubernetesReplicationStore('app-credentials', 'database'),
    }
    ```
  |||, [
    d.arg('name', d.T.string),
    d.arg('namespace', d.T.string),
    d.argument.fromSchema('serviceAccountName', { type: ['string', 'null'], default: null }),
    d.arg('serviceAccountNamespace', d.T.string),
  ]),
  newKubernetesReplicationStore(name, namespace, serviceAccountName=null, serviceAccountNamespace=namespace)::
    local readerName = if serviceAccountName == null then name else serviceAccountName;
    assert validDnsSubdomain(name) : 'labsonnet ExternalSecret: replication store name must be a valid DNS subdomain';
    assert validDnsLabel(namespace) : 'labsonnet ExternalSecret: replication store namespace must be a valid DNS label';
    assert validDnsLabel(readerName) : 'labsonnet ExternalSecret: credential reader ServiceAccount name must be a valid DNS label';
    assert validDnsLabel(serviceAccountNamespace) : 'labsonnet ExternalSecret: credential reader ServiceAccount namespace must be a valid DNS label';
    {
      credentialReader: {
        apiVersion: 'v1',
        kind: 'ServiceAccount',
        metadata: { name: readerName, namespace: serviceAccountNamespace },
        automountServiceAccountToken: false,
      },
      credentialStore:
        clusterSecretStore.new(name)
        + {
          spec: {
            provider: {
              kubernetes: {
                remoteNamespace: namespace,
                auth: {
                  serviceAccount: { name: readerName, namespace: serviceAccountNamespace },
                },
                server: {
                  url: 'https://kubernetes.default.svc',
                  caProvider: {
                    type: 'ConfigMap',
                    name: 'kube-root-ca.crt',
                    namespace: namespace,
                    key: 'ca.crt',
                  },
                },
              },
            },
          },
        },
    },

  // Grant one ServiceAccount read access to an explicit set of Secrets in a
  // namespace. Empty resourceNames would mean unrestricted access, so reject it.
  '#newSecretReadGrant':: d.fn(|||
    Grant a ServiceAccount `get` access to the named Secrets in one namespace. At least one Secret name is required.
    The ServiceAccount namespace defaults to the Secret namespace.

    Example:

    ```jsonnet
    local e = import 'labsonnet/helpers/externalsecret.libsonnet';
    {
      secretReadGrant: e.newSecretReadGrant('api-credentials', 'database', ['api-postgres'],
        'api-reader'),
    }
    ```
  |||, [
    d.arg('name', d.T.string),
    d.arg('namespace', d.T.string),
    d.arg('secretNames', d.T.array),
    d.arg('serviceAccountName', d.T.string),
    d.arg('serviceAccountNamespace', d.T.string),
  ]),
  newSecretReadGrant(name, namespace, secretNames, serviceAccountName, serviceAccountNamespace=namespace)::
    assert validDnsSubdomain(name) : 'labsonnet ExternalSecret: secret read grant name must be a valid DNS subdomain';
    assert validDnsLabel(namespace) : 'labsonnet ExternalSecret: secret read grant namespace must be a valid DNS label';
    assert std.isArray(secretNames) && std.length(secretNames) > 0
           : 'labsonnet ExternalSecret: secret read grant requires at least one secret name';
    assert std.all([validDnsSubdomain(secretName) for secretName in secretNames])
           : 'labsonnet ExternalSecret: secret read grant secret names must be valid DNS subdomains';
    assert validDnsLabel(serviceAccountName)
           : 'labsonnet ExternalSecret: secret read grant ServiceAccount name must be a valid DNS label';
    assert validDnsLabel(serviceAccountNamespace)
           : 'labsonnet ExternalSecret: secret read grant ServiceAccount namespace must be a valid DNS label';
    local rule = {
      apiGroups: [''],
      resources: ['secrets'],
      resourceNames: secretNames,
      verbs: ['get'],
    };
    {
      credentialReaderRole: {
        apiVersion: 'rbac.authorization.k8s.io/v1',
        kind: 'Role',
        metadata: { name: name, namespace: namespace },
        rules: [rule],
      },
      credentialReaderBinding: {
        apiVersion: 'rbac.authorization.k8s.io/v1',
        kind: 'RoleBinding',
        metadata: { name: name, namespace: namespace },
        subjects: [
          { kind: 'ServiceAccount', name: serviceAccountName, namespace: serviceAccountNamespace },
        ],
        roleRef: { apiGroup: 'rbac.authorization.k8s.io', kind: 'Role', name: name },
      },
    },

  '#withSecretLabels':: d.fn(|||
    Return a patch that sets labels on an ExternalSecret's target Secret template.

    Example:

    ```jsonnet
    local e = import 'labsonnet/helpers/externalsecret.libsonnet';
    {
      secret: std.mergePatch(
        e.new('api-token', 'apps', 'app-secrets'),
        e.withSecretLabels({ app: 'api' })
      ),
    }
    ```
  |||, [d.arg('labels', d.T.object)]),
  withSecretLabels(labels)::
    externalSecret.spec.target.template.metadata.withLabels(labels),
}
