// Generic Kubernetes affinity helpers: node affinity, pod anti-affinity, and workload mixins.

{

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


  combine(affinities):: std.foldl(
    function(acc, aff) std.mergePatch(acc, aff),
    affinities,
    {}
  ),


  withWorkloadAffinity(affinity)::
    { spec+: { template+: { spec+: { affinity: affinity } } } },
}
