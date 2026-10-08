local lab = import '../../labsonnet/main.libsonnet';

{
  routes:
    lab.new('router', 'example/router:v1')
    + lab.withFqdn('default.example.test')
    + lab.withPort({
      port: 8080,
      name: 'public',
      httpRoute: {
        gateway: { name: 'public-gateway', namespace: 'network' },
      },
    })
    + lab.withPort({
      port: 8080,
      name: 'private',
      httpRoute: {
        fqdn: 'private.example.test',
        gateway: { name: 'private-gateway', namespace: 'vpn' },
      },
    })
    + lab.withPort({
      port: 5353,
      name: 'dns',
      udpRoute: { gateway: { name: 'dns-gateway', namespace: 'network', sectionName: 'dns' } },
    })
    + lab.withPort({
      port: 50051,
      name: 'grpc',
      grpcRoute: { gateway: { name: 'public-gateway', namespace: 'network' } },
    })
    + lab.withPort({
      port: 5432,
      name: 'database',
      tcpRoute: { gateway: { name: 'public-gateway', namespace: 'network', sectionName: 'postgres' } },
    }),

  invalidMultipleRoutingTypes:
    lab.new('invalid-routes', 'example/app:v1')
    + lab.withPort({
      port: 8080,
      httpRoute: {},
      grpcRoute: {},
    }),

  invalidProtocolConflict:
    lab.new('invalid-protocol', 'example/app:v1')
    + lab.withFqdn('app.example.test')
    + lab.withPort({
      port: 8080,
      protocol: 'UDP',
      httpRoute: { gateway: { name: 'edge', namespace: 'network' } },
    }),

  separate_exposure:
    lab.new('database', 'example:v1') + lab.withType('StatefulSet')
    + lab.withHeadlessService('peer-discovery', publishNotReadyAddresses=false)
    + lab.withPort({ port: 8080, name: 'web' })
    + lab.withHeadlessPort({ port: 5432, name: 'peer' }),
  valid_monitor:
    lab.new('monitor', 'example:v1')
    + lab.withPort({ port: 8080, name: 'web' })
    + lab.withPort({ port: 8080, name: 'alias' })
    + lab.withServiceMonitor('web'),
  discarded_alias_monitor:
    lab.new('monitor', 'example:v1')
    + lab.withPort({ port: 8080, name: 'web' })
    + lab.withPort({ port: 8080, name: 'metrics' })
    + lab.withServiceMonitor('metrics'),
  headless_only_monitor:
    lab.new('monitor', 'example:v1') + lab.withHeadlessService()
    + lab.withPort({ port: 8080, name: 'web' })
    + lab.withHeadlessPort({ port: 9090, name: 'metrics' })
    + lab.withServiceMonitor('metrics'),
}
