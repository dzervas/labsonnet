# labsonnet

Commonly used components to define a Kubernetes workload, mainly from a bare docker image
## Install

```
jb install https://github.com/dzervas/labsonnet@main
```

## Usage

```jsonnet
local labsonnet = import "https://github.com/dzervas/labsonnet/labsonnet/main.libsonnet"
```


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
* [`fn withHeadlessService(name, publishNotReadyAddresses=true)`](#fn-withheadlessservice)
* [`fn withImagePullSecrets(secrets)`](#fn-withimagepullsecrets)
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
* [`fn withServiceMonitor(portName, path, interval, name)`](#fn-withservicemonitor)
* [`fn withServiceName(name)`](#fn-withservicename)
* [`fn withServiceType(type)`](#fn-withservicetype)
* [`fn withStartupProbe(probe)`](#fn-withstartupprobe)
* [`fn withType(type)`](#fn-withtype)
* [`fn withVolumeMount(mountPath, volumeName, readOnly=false, subPath)`](#fn-withvolumemount)

## Fields

### fn new

```jsonnet
new(name, image)
```

PARAMETERS:

* **name** (`string`)
* **image** (`string`)

Main entrypoint for labsonnet, defines a new "app".
The `name` is used for most of the resources, namespace, service name, etc.

The rest of the functions work on top of this to alter various aspects of the app.

Example:

```jsonnet
labsonnet.new('hello-world', 'nginx:latest')
+ labsonnet.withEnv('MY_VAR', 'my-value')
```

### fn withAffinity

```jsonnet
withAffinity(affinity)
```

PARAMETERS:

* **affinity** (`object | null`)

Set workload affinity with nodeAffinity, podAffinity, or podAntiAffinity object fields (see helpers/affinity.libsonnet)
### fn withArgs

```jsonnet
withArgs(args)
```

PARAMETERS:

* **args** (`array`)

Set the arguments for the app
### fn withClaimTemplate

```jsonnet
withClaimTemplate(name, config)
```

PARAMETERS:

* **name** (`string`)
* **config** (`object`)

Declare managed StatefulSet storage without mounting it. config accepts size (required), accessModes (default ['ReadWriteOnce']), and storageClassName (default null). The name is the claim-template and volume name and must be a Kubernetes volume name. Repeated equal definitions deduplicate; conflicting definitions fail. Templates declared here render in alphabetical name order; withPV templates retain alphabetical mount-path order. Mount it with withVolumeMount. Declarations and references resolve against the final composed configuration, so their order does not matter.

```jsonnet
labsonnet.new('probe', 'example:1')
+ labsonnet.withType('StatefulSet')
+ labsonnet.withPort({ port: 8080 })
+ labsonnet.withClaimTemplate('state', { size: '2Gi', storageClassName: 'fast' })
+ labsonnet.withVolumeMount('/config', 'state', subPath='config')
+ labsonnet.withVolumeMount('/data', 'state', subPath='data')
```

### fn withCommand

```jsonnet
withCommand(command)
```

PARAMETERS:

* **command** (`array`)

Set the command for the app
### fn withConfigMapMount

```jsonnet
withConfigMapMount(mountPath, name, readOnly=true)
```

PARAMETERS:

* **mountPath** (`string`)
* **name** (`string`)
* **readOnly** (`bool`)
   - default value: `true`

Add a configMap volume mount to the app. Duplicate mount paths across all mount APIs fail, including identical repeats.
### fn withContainer

```jsonnet
withContainer(container)
```

PARAMETERS:

* **container** (`object`)

Add an additional container to the app - pass a standard k.core.v1.container object
### fn withCreateNamespace

```jsonnet
withCreateNamespace(create=true)
```

PARAMETERS:

* **create** (`bool`)
   - default value: `true`

Set whether to create the namespace
### fn withEmptyDir

```jsonnet
withEmptyDir(mountPath)
```

PARAMETERS:

* **mountPath** (`string`)

Add an emptyDir volume mount to the app. Duplicate mount paths across all mount APIs fail, including identical repeats.
### fn withEnv

```jsonnet
withEnv(env)
```

PARAMETERS:

* **env** (`object`)

Add environment variables to the app
### fn withExistingPVC

```jsonnet
withExistingPVC(volumeName, claimName)
```

PARAMETERS:

* **volumeName** (`string`)
* **claimName** (`string`)

Declare a volume referencing an existing PVC in the workload namespace, without creating or managing that claim. Works with Deployment and StatefulSet. volumeName must be a Kubernetes volume name; claimName is independent and may be a longer or dotted PVC name. Repeated equal definitions deduplicate; conflicting definitions fail. This API does not add a mount.

```jsonnet
labsonnet.new('reader', 'example:1')
+ labsonnet.withPort({ port: 8080 })
+ labsonnet.withExistingPVC('media', 'shared-media')
+ labsonnet.withVolumeMount('/movies', 'media', readOnly=true, subPath='movies')
+ labsonnet.withVolumeMount('/series', 'media', readOnly=true, subPath='series')
```

### fn withExternalSecretEnvs

```jsonnet
withExternalSecretEnvs(name, envs, cfg)
```

PARAMETERS:

* **name** (`string`)
* **envs** (`object`)
* **cfg** (`object`)

Add an external secret with environment variable mappings. cfg = { store: string, storeKind?: string, remoteKey?: string, refreshInterval?: string, refreshPolicy?: string, creationPolicy?: string, deletionPolicy?: string }
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

Add an external secret mounted as a volume. Duplicate mount paths across all mount APIs fail, including identical repeats; the same secret may be mounted at different paths. cfg = { store: string, storeKind?: string, remoteKey?: string, refreshInterval?: string, refreshPolicy?: string, creationPolicy?: string, deletionPolicy?: string }
### fn withFieldRefEnv

```jsonnet
withFieldRefEnv(envs)
```

PARAMETERS:

* **envs** (`object`)

Add environment variable references to the app
### fn withFqdn

```jsonnet
withFqdn(fqdn)
```

PARAMETERS:

* **fqdn** (`string`)

Set the FQDN for the app
### fn withHeadlessPort

```jsonnet
withHeadlessPort(portEntry)
```

PARAMETERS:

* **portEntry** (`object`)

Add a container port exposed on the headless Service. Use withHeadlessService() to enable headless Service generation.
### fn withHeadlessService

```jsonnet
withHeadlessService(name, publishNotReadyAddresses=true)
```

PARAMETERS:

* **name** (`string`)
* **publishNotReadyAddresses** (`bool`)
   - default value: `true`

Create a headless Service for a Deployment or StatefulSet, optionally setting its name and publishing not-ready addresses. The name defaults to `<workload>-headless` and supplies StatefulSet serviceName unless overridden.
### fn withImagePullSecrets

```jsonnet
withImagePullSecrets(secrets)
```

PARAMETERS:

* **secrets** (`array`)

Add image pull secrets to the app
### fn withInitContainer

```jsonnet
withInitContainer(container)
```

PARAMETERS:

* **container** (`object`)

Add an init container to the app - pass a standard k.core.v1.container object
### fn withLivenessProbe

```jsonnet
withLivenessProbe(probe)
```

PARAMETERS:

* **probe** (`object`)

Set the liveness probe for the app - e.g. `{ httpGet: { path: '/healthz', port: 8080 }, initialDelaySeconds: 10, periodSeconds: 30 }`
### fn withNamespace

```jsonnet
withNamespace(ns)
```

PARAMETERS:

* **ns** (`string`)

Set the namespace for the app
### fn withNamespaceAnnotations

```jsonnet
withNamespaceAnnotations(annotations)
```

PARAMETERS:

* **annotations** (`object`)

Add namespace annotations to the app
### fn withNamespaceLabels

```jsonnet
withNamespaceLabels(labels)
```

PARAMETERS:

* **labels** (`object`)

Add namespace labels to the app
### fn withPV

```jsonnet
withPV(mountPath, pvConfig)
```

PARAMETERS:

* **mountPath** (`string`)
* **pvConfig** (`object`)

Convenience wrapper over storage declaration and withVolumeMount, declaring managed storage and mounting it in one call. pvConfig supports name, size, accessModes, storageClassName, readOnly (default false), subPath (default null), and emptyDir. Persistent storage requires StatefulSet. Names default to `<workload>-<mount-path-with-dashes>`; storage defaults are ReadWriteOnce and no explicit storage class. Each mount path may be declared only once across all mount APIs, including identical repeats. Use withVolumeMount at another path to mount its named volume again.

### fn withPodAnnotations

```jsonnet
withPodAnnotations(annotations)
```

PARAMETERS:

* **annotations** (`object`)

Add pod annotations to the app
### fn withPodLabels

```jsonnet
withPodLabels(labels)
```

PARAMETERS:

* **labels** (`object`)

Add pod labels to the app
### fn withPodManagementPolicy

```jsonnet
withPodManagementPolicy(policy)
```

PARAMETERS:

* **policy** (`string`)

Set the pod management policy for the app
### fn withPodSecurityContext

```jsonnet
withPodSecurityContext(ctx)
```

PARAMETERS:

* **ctx** (`object`)

Set pod-level security context overrides. Top-level fields set to null are omitted from the final context, so use values such as { fsGroup: null, fsGroupChangePolicy: null } to remove those defaults. As with other scalar hidden fields, the last withPodSecurityContext() call supplies the overrides.
### fn withPort

```jsonnet
withPort(portEntry)
```

PARAMETERS:

* **portEntry** (`object`)

Add a container port exposed on the ordinary Service. Routing configs accept `name` to override the resource name while keeping output keys based on port names.
### fn withReadinessProbe

```jsonnet
withReadinessProbe(probe)
```

PARAMETERS:

* **probe** (`object`)

Set the readiness probe for the app - e.g. `{ httpGet: { path: '/readyz', port: 8080 }, initialDelaySeconds: 10, periodSeconds: 30 }`
### fn withReplicas

```jsonnet
withReplicas(replicas)
```

PARAMETERS:

* **replicas** (`number`)

Set the number of replicas for the app (a non-negative integer)
### fn withResources

```jsonnet
withResources(resources)
```

PARAMETERS:

* **resources** (`object`)

Set the resource requirements for the app - `{ requests: { cpu, memory }, limits: { cpu, memory } }`
### fn withRunAsUser

```jsonnet
withRunAsUser(uid)
```

PARAMETERS:

* **uid** (`number`)

Set the UID & GID for the app
### fn withSecretEnv

```jsonnet
withSecretEnv(envs)
```

PARAMETERS:

* **envs** (`object`)

Add environment variables from existing Kubernetes Secrets
### fn withSecretMount

```jsonnet
withSecretMount(mountPath, name, readOnly=true)
```

PARAMETERS:

* **mountPath** (`string`)
* **name** (`string`)
* **readOnly** (`bool`)
   - default value: `true`

Add a secret volume mount to the app. Duplicate mount paths across all mount APIs fail, including identical repeats.
### fn withSecurityContext

```jsonnet
withSecurityContext(ctx)
```

PARAMETERS:

* **ctx** (`object`)

Set the security context for the app - runAsNonRoot, runAsUser, capabilities, etc.
### fn withServiceMonitor

```jsonnet
withServiceMonitor(portName, path, interval, name)
```

PARAMETERS:

* **portName** (`string`)
* **path** (`string`)
* **interval** (`string`)
* **name** (`string`)

Add a ServiceMonitor for Prometheus/VictoriaMetrics scraping. portName must match an exposed Service port name after deduplication; name defaults to portName.
### fn withServiceName

```jsonnet
withServiceName(name)
```

PARAMETERS:

* **name** (`string`)

Override the StatefulSet serviceName, taking precedence over the headless Service name.
### fn withServiceType

```jsonnet
withServiceType(type)
```

PARAMETERS:

* **type** (`string`)

Set the service type for the app (ClusterIP, NodePort, LoadBalancer, ExternalName)
### fn withStartupProbe

```jsonnet
withStartupProbe(probe)
```

PARAMETERS:

* **probe** (`object`)

Set the startup probe for the app - e.g. `{ httpGet: { path: '/startupz', port: 8080 }, initialDelaySeconds: 10, periodSeconds: 30 }`
### fn withType

```jsonnet
withType(type)
```

PARAMETERS:

* **type** (`string`)

Set the workload type of the app (Deployment or StatefulSet)
### fn withVolumeMount

```jsonnet
withVolumeMount(mountPath, volumeName, readOnly=false, subPath)
```

PARAMETERS:

* **mountPath** (`string`)
* **volumeName** (`string`)
* **readOnly** (`bool`)
   - default value: `false`
* **subPath** (`string`)

Mount a declared volume or claim template. References resolve after composition, so declarations can appear before or after mounts. Also accepts volume names supplied by withPV, withEmptyDir, withSecretMount, withConfigMapMount, or withExternalSecretMount. Each mount has independent readOnly and subPath; null subPath omits the field. Different paths accumulate. Each mount path may be declared only once across all mount APIs, including identical repeats. Unknown references and conflicting volume definitions fail.
