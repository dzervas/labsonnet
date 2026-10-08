# labsonnet

Build Kubernetes workloads for Tanka from container images. Add settings with `+`.

## Tanka setup

In your Tanka project, install the library:

```bash
jb install github.com/dzervas/labsonnet/labsonnet@main
```

Create these one-line import files under `lib/`:

| File                             | Contents                                                                                 |
| -------------------------------- | ---------------------------------------------------------------------------------------- |
| `lib/k.libsonnet`                | `import 'github.com/jsonnet-libs/k8s-libsonnet/1.33/main.libsonnet'`                     |
| `lib/gateway-api.libsonnet`      | `import 'github.com/jsonnet-libs/gateway-api-libsonnet/1.1-experimental/main.libsonnet'` |
| `lib/external-secrets.libsonnet` | `import 'github.com/jsonnet-libs/external-secrets-libsonnet/1.0/main.libsonnet'`         |

Use versions available in your `vendor/` directory. Tanka includes `lib/` and
`vendor/` in its import paths, so the library can use these short aliases.

## Quick start

Add this to `environments/dashboard/main.jsonnet` in a configured Tanka environment:

```jsonnet
local lab = import 'labsonnet/main.libsonnet';
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withNamespace('apps')
    + lab.withCreateNamespace()
    + lab.withPort({ port: 8080, name: 'http' })
    + lab.withEnv({ TZ: 'Europe/Athens' }),
}
```

Preview, compare, and apply from the project root:

```bash
tk show environments/dashboard
tk diff environments/dashboard
tk apply environments/dashboard
```

Each app groups resources under `workload`, `service`, `headlessService`,
`namespace`, `routing`, `pvc`, `externalSecrets`, and `monitors`.
Tanka finds the Kubernetes resources in these nested objects. Unused groups
may be empty or null. Select `.workload` if you only need the workload resource.

Defaults: Deployment, one replica, ClusterIP Service, and namespace equal to
the app name. The namespace is not created unless you call `withCreateNamespace()`.
At least one port is required. Containers run as UID/GID 1000, without privilege
escalation, and with all capabilities dropped. Choose an image that supports this
or set the security context explicitly.

Examples below use `lab` from the import above. Settings such as replica counts
use the last value; ports, mounts, containers, and environment entries accumulate. For maps,
later values replace matching keys.
Replace example image references with images you use.

## Routes, secrets, and storage

```jsonnet
local lab = import 'labsonnet/main.libsonnet';
{
  photos:
    lab.new('photos', 'ghcr.io/example/photos:1.0')
    + lab.withNamespace('apps')
    + lab.withType('StatefulSet')
    + lab.withPort({
      port: 8080,
      name: 'http',
      httpRoute: {
        fqdn: 'photos.example.com',
        gateway: { name: 'edge', namespace: 'network', sectionName: 'https' },
      },
    })
    + lab.withPV('/data', { size: '10Gi', storageClassName: 'fast' })
    + lab.withExternalSecretEnvs('photos-login', { API_TOKEN: 'token' }, {
      store: 'password-store', remoteKey: 'photos', refreshPolicy: 'CreatedOnce',
    })
    + lab.withPort({ port: 9090, name: 'metrics' })
    + lab.withServiceMonitor(),
}
```

The Gateway, storage class, and secret store must already exist. Routes, external
secrets, and monitors need their matching controllers and CRDs.

## Choosing a volume

| Need                                         | Use                                                                                        |
| -------------------------------------------- | ------------------------------------------------------------------------------------------ |
| New persistent storage for a StatefulSet     | [`withPV`](#fn-withpv)                                                                     |
| One StatefulSet PVC mounted at several paths | [`withClaimTemplate`](#fn-withclaimtemplate) + [`withVolumeMount`](#fn-withvolumemount)    |
| An existing PVC                              | [`withExistingPVC`](#fn-withexistingpvc) + [`withVolumeMount`](#fn-withvolumemount)        |
| Temporary files                              | [`withEmptyDir`](#fn-withemptydir)                                                         |
| An existing ConfigMap or Secret              | [`withConfigMapMount`](#fn-withconfigmapmount) or [`withSecretMount`](#fn-withsecretmount) |
| Files from an OCI image                      | [`withImageVolume`](#fn-withimagevolume) + [`withVolumeMount`](#fn-withvolumemount)        |
| Files from a secret store                    | [`withExternalSecretMount`](#fn-withexternalsecretmount)                                   |

A volume provides storage; a mount chooses where it appears in the container.
Each mount path must be unique. A volume can have multiple mounts. Repeating
a volume definition is allowed only when the definitions match.

## Reusable defaults

See [downstream helpers and overrides](downstream.md) for re-exporting
helpers, setting local defaults, and adding checks after composition.

Wrap the library to share placement or monitoring settings between apps:

```jsonnet
local lab = import 'labsonnet/main.libsonnet';
local affinity = import 'labsonnet/helpers/affinity.libsonnet';
local site = lab {
  new(name, image)::
    super.new(name, image)
    + lab.withAffinity(affinity.requireNodeLabel('pool', ['apps'])),
  withMetrics(port=9090)::
    lab.withPort({ port: port, name: 'metrics' }) + lab.withServiceMonitor(),
};
{
  dashboard:
    site.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + site.withPort({ port: 8080 })
    + site.withMetrics(),
}
```

## Lazy configuration callbacks

Use a callback when a setting needs the final app name or namespace:

```jsonnet
local lab = import 'labsonnet/main.libsonnet';
{
  worker:
    lab.new('worker', 'ghcr.io/example/worker:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withEnv(function(ctx) { APP_NAME: ctx.name, APP_NAMESPACE: ctx.namespace })
    + lab.withNamespace('apps'),
}
```

`ctx` contains only `name` and `namespace`. The namespace defaults to the app
name; callbacks see later `withNamespace` calls too. `withServiceName` does not
change `ctx.name`.

Supported by `withPort`, `withHeadlessPort`, `withEnv`, `withFieldRefEnv`,
`withSecretEnv`, `withPV`'s `pvConfig`, and `withClaimTemplate`'s `config`.
Return an object with the normal helper fields. Nested callbacks are not
resolved. Keep callbacks pure and use `ctx` or captured values; reading the app
being built can cause a cycle.

## Install

```
jb install github.com/dzervas/labsonnet/labsonnet@main
```

## Usage

```jsonnet
local labsonnet = import 'labsonnet/main.libsonnet'
```


## Subpackages

* [downstream](downstream.md)
* [helpers.affinity](helpers/affinity.md)
* [helpers.certificate](helpers/certificate.md)
* [helpers.cnpg](helpers/cnpg.md)
* [helpers.externalsecret](helpers/externalsecret.md)
* [helpers.gateway](helpers/gateway.md)
* [helpers.imagevolume](helpers/imagevolume.md)
* [helpers.ingress](helpers/ingress.md)
* [helpers.pvc](helpers/pvc.md)
* [helpers.servicemonitor](helpers/servicemonitor.md)

## Index

* [`fn new(name, image)`](#fn-new)
* [`fn withAffinity(affinity)`](#fn-withaffinity)
* [`fn withArgs(args)`](#fn-withargs)
* [`fn withClaimTemplate(name, config)`](#fn-withclaimtemplate)
* [`fn withCommand(command)`](#fn-withcommand)
* [`fn withConfigMapMount(mountPath, name, readOnly=true)`](#fn-withconfigmapmount)
* [`fn withContainer(container)`](#fn-withcontainer)
* [`fn withCreateNamespace(create=true)`](#fn-withcreatenamespace)
* [`fn withEmptyDir(mountPath)`](#fn-withemptydir)
* [`fn withEnv(env)`](#fn-withenv)
* [`fn withExistingPVC(volumeName, claimName)`](#fn-withexistingpvc)
* [`fn withExternalSecretEnvs(name, envs, cfg)`](#fn-withexternalsecretenvs)
* [`fn withExternalSecretMount(name, mountPath, cfg, readOnly=true)`](#fn-withexternalsecretmount)
* [`fn withFieldRefEnv(envs)`](#fn-withfieldrefenv)
* [`fn withFqdn(fqdn)`](#fn-withfqdn)
* [`fn withHeadlessPort(portEntry)`](#fn-withheadlessport)
* [`fn withHeadlessService(name=null, publishNotReadyAddresses=true)`](#fn-withheadlessservice)
* [`fn withImagePullSecrets(secrets)`](#fn-withimagepullsecrets)
* [`fn withImageVolume(name, image, pullPolicy=null)`](#fn-withimagevolume)
* [`fn withInitContainer(container)`](#fn-withinitcontainer)
* [`fn withLivenessProbe(probe)`](#fn-withlivenessprobe)
* [`fn withNamespace(ns)`](#fn-withnamespace)
* [`fn withNamespaceAnnotations(annotations)`](#fn-withnamespaceannotations)
* [`fn withNamespaceLabels(labels)`](#fn-withnamespacelabels)
* [`fn withPV(mountPath, pvConfig)`](#fn-withpv)
* [`fn withPodAnnotations(annotations)`](#fn-withpodannotations)
* [`fn withPodLabels(labels)`](#fn-withpodlabels)
* [`fn withPodManagementPolicy(policy)`](#fn-withpodmanagementpolicy)
* [`fn withPodSecurityContext(ctx)`](#fn-withpodsecuritycontext)
* [`fn withPort(portEntry)`](#fn-withport)
* [`fn withReadinessProbe(probe)`](#fn-withreadinessprobe)
* [`fn withReplicas(replicas)`](#fn-withreplicas)
* [`fn withResources(resources)`](#fn-withresources)
* [`fn withRunAsUser(uid)`](#fn-withrunasuser)
* [`fn withSecretEnv(envs)`](#fn-withsecretenv)
* [`fn withSecretMount(mountPath, name, readOnly=true)`](#fn-withsecretmount)
* [`fn withSecurityContext(ctx)`](#fn-withsecuritycontext)
* [`fn withServiceMonitor(portName="metrics", path="/metrics", interval="30s", name=null)`](#fn-withservicemonitor)
* [`fn withServiceName(name)`](#fn-withservicename)
* [`fn withServiceType(type)`](#fn-withservicetype)
* [`fn withStartupProbe(probe)`](#fn-withstartupprobe)
* [`fn withType(type)`](#fn-withtype)
* [`fn withVolumeMount(mountPath, volumeName, readOnly=false, subPath=null)`](#fn-withvolumemount)

## Fields

### fn new

```jsonnet
new(name, image)
```

PARAMETERS:

* **name** (`string`)
* **image** (`string`)

Create an app. Add at least one port before rendering. The name also sets the default namespace and Service name.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 }),
}
```

### fn withAffinity

```jsonnet
withAffinity(affinity)
```

PARAMETERS:

* **affinity** (`object | null`)

Set pod placement rules. Use the affinity helper to build them; pass `null` or `{}` to remove placement rules.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withAffinity((import 'labsonnet/helpers/affinity.libsonnet').requireNodeLabel('pool', ['apps'])),
}
```

### fn withArgs

```jsonnet
withArgs(args)
```

PARAMETERS:

* **args** (`array`)

Set arguments passed to the container entrypoint.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withArgs(['--listen', ':8080']),
}
```

### fn withClaimTemplate

```jsonnet
withClaimTemplate(name, config)
```

PARAMETERS:

* **name** (`string`)
* **config** (`object | function(ctx) object`)

Create a StatefulSet PVC by volume name, then mount it separately.
Use this when one PVC needs several mounts. `config` accepts `size`
(required), `accessModes`, and `storageClassName`, as in `withPV`.
Accepts an object or callback.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withType('StatefulSet')
    + lab.withClaimTemplate('data', { size: '10Gi', storageClassName: 'fast' })
    + lab.withVolumeMount('/config', 'data', subPath='config')
    + lab.withVolumeMount('/data', 'data', subPath='data'),
}
```

### fn withCommand

```jsonnet
withCommand(command)
```

PARAMETERS:

* **command** (`array`)

Set the container entrypoint as an array of strings.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withCommand(['/app/server']),
}
```

### fn withConfigMapMount

```jsonnet
withConfigMapMount(mountPath, name, readOnly=true)
```

PARAMETERS:

* **mountPath** (`string`)
* **name** (`string`)
* **readOnly** (`bool`)
   - default value: `true`

Mount an existing ConfigMap from the app namespace. Read-only by default.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withConfigMapMount('/etc/app', 'dashboard-config'),
}
```

### fn withContainer

```jsonnet
withContainer(container)
```

PARAMETERS:

* **container** (`object`)

Add a sidecar container using a Kubernetes container object. It inherits the main container's environment, mounts, and security settings.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withContainer({ name: 'worker', image: 'ghcr.io/example/worker:1.0' }),
}
```

### fn withCreateNamespace

```jsonnet
withCreateNamespace(create=true)
```

PARAMETERS:

* **create** (`bool`)
   - default value: `true`

Create the app namespace when true. Namespace creation is disabled by default.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withCreateNamespace(),
}
```

### fn withEmptyDir

```jsonnet
withEmptyDir(mountPath)
```

PARAMETERS:

* **mountPath** (`string`)

Mount temporary storage. Data lasts only for the lifetime of the pod.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withEmptyDir('/tmp'),
}
```

### fn withEnv

```jsonnet
withEnv(env)
```

PARAMETERS:

* **env** (`object | function(ctx) object`)

Add plain environment variables as a map. Accepts an object or callback.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withEnv({ TZ: 'Europe/Athens', LOG_LEVEL: 'info' }),
}
```

### fn withExistingPVC

```jsonnet
withExistingPVC(volumeName, claimName)
```

PARAMETERS:

* **volumeName** (`string`)
* **claimName** (`string`)

Use a PVC that already exists in the app namespace. `volumeName` names
the volume in the pod; `claimName` identifies the existing PVC. Add mounts
with `withVolumeMount`. Works with Deployment and StatefulSet.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withExistingPVC('media', 'shared-media')
    + lab.withVolumeMount('/movies', 'media', readOnly=true, subPath='movies'),
}
```

### fn withExternalSecretEnvs

```jsonnet
withExternalSecretEnvs(name, envs, cfg)
```

PARAMETERS:

* **name** (`string`)
* **envs** (`object`)
* **cfg** (`object`)

Create an ExternalSecret and read its keys as environment variables. Map variable names to keys in the extracted remote object. `cfg.store` is required; `storeKind` defaults to `ClusterSecretStore` and `remoteKey` to the secret name.

Optional fields: `refreshInterval`, `refreshPolicy`, `creationPolicy`, `deletionPolicy`. Omitted policy fields use controller defaults. Requires External Secrets Operator and an existing store.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withExternalSecretEnvs('dashboard-login', { API_TOKEN: 'token' }, {
      store: 'password-store', remoteKey: 'dashboard', refreshPolicy: 'CreatedOnce',
    }),
}
```

### fn withExternalSecretMount

```jsonnet
withExternalSecretMount(name, mountPath, cfg, readOnly=true)
```

PARAMETERS:

* **name** (`string`)
* **mountPath** (`string`)
* **cfg** (`object`)
* **readOnly** (`bool`)
   - default value: `true`

Create an ExternalSecret and mount the resulting Secret read-only by default. Uses the same `cfg` fields as `withExternalSecretEnvs`. Extracts the whole remote object. A secret can be mounted at multiple distinct paths.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withExternalSecretMount('dashboard-login', '/run/credentials', { store: 'password-store', remoteKey: 'dashboard' }),
}
```

### fn withFieldRefEnv

```jsonnet
withFieldRefEnv(envs)
```

PARAMETERS:

* **envs** (`object | function(ctx) object`)

Add environment variables from pod fields using the downward API. Map variable names to field paths. Accepts an object or callback.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withFieldRefEnv({ POD_NAME: 'metadata.name', POD_NAMESPACE: 'metadata.namespace' }),
}
```

### fn withFqdn

```jsonnet
withFqdn(fqdn)
```

PARAMETERS:

* **fqdn** (`string`)

Set the default hostname for HTTP, gRPC, and Ingress routes. A route can override it with its own `fqdn`.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withFqdn('dashboard.example.com'),
}
```

### fn withHeadlessPort

```jsonnet
withHeadlessPort(portEntry)
```

PARAMETERS:

* **portEntry** (`object | function(ctx) object`)

Expose a port through the headless Service for peer discovery. Enable it
with `withHeadlessService()`. Uses the same fields as `withPort` and accepts
an object or callback.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withHeadlessService()
    + lab.withHeadlessPort({ port: 7000, name: 'peer' }),
}
```

### fn withHeadlessService

```jsonnet
withHeadlessService(name=null, publishNotReadyAddresses=true)
```

PARAMETERS:

* **name** (`null`,`string`)
   - default value: `null`
* **publishNotReadyAddresses** (`bool`)
   - default value: `true`

Create a headless Service for peer discovery. Its name defaults to `<app>-headless`; it also supplies the StatefulSet `serviceName`. Not-ready addresses are published by default. Add ports with `withHeadlessPort`.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withType('StatefulSet')
    + lab.withHeadlessService(publishNotReadyAddresses=false)
    + lab.withHeadlessPort({ port: 7000, name: 'peer' }),
}
```

### fn withImagePullSecrets

```jsonnet
withImagePullSecrets(secrets)
```

PARAMETERS:

* **secrets** (`array`)

Add names of existing image pull Secrets in the app namespace.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withImagePullSecrets(['registry-login']),
}
```

### fn withImageVolume

```jsonnet
withImageVolume(name, image, pullPolicy=null)
```

PARAMETERS:

* **name** (`string`)
* **image** (`string`)
* **pullPolicy** (`null`,`string`)
   - default value: `null`

Use files from an OCI image. Add a mount with `readOnly=true`.
Requires cluster support for image volumes. Optional `pullPolicy`:
`Always`, `IfNotPresent`, or `Never`; null leaves it to Kubernetes.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withImageVolume('assets', 'ghcr.io/example/assets:1.0')
    + lab.withVolumeMount('/assets', 'assets', readOnly=true),
}
```

### fn withInitContainer

```jsonnet
withInitContainer(container)
```

PARAMETERS:

* **container** (`object`)

Add a container that runs before the app starts. It inherits the main container's environment, mounts, and security settings.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withInitContainer({ name: 'prepare', image: 'busybox:1.37', command: ['sh', '-c', 'echo ready'] }),
}
```

### fn withLivenessProbe

```jsonnet
withLivenessProbe(probe)
```

PARAMETERS:

* **probe** (`object`)

Set a probe that restarts an unhealthy container.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withLivenessProbe({ httpGet: { path: '/healthz', port: 8080 }, periodSeconds: 30 }),
}
```

### fn withNamespace

```jsonnet
withNamespace(ns)
```

PARAMETERS:

* **ns** (`string`)

Set the namespace for the app and its namespaced resources. The default is the app name.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withNamespace('apps'),
}
```

### fn withNamespaceAnnotations

```jsonnet
withNamespaceAnnotations(annotations)
```

PARAMETERS:

* **annotations** (`object`)

Add namespace annotations. Call `withCreateNamespace()` to emit the Namespace resource.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withCreateNamespace()
    + lab.withNamespaceAnnotations({ owner: 'platform' }),
}
```

### fn withNamespaceLabels

```jsonnet
withNamespaceLabels(labels)
```

PARAMETERS:

* **labels** (`object`)

Add namespace labels. Call `withCreateNamespace()` to emit the Namespace resource.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withCreateNamespace()
    + lab.withNamespaceLabels({ 'pod-security.kubernetes.io/enforce': 'restricted' }),
}
```

### fn withPV

```jsonnet
withPV(mountPath, pvConfig)
```

PARAMETERS:

* **mountPath** (`string`)
* **pvConfig** (`object | function(ctx) object`)

Create a PVC and mount it in one call. Requires a StatefulSet and `size`.

Set `storageClassName` to choose a storage class; otherwise Kubernetes uses
its default. Optional fields: `name`, `accessModes` (default
`['ReadWriteOnce']`), `readOnly`, and `subPath` (see `withVolumeMount`).
Accepts an object or callback.

For another mount of this volume, give it a `name` and use `withVolumeMount`.
For temporary storage, use `withEmptyDir` (or `emptyDir: true`).

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withType('StatefulSet')
    + lab.withPV('/data', { name: 'data', size: '10Gi', storageClassName: 'fast' }),
}
```

### fn withPodAnnotations

```jsonnet
withPodAnnotations(annotations)
```

PARAMETERS:

* **annotations** (`object`)

Add annotations to the pod template.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withPodAnnotations({ 'reloader.stakater.com/auto': 'true' }),
}
```

### fn withPodLabels

```jsonnet
withPodLabels(labels)
```

PARAMETERS:

* **labels** (`object`)

Add pod labels. Labels used by the workload selector cannot be changed.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withPodLabels({ component: 'dashboard' }),
}
```

### fn withPodManagementPolicy

```jsonnet
withPodManagementPolicy(policy)
```

PARAMETERS:

* **policy** (`string`)

Set the StatefulSet pod management policy to `OrderedReady` or `Parallel`.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withType('StatefulSet')
    + lab.withPodManagementPolicy('Parallel'),
}
```

### fn withPodSecurityContext

```jsonnet
withPodSecurityContext(ctx)
```

PARAMETERS:

* **ctx** (`object`)

Override pod security defaults. Top-level null values remove fields. Each call replaces the previous override object.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withPodSecurityContext({ fsGroup: null, fsGroupChangePolicy: null }),
}
```

### fn withPort

```jsonnet
withPort(portEntry)
```

PARAMETERS:

* **portEntry** (`object | function(ctx) object`)

Expose a container port through the app's Service.

| Field      | Meaning                                                                          |
| ---------- | -------------------------------------------------------------------------------- |
| `port`     | Required port number.                                                            |
| `name`     | Optional Service port name; defaults to `<protocol>-<port>`, such as `tcp-8080`. |
| `protocol` | Defaults to `TCP`; use `UDP` for a UDP port.                                     |

For a route, add one of `httpRoute`, `grpcRoute`, `tcpRoute`, `udpRoute`, or
`ingress`. HTTP, gRPC, and Ingress need a hostname (`fqdn` in the route or
`withFqdn`). Routes select TCP, except `udpRoute`, which selects UDP.

See the [routing example](#routes-secrets-and-storage) and the
[Gateway](helpers/gateway.md) or [Ingress](helpers/ingress.md) options.
`name` inside a route config overrides the resource name.

Repeated number/protocol pairs keep the first Service port. Use different
port names to attach several routes to one port. Accepts an object or callback.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080, name: 'http' }),
}
```

### fn withReadinessProbe

```jsonnet
withReadinessProbe(probe)
```

PARAMETERS:

* **probe** (`object`)

Set a probe that controls when the pod receives Service traffic.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withReadinessProbe({ httpGet: { path: '/readyz', port: 8080 } }),
}
```

### fn withReplicas

```jsonnet
withReplicas(replicas)
```

PARAMETERS:

* **replicas** (`number`)

Set the replica count, a non-negative integer. The default is 1.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withReplicas(2),
}
```

### fn withResources

```jsonnet
withResources(resources)
```

PARAMETERS:

* **resources** (`object`)

Set CPU and memory requests and limits using a Kubernetes resources object.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withResources({ requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '512Mi' } }),
}
```

### fn withRunAsUser

```jsonnet
withRunAsUser(uid)
```

PARAMETERS:

* **uid** (`number`)

Set the container UID and GID, plus the default pod `fsGroup`. The default is 1000.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withRunAsUser(65532),
}
```

### fn withSecretEnv

```jsonnet
withSecretEnv(envs)
```

PARAMETERS:

* **envs** (`object | function(ctx) object`)

Read environment variables from existing Kubernetes Secrets in the app namespace. Map variables to `{ name: secretName, key: secretKey }`. Accepts an object or callback.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withSecretEnv({ API_TOKEN: { name: 'dashboard-login', key: 'token' } }),
}
```

### fn withSecretMount

```jsonnet
withSecretMount(mountPath, name, readOnly=true)
```

PARAMETERS:

* **mountPath** (`string`)
* **name** (`string`)
* **readOnly** (`bool`)
   - default value: `true`

Mount an existing Kubernetes Secret from the app namespace. Read-only by default.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withSecretMount('/run/credentials', 'dashboard-login'),
}
```

### fn withSecurityContext

```jsonnet
withSecurityContext(ctx)
```

PARAMETERS:

* **ctx** (`object`)

Override container security defaults. Each call replaces the previous override object.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withSecurityContext({ readOnlyRootFilesystem: true }),
}
```

### fn withServiceMonitor

```jsonnet
withServiceMonitor(portName="metrics", path="/metrics", interval="30s", name=null)
```

PARAMETERS:

* **portName** (`string`)
   - default value: `"metrics"`
* **path** (`string`)
   - default value: `"/metrics"`
* **interval** (`string`)
   - default value: `"30s"`
* **name** (`null`,`string`)
   - default value: `null`

Create a ServiceMonitor for an ordinary Service port. `portName` must match the final Service port name. Defaults: `metrics`, `/metrics`, `30s`, and a monitor name matching `portName`. Requires a monitoring operator and the ServiceMonitor CRD.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withPort({ port: 9090, name: 'metrics' })
    + lab.withServiceMonitor(),
}
```

### fn withServiceName

```jsonnet
withServiceName(name)
```

PARAMETERS:

* **name** (`string`)

Set the StatefulSet `serviceName`. This overrides the generated headless Service reference; it does not rename the ordinary Service or create another Service.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withType('StatefulSet')
    + lab.withServiceName('existing-peers'),
}
```

### fn withServiceType

```jsonnet
withServiceType(type)
```

PARAMETERS:

* **type** (`string`)

Set the ordinary Service type. The default is `ClusterIP`; use `LoadBalancer` for direct network access.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withServiceType('LoadBalancer'),
}
```

### fn withStartupProbe

```jsonnet
withStartupProbe(probe)
```

PARAMETERS:

* **probe** (`object`)

Set a probe that allows slow startup before liveness and readiness checks begin.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withStartupProbe({ httpGet: { path: '/healthz', port: 8080 }, failureThreshold: 30, periodSeconds: 10 }),
}
```

### fn withType

```jsonnet
withType(type)
```

PARAMETERS:

* **type** (`string`)

Choose `Deployment` (default) or `StatefulSet`. Managed persistent storage requires a StatefulSet.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withType('StatefulSet'),
}
```

### fn withVolumeMount

```jsonnet
withVolumeMount(mountPath, volumeName, readOnly=false, subPath=null)
```

PARAMETERS:

* **mountPath** (`string`)
* **volumeName** (`string`)
* **readOnly** (`bool`)
   - default value: `false`
* **subPath** (`null`,`string`)
   - default value: `null`

Mount a volume created by another helper. `volumeName` must match the
declared volume or claim template; declaration order does not matter.

`readOnly` defaults to false. `subPath` selects a file or folder inside the volume;
null mounts the whole volume. Image volumes require `readOnly=true`.

```jsonnet
{
  dashboard:
    lab.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withExistingPVC('media', 'shared-media')
    + lab.withVolumeMount('/movies', 'media', readOnly=true, subPath='movies')
    + lab.withVolumeMount('/series', 'media', readOnly=true, subPath='series'),
}
```
