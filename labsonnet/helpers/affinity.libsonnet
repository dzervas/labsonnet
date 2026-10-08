// Generic Kubernetes affinity helpers: node affinity, pod anti-affinity, and workload mixins.

local d = import 'github.com/jsonnet-libs/docsonnet/doc-util/main.libsonnet';

{
  '#':: d.pkg(
    name='affinity',
    url='https://github.com/dzervas/labsonnet',
    filename=std.thisFile,
    version='main',
    help=|||
      Build node placement and pod spreading rules. Pass the result to
      `lab.withAffinity`, or use `withWorkloadAffinity` on a Kubernetes workload.
    |||,
  ) + d.package.withInstallTemplate('jb install github.com/dzervas/labsonnet/labsonnet@main')
    + d.package.withUsageTemplate("local affinity = import 'labsonnet/helpers/affinity.libsonnet'"),

  '#requireNodeLabel':: d.fn(|||
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
  |||, [d.arg('key', d.T.string), d.arg('values', d.T.array)]),

  requireNodeLabel(key, values):: {
    nodeAffinity: {
      requiredDuringSchedulingIgnoredDuringExecution: {
        nodeSelectorTerms: [{
          matchExpressions: [{
            key: key,
            operator: 'In',
            values: values,
          }],
        }],
      },
    },
  },


  '#avoidNodeLabel':: d.fn(|||
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
  |||, [d.arg('key', d.T.string), d.arg('values', d.T.array)]),

  avoidNodeLabel(key, values):: {
    nodeAffinity: {
      requiredDuringSchedulingIgnoredDuringExecution: {
        nodeSelectorTerms: [{
          matchExpressions: [{
            key: key,
            operator: 'NotIn',
            values: values,
          }],
        }],
      },
    },
  },


  '#preferNodeLabel':: d.fn(|||
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
  |||, [d.arg('key', d.T.string), d.arg('values', d.T.array), d.arg('weight', d.T.number, 100)]),

  preferNodeLabel(key, values, weight=100):: {
    nodeAffinity: {
      preferredDuringSchedulingIgnoredDuringExecution: [{
        weight: weight,
        preference: {
          matchExpressions: [{
            key: key,
            operator: 'In',
            values: values,
          }],
        },
      }],
    },
  },


  '#spreadAcrossNodes':: d.fn(|||
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
  |||, [
    d.arg('labelSelector', d.T.object),
    d.arg('topologyKey', d.T.string, 'kubernetes.io/hostname'),
    d.arg('weight', d.T.number, 100),
  ]),

  spreadAcrossNodes(labelSelector, topologyKey='kubernetes.io/hostname', weight=100):: {
    podAntiAffinity: {
      preferredDuringSchedulingIgnoredDuringExecution: [{
        weight: weight,
        podAffinityTerm: {
          labelSelector: {
            matchLabels: labelSelector,
          },
          topologyKey: topologyKey,
        },
      }],
    },
  },


  '#requireSpreadAcrossNodes':: d.fn(|||
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
  |||, [
    d.arg('labelSelector', d.T.object),
    d.arg('topologyKey', d.T.string, 'kubernetes.io/hostname'),
  ]),

  requireSpreadAcrossNodes(labelSelector, topologyKey='kubernetes.io/hostname'):: {
    podAntiAffinity: {
      requiredDuringSchedulingIgnoredDuringExecution: [{
        labelSelector: {
          matchLabels: labelSelector,
        },
        topologyKey: topologyKey,
      }],
    },
  },


  '#combine':: d.fn(|||
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
  |||, [d.arg('affinities', d.T.array)]),

  combine(affinities):: std.foldl(
    function(acc, aff) std.mergePatch(acc, aff),
    affinities,
    {}
  ),


  '#withWorkloadAffinity':: d.fn(|||
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
  |||, [d.arg('affinity', d.T.object)]),

  withWorkloadAffinity(affinity)::
    { spec+: { template+: { spec+: { affinity: affinity } } } },
}
