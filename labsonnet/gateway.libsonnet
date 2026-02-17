// Gateway API route builder — dispatches to helpers/gateway.libsonnet.
// Exports meta (routing metadata) and routeKeys.

local gatewayHelper = import 'helpers/gateway.libsonnet';


local routeTypes = {
  httpRoute: { layer: 'L7', protocol: 'TCP' },
  grpcRoute: { layer: 'L7', protocol: 'TCP' },
  tcpRoute: { layer: 'L4', protocol: 'TCP' },
  udpRoute: { layer: 'L4', protocol: 'UDP' },
};

{

  meta:: {
    [k]: routeTypes[k]
    for k in std.objectFields(routeTypes)
  },


  routeKeys:: std.objectFields(routeTypes),


  build(routeKey, resourceName, serviceName, namespace, fqdn, port, routeCfg)::
    local gateway = if std.objectHas(routeCfg, 'gateway') then routeCfg.gateway else {};
    local annotations = if std.objectHas(routeCfg, 'annotations') then routeCfg.annotations else {};

    if routeKey == 'httpRoute' then
      local matches = if std.objectHas(routeCfg, 'matches') then routeCfg.matches else null;
      gatewayHelper.httpRoute(resourceName, namespace, serviceName, port, fqdn, gateway, matches, annotations)
    else if routeKey == 'grpcRoute' then
      gatewayHelper.grpcRoute(resourceName, namespace, serviceName, port, fqdn, gateway, annotations)
    else if routeKey == 'tcpRoute' then
      gatewayHelper.tcpRoute(resourceName, namespace, serviceName, port, gateway, annotations)
    else if routeKey == 'udpRoute' then
      gatewayHelper.udpRoute(resourceName, namespace, serviceName, port, gateway, annotations)
    else
      error "labsonnet gateway: unknown route type '%s'" % routeKey,
}
