// Standalone Ingress resource builder.

local d = import 'github.com/jsonnet-libs/docsonnet/doc-util/main.libsonnet';

local k = import 'k.libsonnet';

local ingressK = k.networking.v1.ingress;
local ingressRule = k.networking.v1.ingressRule;
local httpIngressPath = k.networking.v1.httpIngressPath;

{
  '#':: d.pkg(
    name='ingress',
    url='https://github.com/dzervas/labsonnet',
    filename=std.thisFile,
    version='main',
    help='Create an Ingress with one host, one service backend, and TLS. Requires cert-manager and an Ingress controller.',
  ) + d.package.withInstallTemplate('jb install github.com/dzervas/labsonnet/labsonnet@main')
    + d.package.withUsageTemplate("local ingress = import 'labsonnet/helpers/ingress.libsonnet'"),

  '#new':: d.fn(|||
    Create an HTTPS Ingress for a service. The certificate secret name is made from the host by replacing dots with dashes and adding `-cert`.

    Example:

    ```jsonnet
    local i = import 'labsonnet/helpers/ingress.libsonnet';
    {
      ingress: i.new('api', 'apps', 'api', 8080, 'api.example.test',
        className='traefik'),
    }
    ```
  |||, [
    d.arg('name', d.T.string),
    d.arg('namespace', d.T.string),
    d.arg('serviceName', d.T.string),
    d.arg('port', d.T.number),
    d.arg('fqdn', d.T.string),
    d.arg('clusterIssuer', d.T.string, 'letsencrypt-prod'),
    d.argument.fromSchema('className', { type: ['string', 'null'], default: null }),
    d.arg('annotations', d.T.object, {}),
  ]),

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
