// Standalone Ingress resource builder.

local k = import 'k.libsonnet';

local ingressK = k.networking.v1.ingress;
local ingressRule = k.networking.v1.ingressRule;
local httpIngressPath = k.networking.v1.httpIngressPath;

{
  new(name, namespace, serviceName, port, fqdn, clusterIssuer='letsencrypt-prod', className=null, annotations={})::
    ingressK.new(name)
    + ingressK.metadata.withNamespace(namespace)
    + ingressK.metadata.withAnnotations(
      { 'cert-manager.io/cluster-issuer': clusterIssuer } + annotations
    )
    + (if className != null then ingressK.spec.withIngressClassName(className) else {})
    + ingressK.spec.withRules([
      ingressRule.withHost(fqdn)
      + ingressRule.http.withPaths([
        httpIngressPath.withPath('/')
        + httpIngressPath.withPathType('ImplementationSpecific')
        + httpIngressPath.backend.service.withName(serviceName)
        + httpIngressPath.backend.service.port.withNumber(port),
      ]),
    ])
    + ingressK.spec.withTls([{
      hosts: [fqdn],
      secretName: '%s-cert' % std.strReplace(fqdn, '.', '-'),
    }]),
}
