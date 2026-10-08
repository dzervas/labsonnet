# certificate

Create cert-manager Certificate resources. Requires cert-manager and its Certificate CRD.
## Install

```
jb install github.com/dzervas/labsonnet/labsonnet@main
```

## Usage

```jsonnet
local certificate = import 'labsonnet/helpers/certificate.libsonnet'
```


## Index

* [`fn new(name, namespace, secretName, issuerRef, spec={})`](#fn-new)

## Fields

### fn new

```jsonnet
new(name, namespace, secretName, issuerRef, spec={})
```

PARAMETERS:

* **name** (`string`)
* **namespace** (`string`)
* **secretName** (`string`)
* **issuerRef** (`object`)
* **spec** (`object`)
   - default value: `{}`

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
