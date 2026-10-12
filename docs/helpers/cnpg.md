# cnpg

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
* [`fn newCredentialInfrastructure(name, namespace="default", generatorName=null, passwordSpec={}, serviceAccountName=null, serviceAccountNamespace)`](#fn-newcredentialinfrastructure)
* [`fn newCredentialReadGrant(role, serviceAccountName=null, serviceAccountNamespace)`](#fn-newcredentialreadgrant)
* [`fn newDatabase(name, clusterName, ownerName, namespace="default", reclaimPolicy="retain", spec={}, resourceName=null)`](#fn-newdatabase)
* [`fn newRole(name, clusterName, secretName, namespace="default", roleName, reclaimPolicy="retain", spec={})`](#fn-newrole)
* [`fn newTenant(name, clusterName, clusterNamespace, appNamespace, credentials=null, resourceName=null, secretName=null, databaseSpec={}, roleSpec={})`](#fn-newtenant)
* [`fn remoteCredentials(store, remoteKey, storeKind="ClusterSecretStore", property=null)`](#fn-remotecredentials)

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
