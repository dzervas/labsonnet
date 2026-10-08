local d = import 'github.com/jsonnet-libs/docsonnet/doc-util/main.libsonnet';
local lab = import 'main.libsonnet';

// Include standalone helpers in the docs without changing the workload API.
local rendered = d.render(lab {
  downstream:: import 'docsonnet/downstream.libsonnet',
  helpers:: {
    affinity:: import 'labsonnet/helpers/affinity.libsonnet',
    certificate:: import 'labsonnet/helpers/certificate.libsonnet',
    cnpg:: import 'labsonnet/helpers/cnpg.libsonnet',
    externalsecret:: import 'labsonnet/helpers/externalsecret.libsonnet',
    gateway:: import 'labsonnet/helpers/gateway.libsonnet',
    imagevolume:: import 'labsonnet/helpers/imagevolume.libsonnet',
    ingress:: import 'labsonnet/helpers/ingress.libsonnet',
    pvc:: import 'labsonnet/helpers/pvc.libsonnet',
    servicemonitor:: import 'labsonnet/helpers/servicemonitor.libsonnet',
  },
});

// The Jsonnet CLI adds a final newline when writing each string with -S.
{ [path]: std.stripChars(rendered[path], '\n') for path in std.objectFields(rendered) }
