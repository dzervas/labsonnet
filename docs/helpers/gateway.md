# gateway

Create Gateway API HTTP, gRPC, TCP, and UDP routes to Services. The matching Gateway API route CRDs must be installed.
## Install

```
jb install github.com/dzervas/labsonnet/labsonnet@main
```

## Usage

```jsonnet
local gateway = import 'labsonnet/helpers/gateway.libsonnet'
```


## Index

* [`fn grpcRoute(name, namespace, serviceName, port, fqdn, gateway, annotations={})`](#fn-grpcroute)
* [`fn httpRoute(name, namespace, serviceName, port, fqdn, gateway, matches=null, annotations={}, filters=[])`](#fn-httproute)
* [`fn tcpRoute(name, namespace, serviceName, port, gateway, annotations={})`](#fn-tcproute)
* [`fn udpRoute(name, namespace, serviceName, port, gateway, annotations={})`](#fn-udproute)

## Fields

### fn grpcRoute

```jsonnet
grpcRoute(name, namespace, serviceName, port, fqdn, gateway, annotations={})
```

PARAMETERS:

* **name** (`string`)
* **namespace** (`string`)
* **serviceName** (`string`)
* **port** (`number`)
* **fqdn** (`string`)
* **gateway** (`object`)
* **annotations** (`object`)
   - default value: `{}`

Create a GRPCRoute to a Service. The route uses the `https` listener by default and sets the supplied host name.

Example:

```jsonnet
local g = import 'labsonnet/helpers/gateway.libsonnet';
{
  grpcRoute: g.grpcRoute('greeter', 'apps', 'greeter', 9000, 'grpc.example.test',
    { name: 'public', namespace: 'gateway' }),
}
```

### fn httpRoute

```jsonnet
httpRoute(name, namespace, serviceName, port, fqdn, gateway, matches=null, annotations={}, filters=[])
```

PARAMETERS:

* **name** (`string`)
* **namespace** (`string`)
* **serviceName** (`string`)
* **port** (`number`)
* **fqdn** (`string`)
* **gateway** (`object`)
* **matches** (`array`,`null`)
   - default value: `null`
* **annotations** (`object`)
   - default value: `{}`
* **filters** (`array`)
   - default value: `[]`

Create an HTTPRoute to a Service. The route uses the `https` listener by default, matches `/` by default, and always sets the supplied host name.

Example:

```jsonnet
local g = import 'labsonnet/helpers/gateway.libsonnet';
{
  httpRoute: g.httpRoute('api', 'apps', 'api', 8080, 'api.example.test',
    { name: 'public', namespace: 'gateway' }),
}
```

### fn tcpRoute

```jsonnet
tcpRoute(name, namespace, serviceName, port, gateway, annotations={})
```

PARAMETERS:

* **name** (`string`)
* **namespace** (`string`)
* **serviceName** (`string`)
* **port** (`number`)
* **gateway** (`object`)
* **annotations** (`object`)
   - default value: `{}`

Create a TCPRoute to a Service. `gateway` must include `name`, `namespace`, and `sectionName` for the TCP listener.

Example:

```jsonnet
local g = import 'labsonnet/helpers/gateway.libsonnet';
{
  tcpRoute: g.tcpRoute('database', 'apps', 'database', 5432,
    { name: 'public', namespace: 'gateway', sectionName: 'tcp' }),
}
```

### fn udpRoute

```jsonnet
udpRoute(name, namespace, serviceName, port, gateway, annotations={})
```

PARAMETERS:

* **name** (`string`)
* **namespace** (`string`)
* **serviceName** (`string`)
* **port** (`number`)
* **gateway** (`object`)
* **annotations** (`object`)
   - default value: `{}`

Create a UDPRoute to a Service. `gateway` must include `name`, `namespace`, and `sectionName` for the UDP listener.

Example:

```jsonnet
local g = import 'labsonnet/helpers/gateway.libsonnet';
{
  udpRoute: g.udpRoute('dns', 'apps', 'dns', 53,
    { name: 'public', namespace: 'gateway', sectionName: 'udp' }),
}
```
