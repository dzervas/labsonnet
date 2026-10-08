# externalsecret

Build ExternalSecret, password generator, Kubernetes replication store, and narrow Secret read access resources. Requires the External Secrets Operator CRDs.
## Install

```
jb install github.com/dzervas/labsonnet/labsonnet@main
```

## Usage

```jsonnet
local externalsecret = import 'labsonnet/helpers/externalsecret.libsonnet'
```


## Index

* [`fn new(name, namespace, storeName=null, storeKind="ClusterSecretStore", dataFrom=[], data=[], refreshInterval=null, refreshPolicy=null, creationPolicy=null, deletionPolicy=null)`](#fn-new)
* [`fn newKubernetesReplicationStore(name, namespace, serviceAccountName=null, serviceAccountNamespace)`](#fn-newkubernetesreplicationstore)
* [`fn newPasswordGenerator(name, namespace, spec={})`](#fn-newpasswordgenerator)
* [`fn newSecretReadGrant(name, namespace, secretNames, serviceAccountName, serviceAccountNamespace)`](#fn-newsecretreadgrant)
* [`fn withSecretLabels(labels)`](#fn-withsecretlabels)

## Fields

### fn new

```jsonnet
new(name, namespace, storeName=null, storeKind="ClusterSecretStore", dataFrom=[], data=[], refreshInterval=null, refreshPolicy=null, creationPolicy=null, deletionPolicy=null)
```

PARAMETERS:

* **name** (`string`)
* **namespace** (`string`)
* **storeName** (`null`,`string`)
   - default value: `null`
* **storeKind** (`string`)
   - default value: `"ClusterSecretStore"`
* **dataFrom** (`array`)
   - default value: `[]`
* **data** (`array`)
   - default value: `[]`
* **refreshInterval** (`null`,`string`)
   - default value: `null`
* **refreshPolicy** (`null`,`string`)
   - default value: `null`
* **creationPolicy** (`null`,`string`)
   - default value: `null`
* **deletionPolicy** (`null`,`string`)
   - default value: `null`

Create an ExternalSecret. `dataFrom` and `data` are omitted when empty. Store and refresh or target policies are omitted when null.

Example:

```jsonnet
local e = import 'labsonnet/helpers/externalsecret.libsonnet';
{
  secret: e.new('api-token', 'apps', 'app-secrets',
    dataFrom=[{ extract: { key: 'api-token' } }]),
}
```

### fn newKubernetesReplicationStore

```jsonnet
newKubernetesReplicationStore(name, namespace, serviceAccountName=null, serviceAccountNamespace)
```

PARAMETERS:

* **name** (`string`)
* **namespace** (`string`)
* **serviceAccountName** (`null`,`string`)
   - default value: `null`
* **serviceAccountNamespace** (`string`)

Create a reader ServiceAccount and a ClusterSecretStore that reads Secrets from `namespace`. Add a separate Role and RoleBinding to grant access to specific Secrets.
The reader name defaults to `name`; the reader namespace defaults to the source `namespace`.

Example:

```jsonnet
local e = import 'labsonnet/helpers/externalsecret.libsonnet';
{
  replicationStore: e.newKubernetesReplicationStore('app-credentials', 'database'),
}
```

### fn newPasswordGenerator

```jsonnet
newPasswordGenerator(name, namespace, spec={})
```

PARAMETERS:

* **name** (`string`)
* **namespace** (`string`)
* **spec** (`object`)
   - default value: `{}`

Create an External Secrets Password generator in a namespace. Pass the generator's policy in `spec`.

Example:

```jsonnet
local e = import 'labsonnet/helpers/externalsecret.libsonnet';
{
  passwordGenerator: e.newPasswordGenerator('app-password', 'apps', { length: 40, allowRepeat: true }),
}
```

### fn newSecretReadGrant

```jsonnet
newSecretReadGrant(name, namespace, secretNames, serviceAccountName, serviceAccountNamespace)
```

PARAMETERS:

* **name** (`string`)
* **namespace** (`string`)
* **secretNames** (`array`)
* **serviceAccountName** (`string`)
* **serviceAccountNamespace** (`string`)

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

### fn withSecretLabels

```jsonnet
withSecretLabels(labels)
```

PARAMETERS:

* **labels** (`object`)

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
