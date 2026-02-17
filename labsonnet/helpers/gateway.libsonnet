// Standalone Gateway API route builders.
// gateway parameter: { name, namespace, sectionName }
// L7 routes default sectionName to 'https'; L4 routes require it.

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

  httpRoute(name, namespace, serviceName, port, fqdn, gateway, matches=null, annotations={})::
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
      + rt.rule.withMatches(effectiveMatches);
    buildRoute(rt, name, namespace, serviceName, port, gw, [fqdn], rule, annotations),


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
