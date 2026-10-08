# pvc

Create PersistentVolumeClaim resources.
## Install

```
jb install github.com/dzervas/labsonnet/labsonnet@main
```

## Usage

```jsonnet
local pvc = import 'labsonnet/helpers/pvc.libsonnet'
```


## Index

* [`fn new(name, namespace, size, accessModes=["ReadWriteOnce"], storageClassName=null, labels={})`](#fn-new)

## Fields

### fn new

```jsonnet
new(name, namespace, size, accessModes=["ReadWriteOnce"], storageClassName=null, labels={})
```

PARAMETERS:

* **name** (`string`)
* **namespace** (`string`)
* **size** (`string`)
* **accessModes** (`array`)
   - default value: `["ReadWriteOnce"]`
* **storageClassName** (`null`,`string`)
   - default value: `null`
* **labels** (`object`)
   - default value: `{}`

Create a PersistentVolumeClaim. The storage class is omitted when null, so Kubernetes may use its default class. A named class must have a provisioner in the cluster.

Example:

```jsonnet
local p = import 'labsonnet/helpers/pvc.libsonnet';
{
  pvc: p.new('media', 'apps', '20Gi', storageClassName='fast',
    labels={ app: 'media' }),
}
```
