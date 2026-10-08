# servicemonitor

Create a ServiceMonitor that selects labeled Services and scrapes one named port. Requires the ServiceMonitor CRD from a monitoring operator.
## Install

```
jb install github.com/dzervas/labsonnet/labsonnet@main
```

## Usage

```jsonnet
local servicemonitor = import 'labsonnet/helpers/servicemonitor.libsonnet'
```


## Index

* [`fn new(name, namespace, portName="metrics", path="/metrics", interval="30s", labels={}, selector={})`](#fn-new)

## Fields

### fn new

```jsonnet
new(name, namespace, portName="metrics", path="/metrics", interval="30s", labels={}, selector={})
```

PARAMETERS:

* **name** (`string`)
* **namespace** (`string`)
* **portName** (`string`)
   - default value: `"metrics"`
* **path** (`string`)
   - default value: `"/metrics"`
* **interval** (`string`)
   - default value: `"30s"`
* **labels** (`object`)
   - default value: `{}`
* **selector** (`object`)
   - default value: `{}`

Create a ServiceMonitor. `selector` becomes `spec.selector.matchLabels`; the selected Service must expose `portName`. The selector defaults to empty and matches all Services in the namespace.

Example:

```jsonnet
local sm = import 'labsonnet/helpers/servicemonitor.libsonnet';
{
  serviceMonitor: sm.new('api', 'apps', selector={ app: 'api' }, labels={ team: 'platform' }),
}
```
