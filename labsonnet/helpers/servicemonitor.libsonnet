// Standalone ServiceMonitor resource builder (monitoring.coreos.com/v1).
// Compatible with Prometheus Operator and VictoriaMetrics Operator (auto-discovery).

{
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
