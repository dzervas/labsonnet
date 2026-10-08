# affinity

Build node placement and pod spreading rules. Pass the result to
`lab.withAffinity`, or use `withWorkloadAffinity` on a Kubernetes workload.

## Install

```
jb install github.com/dzervas/labsonnet/labsonnet@main
```

## Usage

```jsonnet
local affinity = import 'labsonnet/helpers/affinity.libsonnet'
```


## Index

* [`fn avoidNodeLabel(key, values)`](#fn-avoidnodelabel)
* [`fn combine(affinities)`](#fn-combine)
* [`fn preferNodeLabel(key, values, weight=100)`](#fn-prefernodelabel)
* [`fn requireNodeLabel(key, values)`](#fn-requirenodelabel)
* [`fn requireSpreadAcrossNodes(labelSelector, topologyKey="kubernetes.io/hostname")`](#fn-requirespreadacrossnodes)
* [`fn spreadAcrossNodes(labelSelector, topologyKey="kubernetes.io/hostname", weight=100)`](#fn-spreadacrossnodes)
* [`fn withWorkloadAffinity(affinity)`](#fn-withworkloadaffinity)

## Fields

### fn avoidNodeLabel

```jsonnet
avoidNodeLabel(key, values)
```

PARAMETERS:

* **key** (`string`)
* **values** (`array`)

Require nodes to have none of the listed values for a label.

Example:

```jsonnet
local lab = import 'labsonnet/main.libsonnet';
local a = import 'labsonnet/helpers/affinity.libsonnet';
{
  worker:
    lab.new('worker', 'ghcr.io/example/worker:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withAffinity(a.avoidNodeLabel('nodepool', ['batch'])),
}
```

### fn combine

```jsonnet
combine(affinities)
```

PARAMETERS:

* **affinities** (`array`)

Merge affinity objects in order with `std.mergePatch`. Later values replace conflicting values, including arrays.

Example:

```jsonnet
local lab = import 'labsonnet/main.libsonnet';
local a = import 'labsonnet/helpers/affinity.libsonnet';
{
  worker:
    lab.new('worker', 'ghcr.io/example/worker:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withReplicas(3)
    + lab.withAffinity(a.combine([
      a.requireNodeLabel('nodepool', ['apps']),
      a.spreadAcrossNodes({ app: 'worker' }),
    ])),
}
```

### fn preferNodeLabel

```jsonnet
preferNodeLabel(key, values, weight=100)
```

PARAMETERS:

* **key** (`string`)
* **values** (`array`)
* **weight** (`number`)
   - default value: `100`

Prefer nodes with one of the listed label values. Kubernetes treats this as a scheduling preference.

Example:

```jsonnet
local lab = import 'labsonnet/main.libsonnet';
local a = import 'labsonnet/helpers/affinity.libsonnet';
{
  worker:
    lab.new('worker', 'ghcr.io/example/worker:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withAffinity(a.preferNodeLabel('nodepool', ['compute'], weight=80)),
}
```

### fn requireNodeLabel

```jsonnet
requireNodeLabel(key, values)
```

PARAMETERS:

* **key** (`string`)
* **values** (`array`)

Require nodes to have one of the listed values for a label.

Example:

```jsonnet
local lab = import 'labsonnet/main.libsonnet';
local a = import 'labsonnet/helpers/affinity.libsonnet';
{
  worker:
    lab.new('worker', 'ghcr.io/example/worker:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withAffinity(a.requireNodeLabel('nodepool', ['apps'])),
}
```

### fn requireSpreadAcrossNodes

```jsonnet
requireSpreadAcrossNodes(labelSelector, topologyKey="kubernetes.io/hostname")
```

PARAMETERS:

* **labelSelector** (`object`)
* **topologyKey** (`string`)
   - default value: `"kubernetes.io/hostname"`

Require matching pods to use different topology domains. Scheduling waits if no eligible domain is available.

Example:

```jsonnet
local lab = import 'labsonnet/main.libsonnet';
local a = import 'labsonnet/helpers/affinity.libsonnet';
{
  worker:
    lab.new('worker', 'ghcr.io/example/worker:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withReplicas(3)
    + lab.withAffinity(a.requireSpreadAcrossNodes({ app: 'worker' })),
}
```

### fn spreadAcrossNodes

```jsonnet
spreadAcrossNodes(labelSelector, topologyKey="kubernetes.io/hostname", weight=100)
```

PARAMETERS:

* **labelSelector** (`object`)
* **topologyKey** (`string`)
   - default value: `"kubernetes.io/hostname"`
* **weight** (`number`)
   - default value: `100`

Prefer placing matching pods on different topology domains. The default topology is one node per domain.

Example:

```jsonnet
local lab = import 'labsonnet/main.libsonnet';
local a = import 'labsonnet/helpers/affinity.libsonnet';
{
  worker:
    lab.new('worker', 'ghcr.io/example/worker:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withReplicas(3)
    + lab.withAffinity(a.spreadAcrossNodes({ app: 'worker' })),
}
```

### fn withWorkloadAffinity

```jsonnet
withWorkloadAffinity(affinity)
```

PARAMETERS:

* **affinity** (`object`)

Add affinity under `spec.template.spec.affinity` on a Deployment, StatefulSet, or similar workload.

Example:

```jsonnet
local k = import 'k.libsonnet';
local a = import 'labsonnet/helpers/affinity.libsonnet';
{
  worker:
    k.apps.v1.deployment.new('worker', replicas=1, containers=[
      k.core.v1.container.new('worker', 'ghcr.io/example/worker:1.0'),
    ])
    + a.withWorkloadAffinity(a.requireNodeLabel('nodepool', ['apps'])),
}
```
