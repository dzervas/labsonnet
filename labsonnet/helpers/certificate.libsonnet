// Standalone cert-manager Certificate resource builder.

local d = import 'github.com/jsonnet-libs/docsonnet/doc-util/main.libsonnet';

{
  '#':: d.pkg(
    name='certificate',
    url='https://github.com/dzervas/labsonnet',
    filename=std.thisFile,
    version='main',
    help='Create cert-manager Certificate resources. Requires cert-manager and its Certificate CRD.',
  ) + d.package.withInstallTemplate('jb install github.com/dzervas/labsonnet/labsonnet@main')
    + d.package.withUsageTemplate("local certificate = import 'labsonnet/helpers/certificate.libsonnet'"),

  '#new':: d.fn(|||
    Create a Certificate. `issuerRef` selects the cert-manager Issuer or ClusterIssuer. Extra `spec` fields are merged over `secretName` and `issuerRef`.

    Example:

    ```jsonnet
    local c = import 'labsonnet/helpers/certificate.libsonnet';
    {
      certificate: c.new('api-cert', 'apps', 'api-tls',
        { name: 'letsencrypt', kind: 'ClusterIssuer' },
        { dnsNames: ['api.example.test'] }),
    }
    ```
  |||, [
    d.arg('name', d.T.string),
    d.arg('namespace', d.T.string),
    d.arg('secretName', d.T.string),
    d.arg('issuerRef', d.T.object),
    d.arg('spec', d.T.object, {}),
  ]),

  new(name, namespace, secretName, issuerRef, spec={})::
    {
      apiVersion: 'cert-manager.io/v1',
      kind: 'Certificate',
      metadata: { name: name, namespace: namespace },
      spec: {
        secretName: secretName,
        issuerRef: issuerRef,
      } + spec,
    },
}
