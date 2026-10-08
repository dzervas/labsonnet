# cnpg

Build CloudNativePG clusters, databases, roles, and tenant credentials. Requires CloudNativePG and External Secrets Operator CRDs.
## Install

```
jb install github.com/dzervas/labsonnet/labsonnet@main
```

## Usage

```jsonnet
local cnpg = import 'labsonnet/helpers/cnpg.libsonnet'
```


## Index

* [`fn generatedCredentials(generatorName, replicationStore=null, replicationStoreKind="ClusterSecretStore")`](#fn-generatedcredentials)
* [`fn newCluster(name)`](#fn-newcluster)
* [`fn newCredentialInfrastructure(name, namespace="default", generatorName=null, passwordSpec={}, serviceAccountName=null, serviceAccountNamespace)`](#fn-newcredentialinfrastructure)
* [`fn newCredentialReadGrant(role, serviceAccountName=null, serviceAccountNamespace)`](#fn-newcredentialreadgrant)
* [`fn newDatabase(name, clusterName, ownerName, namespace="default", reclaimPolicy="retain", spec={}, resourceName=null)`](#fn-newdatabase)
* [`fn newRole(name, clusterName, secretName, namespace="default", roleName, reclaimPolicy="retain", spec={})`](#fn-newrole)
* [`fn newTenant(name, clusterName, clusterNamespace, appNamespace, credentials=null, resourceName=null, secretName=null, databaseSpec={}, roleSpec={})`](#fn-newtenant)
* [`fn remoteCredentials(store, remoteKey, storeKind="ClusterSecretStore", property=null)`](#fn-remotecredentials)
* [`fn withAffinity(affinity)`](#fn-withaffinity)
* [`fn withClusterSpec(spec)`](#fn-withclusterspec)
* [`fn withExtension(name, image=null, config={})`](#fn-withextension)
* [`fn withImage(image)`](#fn-withimage)
* [`fn withInstances(instances)`](#fn-withinstances)
* [`fn withNamespace(namespace)`](#fn-withnamespace)
* [`fn withRole(name, secretName)`](#fn-withrole)
* [`fn withSharedPreloadLibraries(libraries)`](#fn-withsharedpreloadlibraries)
* [`fn withStorageClass(storageClass)`](#fn-withstorageclass)
* [`fn withStorageSize(size)`](#fn-withstoragesize)

## Fields

### fn generatedCredentials

```jsonnet
generatedCredentials(generatorName, replicationStore=null, replicationStoreKind="ClusterSecretStore")
```

PARAMETERS:

* **generatorName** (`string`)
* **replicationStore** (`null`,`string`)
   - default value: `null`
* **replicationStoreKind** (`string`)
   - default value: `"ClusterSecretStore"`

Describe generated credentials for `newTenant`. A replication store is needed when the app Secret lives outside the database namespace.

Example:

```jsonnet
local cnpg = import 'labsonnet/helpers/cnpg.libsonnet';
{
  credentials: cnpg.generatedCredentials('postgres-password', 'postgres-credentials'),
}
```

### fn newCluster

```jsonnet
newCluster(name)
```

PARAMETERS:

* **name** (`string`)

Start a Cluster builder. Defaults are namespace `default`, one instance, and `5Gi` storage. The image and storage class are left to the operator and cluster defaults. Pods use required anti-affinity across host names by default.

Add options with `withNamespace`, `withInstances`, `withStorageSize`, `withStorageClass`, `withImage`, `withAffinity`, `withRole`, `withExtension`, `withSharedPreloadLibraries`, or `withClusterSpec`. Tanka finds the Cluster resource inside the builder.

Example:

```jsonnet
local cnpg = import 'labsonnet/helpers/cnpg.libsonnet';
local affinity = import 'labsonnet/helpers/affinity.libsonnet';
{
  cluster:
    cnpg.newCluster('postgres')
    + cnpg.withNamespace('database')
    + cnpg.withInstances(3)
    + cnpg.withStorageSize('50Gi')
    + cnpg.withAffinity(affinity.requireNodeLabel('nodepool', ['database'])),
}
```

### fn newCredentialInfrastructure

```jsonnet
newCredentialInfrastructure(name, namespace="default", generatorName=null, passwordSpec={}, serviceAccountName=null, serviceAccountNamespace)
```

PARAMETERS:

* **name** (`string`)
* **namespace** (`string`)
   - default value: `"default"`
* **generatorName** (`null`,`string`)
   - default value: `null`
* **passwordSpec** (`object`)
   - default value: `{}`
* **serviceAccountName** (`null`,`string`)
   - default value: `null`
* **serviceAccountNamespace** (`string`)

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

### fn newCredentialReadGrant

```jsonnet
newCredentialReadGrant(role, serviceAccountName=null, serviceAccountNamespace)
```

PARAMETERS:

* **role** (`object`)
* **serviceAccountName** (`null`,`string`)
   - default value: `null`
* **serviceAccountNamespace** (`string`)

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

### fn newDatabase

```jsonnet
newDatabase(name, clusterName, ownerName, namespace="default", reclaimPolicy="retain", spec={}, resourceName=null)
```

PARAMETERS:

* **name** (`string`)
* **clusterName** (`string`)
* **ownerName** (`string`)
* **namespace** (`string`)
   - default value: `"default"`
* **reclaimPolicy** (`string`)
   - default value: `"retain"`
* **spec** (`object`)
   - default value: `{}`
* **resourceName** (`null`,`string`)
   - default value: `null`

Create a Database resource. `ownerName` and `resourceName` default to `name`; `namespace` defaults to `default`; `reclaimPolicy` defaults to `retain`. Set `reclaimPolicy=null` to omit it.

Example:

```jsonnet
local cnpg = import 'labsonnet/helpers/cnpg.libsonnet';
{
  database: cnpg.newDatabase('catalog', 'postgres', namespace='database'),
}
```

### fn newRole

```jsonnet
newRole(name, clusterName, secretName, namespace="default", roleName, reclaimPolicy="retain", spec={})
```

PARAMETERS:

* **name** (`string`)
* **clusterName** (`string`)
* **secretName** (`string`)
* **namespace** (`string`)
   - default value: `"default"`
* **roleName** (`string`)
* **reclaimPolicy** (`string`)
   - default value: `"retain"`
* **spec** (`object`)
   - default value: `{}`

Create a DatabaseRole with login enabled and a password Secret reference. Requires CloudNativePG 1.30 or later, which provides the DatabaseRole CRD. `roleName` defaults to `name`; `namespace` defaults to `default`; `reclaimPolicy` defaults to `retain`.

Example:

```jsonnet
local cnpg = import 'labsonnet/helpers/cnpg.libsonnet';
{
  role: cnpg.newRole('catalog', 'postgres', 'catalog-postgres', namespace='database'),
}
```

### fn newTenant

```jsonnet
newTenant(name, clusterName, clusterNamespace, appNamespace, credentials=null, resourceName=null, secretName=null, databaseSpec={}, roleSpec={})
```

PARAMETERS:

* **name** (`string`)
* **clusterName** (`string`)
* **clusterNamespace** (`string`)
* **appNamespace** (`string`)
* **credentials** (`null`,`object`)
   - default value: `null`
* **resourceName** (`null`,`string`)
   - default value: `null`
* **secretName** (`null`,`string`)
   - default value: `null`
* **databaseSpec** (`object`)
   - default value: `{}`
* **roleSpec** (`object`)
   - default value: `{}`

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

### fn remoteCredentials

```jsonnet
remoteCredentials(store, remoteKey, storeKind="ClusterSecretStore", property=null)
```

PARAMETERS:

* **store** (`string`)
* **remoteKey** (`string`)
* **storeKind** (`string`)
   - default value: `"ClusterSecretStore"`
* **property** (`null`,`string`)
   - default value: `null`

Describe credentials that an ExternalSecret reads from a SecretStore. Use this object as the `credentials` value for `newTenant`.

Example:

```jsonnet
local cnpg = import 'labsonnet/helpers/cnpg.libsonnet';
{
  credentials: cnpg.remoteCredentials('app-secrets', 'catalog-password'),
}
```

### fn withAffinity

```jsonnet
withAffinity(affinity)
```

PARAMETERS:

* **affinity** (`object`)

Set node affinity. Pass either a node affinity object or an object containing `nodeAffinity`.

Example:

```jsonnet
local cnpg = import 'labsonnet/helpers/cnpg.libsonnet';
local affinity = import 'labsonnet/helpers/affinity.libsonnet';
{
  cluster:
    cnpg.newCluster('postgres')
    + cnpg.withAffinity(affinity.requireNodeLabel('nodepool', ['database'])),
}
```

### fn withClusterSpec

```jsonnet
withClusterSpec(spec)
```

PARAMETERS:

* **spec** (`object`)

Deep-merge extra fields into the Cluster spec. These fields override generated values when they conflict.

Example:

```jsonnet
local cnpg = import 'labsonnet/helpers/cnpg.libsonnet';
{
  cluster:
    cnpg.newCluster('postgres')
    + cnpg.withClusterSpec({ monitoring: { enablePodMonitor: true } }),
}
```

### fn withExtension

```jsonnet
withExtension(name, image=null, config={})
```

PARAMETERS:

* **name** (`string`)
* **image** (`null`,`string`)
   - default value: `null`
* **config** (`object`)
   - default value: `{}`

Add a PostgreSQL extension. If `image` is null, the Cluster spec must provide an `imageCatalogRef`.

Example:

```jsonnet
local cnpg = import 'labsonnet/helpers/cnpg.libsonnet';
{
  cluster:
    cnpg.newCluster('postgres')
    + cnpg.withExtension('vector', 'ghcr.io/example/vector:1'),
}
```

### fn withImage

```jsonnet
withImage(image)
```

PARAMETERS:

* **image** (`string`)

Set the PostgreSQL container image. It is omitted by default.

Example:

```jsonnet
local cnpg = import 'labsonnet/helpers/cnpg.libsonnet';
{
  cluster:
    cnpg.newCluster('postgres')
    + cnpg.withImage('ghcr.io/example/postgres:18'),
}
```

### fn withInstances

```jsonnet
withInstances(instances)
```

PARAMETERS:

* **instances** (`number`)

Set the desired number of PostgreSQL instances. The default is `1`.

Example:

```jsonnet
local cnpg = import 'labsonnet/helpers/cnpg.libsonnet';
{
  cluster:
    cnpg.newCluster('postgres')
    + cnpg.withInstances(3),
}
```

### fn withNamespace

```jsonnet
withNamespace(namespace)
```

PARAMETERS:

* **namespace** (`string`)

Set the Cluster namespace. The default is `default`.

Example:

```jsonnet
local cnpg = import 'labsonnet/helpers/cnpg.libsonnet';
{
  cluster:
    cnpg.newCluster('postgres')
    + cnpg.withNamespace('database'),
}
```

### fn withRole

```jsonnet
withRole(name, secretName)
```

PARAMETERS:

* **name** (`string`)
* **secretName** (`string`)

Add a managed login role backed by the named password Secret.

Example:

```jsonnet
local cnpg = import 'labsonnet/helpers/cnpg.libsonnet';
{
  cluster:
    cnpg.newCluster('postgres')
    + cnpg.withRole('app', 'app-postgres'),
}
```

### fn withSharedPreloadLibraries

```jsonnet
withSharedPreloadLibraries(libraries)
```

PARAMETERS:

* **libraries** (`array`)

Add PostgreSQL shared preload libraries. Duplicate names are removed.

Example:

```jsonnet
local cnpg = import 'labsonnet/helpers/cnpg.libsonnet';
{
  cluster:
    cnpg.newCluster('postgres')
    + cnpg.withSharedPreloadLibraries(['pg_stat_statements']),
}
```

### fn withStorageClass

```jsonnet
withStorageClass(storageClass)
```

PARAMETERS:

* **storageClass** (`string`)

Set the storage class. It is omitted by default.

Example:

```jsonnet
local cnpg = import 'labsonnet/helpers/cnpg.libsonnet';
{
  cluster:
    cnpg.newCluster('postgres')
    + cnpg.withStorageClass('fast'),
}
```

### fn withStorageSize

```jsonnet
withStorageSize(size)
```

PARAMETERS:

* **size** (`string`)

Set the requested storage size for each instance. The default is `5Gi`.

Example:

```jsonnet
local cnpg = import 'labsonnet/helpers/cnpg.libsonnet';
{
  cluster:
    cnpg.newCluster('postgres')
    + cnpg.withStorageSize('50Gi'),
}
```
