# ingress

Create an Ingress with one host, one service backend, and TLS. Requires cert-manager and an Ingress controller.
## Install

```
jb install github.com/dzervas/labsonnet/labsonnet@main
```

## Usage

```jsonnet
local ingress = import 'labsonnet/helpers/ingress.libsonnet'
```


## Index

* [`fn new(name, namespace, serviceName, port, fqdn, clusterIssuer="letsencrypt-prod", className=null, annotations={})`](#fn-new)

## Fields

### fn new

```jsonnet
new(name, namespace, serviceName, port, fqdn, clusterIssuer="letsencrypt-prod", className=null, annotations={})
```

PARAMETERS:

* **name** (`string`)
* **namespace** (`string`)
* **serviceName** (`string`)
* **port** (`number`)
* **fqdn** (`string`)
* **clusterIssuer** (`string`)
   - default value: `"letsencrypt-prod"`
* **className** (`null`,`string`)
   - default value: `null`
* **annotations** (`object`)
   - default value: `{}`

Create an HTTPS Ingress for a service. The certificate secret name is made from the host by replacing dots with dashes and adding `-cert`.

Example:

```jsonnet
local i = import 'labsonnet/helpers/ingress.libsonnet';
{
  ingress: i.new('api', 'apps', 'api', 8080, 'api.example.test',
    className='traefik'),
}
```
