// Standalone Gateway API route builders.
// gateway parameter: { name, namespace, sectionName }
// L7 routes default sectionName to 'https'; L4 routes require it.

local d = import 'github.com/jsonnet-libs/docsonnet/doc-util/main.libsonnet';

local gatewayApi = import 'gateway-api.libsonnet';


local httpRouteLib = gatewayApi.gateway.v1.httpRoute;
local grpcRouteLib = gatewayApi.gateway.v1.grpcRoute;
local tcpRouteLib = gatewayApi.gateway.v1alpha2.tcpRoute;
local udpRouteLib = gatewayApi.gateway.v1alpha2.udpRoute;


local buildRoute(rt, name, namespace, serviceName, port, gateway, hostnames, rule, annotations) =
  rt.route.new(name)
  + rt.route.metadata.withNamespace(namespace)
  + (if std.length(annotations) > 0
     then rt.route.metadata.withAnnotations(annotations)
     else {})
  + (if std.length(hostnames) > 0
     then rt.route.spec.withHostnames(hostnames)
     else {})
  + rt.route.spec.withParentRefs([
    rt.parentRef.withName(gateway.name)
    + rt.parentRef.withNamespace(gateway.namespace)
    + rt.parentRef.withSectionName(gateway.sectionName),
  ])
  + rt.route.spec.withRules([rule]);


{

  '#':: d.pkg(
    name='gateway',
    url='https://github.com/dzervas/labsonnet',
    filename=std.thisFile,
    version='main',
    help='Create Gateway API HTTP, gRPC, TCP, and UDP routes to Services. The matching Gateway API route CRDs must be installed.',
  ) + d.package.withInstallTemplate('jb install github.com/dzervas/labsonnet/labsonnet@main')
    + d.package.withUsageTemplate("local gateway = import 'labsonnet/helpers/gateway.libsonnet'"),

  '#httpRoute':: d.fn(|||
    Create an HTTPRoute to a Service. The route uses the `https` listener by default, matches `/` by default, and always sets the supplied host name.

    Example:

    ```jsonnet
    local g = import 'labsonnet/helpers/gateway.libsonnet';
    {
      httpRoute: g.httpRoute('api', 'apps', 'api', 8080, 'api.example.test',
        { name: 'public', namespace: 'gateway' }),
    }
    ```
  |||, [
    d.arg('name', d.T.string),
    d.arg('namespace', d.T.string),
    d.arg('serviceName', d.T.string),
    d.arg('port', d.T.number),
    d.arg('fqdn', d.T.string),
    d.arg('gateway', d.T.object),
    d.argument.fromSchema('matches', { type: ['array', 'null'], default: null }),
    d.arg('annotations', d.T.object, {}),
    d.arg('filters', d.T.array, []),
  ]),
  httpRoute(name, namespace, serviceName, port, fqdn, gateway, matches=null, annotations={}, filters=[])::
    local gw = { sectionName: 'https' } + gateway;
    local rt = {
      route: httpRouteLib,
      parentRef: httpRouteLib.spec.parentRefs,
      rule: httpRouteLib.spec.rules,
      backendRef: httpRouteLib.spec.rules.backendRefs,
      match: httpRouteLib.spec.rules.matches,
    };
    local defaultMatches = [
      rt.match.path.withType('PathPrefix')
      + rt.match.path.withValue('/'),
    ];
    local effectiveMatches = if matches != null then matches else defaultMatches;
    local rule =
      rt.rule.withBackendRefs([
        rt.backendRef.withName(serviceName)
        + rt.backendRef.withPort(port),
      ])
      + rt.rule.withMatches(effectiveMatches)
      + rt.rule.withFilters(filters);
    buildRoute(rt, name, namespace, serviceName, port, gw, [fqdn], rule, annotations),


  '#grpcRoute':: d.fn(|||
    Create a GRPCRoute to a Service. The route uses the `https` listener by default and sets the supplied host name.

    Example:

    ```jsonnet
    local g = import 'labsonnet/helpers/gateway.libsonnet';
    {
      grpcRoute: g.grpcRoute('greeter', 'apps', 'greeter', 9000, 'grpc.example.test',
        { name: 'public', namespace: 'gateway' }),
    }
    ```
  |||, [
    d.arg('name', d.T.string),
    d.arg('namespace', d.T.string),
    d.arg('serviceName', d.T.string),
    d.arg('port', d.T.number),
    d.arg('fqdn', d.T.string),
    d.arg('gateway', d.T.object),
    d.arg('annotations', d.T.object, {}),
  ]),
  grpcRoute(name, namespace, serviceName, port, fqdn, gateway, annotations={})::
    local gw = { sectionName: 'https' } + gateway;
    local rt = {
      route: grpcRouteLib,
      parentRef: grpcRouteLib.spec.parentRefs,
      rule: grpcRouteLib.spec.rules,
      backendRef: grpcRouteLib.spec.rules.backendRefs,
    };
    local rule =
      rt.rule.withBackendRefs([
        rt.backendRef.withName(serviceName)
        + rt.backendRef.withPort(port),
      ]);
    buildRoute(rt, name, namespace, serviceName, port, gw, [fqdn], rule, annotations),


  '#tcpRoute':: d.fn(|||
    Create a TCPRoute to a Service. `gateway` must include `name`, `namespace`, and `sectionName` for the TCP listener.

    Example:

    ```jsonnet
    local g = import 'labsonnet/helpers/gateway.libsonnet';
    {
      tcpRoute: g.tcpRoute('database', 'apps', 'database', 5432,
        { name: 'public', namespace: 'gateway', sectionName: 'tcp' }),
    }
    ```
  |||, [
    d.arg('name', d.T.string),
    d.arg('namespace', d.T.string),
    d.arg('serviceName', d.T.string),
    d.arg('port', d.T.number),
    d.arg('gateway', d.T.object),
    d.arg('annotations', d.T.object, {}),
  ]),
  tcpRoute(name, namespace, serviceName, port, gateway, annotations={})::
    assert std.objectHas(gateway, 'sectionName') :
           "tcpRoute '%s': gateway.sectionName is required for L4 routes" % name;
    local rt = {
      route: tcpRouteLib,
      parentRef: tcpRouteLib.spec.parentRefs,
      rule: tcpRouteLib.spec.rules,
      backendRef: tcpRouteLib.spec.rules.backendRefs,
    };
    local rule =
      rt.rule.withBackendRefs([
        rt.backendRef.withName(serviceName)
        + rt.backendRef.withPort(port),
      ]);
    buildRoute(rt, name, namespace, serviceName, port, gateway, [], rule, annotations),


  '#udpRoute':: d.fn(|||
    Create a UDPRoute to a Service. `gateway` must include `name`, `namespace`, and `sectionName` for the UDP listener.

    Example:

    ```jsonnet
    local g = import 'labsonnet/helpers/gateway.libsonnet';
    {
      udpRoute: g.udpRoute('dns', 'apps', 'dns', 53,
        { name: 'public', namespace: 'gateway', sectionName: 'udp' }),
    }
    ```
  |||, [
    d.arg('name', d.T.string),
    d.arg('namespace', d.T.string),
    d.arg('serviceName', d.T.string),
    d.arg('port', d.T.number),
    d.arg('gateway', d.T.object),
    d.arg('annotations', d.T.object, {}),
  ]),
  udpRoute(name, namespace, serviceName, port, gateway, annotations={})::
    assert std.objectHas(gateway, 'sectionName') :
           "udpRoute '%s': gateway.sectionName is required for L4 routes" % name;
    local rt = {
      route: udpRouteLib,
      parentRef: udpRouteLib.spec.parentRefs,
      rule: udpRouteLib.spec.rules,
      backendRef: udpRouteLib.spec.rules.backendRefs,
    };
    local rule =
      rt.rule.withBackendRefs([
        rt.backendRef.withName(serviceName)
        + rt.backendRef.withPort(port),
      ]);
    buildRoute(rt, name, namespace, serviceName, port, gateway, [], rule, annotations),
}
