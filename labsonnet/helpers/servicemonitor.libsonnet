// Standalone ServiceMonitor resource builder (monitoring.coreos.com/v1).
// Compatible with Prometheus Operator and VictoriaMetrics Operator (auto-discovery).

local d = import 'github.com/jsonnet-libs/docsonnet/doc-util/main.libsonnet';

{
  '#':: d.pkg(
    name='servicemonitor',
    url='https://github.com/dzervas/labsonnet',
    filename=std.thisFile,
    version='main',
    help='Create a ServiceMonitor that selects labeled Services and scrapes one named port. Requires the ServiceMonitor CRD from a monitoring operator.',
  ) + d.package.withInstallTemplate('jb install github.com/dzervas/labsonnet/labsonnet@main')
    + d.package.withUsageTemplate("local servicemonitor = import 'labsonnet/helpers/servicemonitor.libsonnet'"),

  '#new':: d.fn(|||
    Create a ServiceMonitor. `selector` becomes `spec.selector.matchLabels`; the selected Service must expose `portName`. The selector defaults to empty and matches all Services in the namespace.

    Example:

    ```jsonnet
    local sm = import 'labsonnet/helpers/servicemonitor.libsonnet';
    {
      serviceMonitor: sm.new('api', 'apps', selector={ app: 'api' }, labels={ team: 'platform' }),
    }
    ```
  |||, [
    d.arg('name', d.T.string),
    d.arg('namespace', d.T.string),
    d.arg('portName', d.T.string, 'metrics'),
    d.arg('path', d.T.string, '/metrics'),
    d.arg('interval', d.T.string, '30s'),
    d.arg('labels', d.T.object, {}),
    d.arg('selector', d.T.object, {}),
  ]),

  new(name, namespace, portName='metrics', path='/metrics', interval='30s', labels={}, selector={})::
    {
      apiVersion: 'monitoring.coreos.com/v1',
      kind: 'ServiceMonitor',
      metadata: {
        name: name,
        namespace: namespace,
        [if std.length(labels) > 0 then 'labels']: labels,
      },
      spec: {
        selector: { matchLabels: selector },
        endpoints: [{
          port: portName,
          path: path,
          interval: interval,
        }],
      },
    },
}
