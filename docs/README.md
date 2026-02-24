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
* [`fn withCommand(command)`](#fn-withcommand)
* [`fn withConfigMapMount(mountPath, name, readOnly=true)`](#fn-withconfigmapmount)
* [`fn withCreateNamespace(create=true)`](#fn-withcreatenamespace)
* [`fn withEmptyDir(mountPath)`](#fn-withemptydir)
* [`fn withEnv(env)`](#fn-withenv)
* [`fn withExternalSecretEnvs(name, envs, cfg)`](#fn-withexternalsecretenvs)
* [`fn withExternalSecretMount(name, mountPath, cfg, readOnly=true)`](#fn-withexternalsecretmount)
* [`fn withFieldRefEnv(envs)`](#fn-withfieldrefenv)
* [`fn withFqdn(fqdn)`](#fn-withfqdn)
* [`fn withHeadlessService(headless=true)`](#fn-withheadlessservice)
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

* **affinity** (`object`)

Set the affinity for the app - for more affinities check helpers/affinity.libsonnet
### fn withArgs

```jsonnet
withArgs(args)
```

PARAMETERS:

* **args** (`array`)

Set the arguments for the app
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

Add a configMap volume mount to the app
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

Add an emptyDir volume mount to the app
### fn withEnv

```jsonnet
withEnv(env)
```

PARAMETERS:

* **env** (`object`)

Add environment variables to the app
### fn withExternalSecretEnvs

```jsonnet
withExternalSecretEnvs(name, envs, cfg)
```

PARAMETERS:

* **name** (`string`)
* **envs** (`object`)
* **cfg** (`object`)

Add an external secret with environment variable mappings. cfg = { store: string, storeKind?: string, remoteKey?: string }
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

Add an external secret mounted as a volume. cfg = { store: string, storeKind?: string, remoteKey?: string }
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
### fn withHeadlessService

```jsonnet
withHeadlessService(headless=true)
```

PARAMETERS:

* **headless** (`bool`)
   - default value: `true`

Set whether to create a headless service
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

Add an init container to the app
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

Add a persistent volume mount to the app
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

Set the pod-level security context overrides
### fn withPort

```jsonnet
withPort(portEntry)
```

PARAMETERS:

* **portEntry** (`object`)

Add a port to the app
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

Set the number of replicas for the app
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

Add a secret volume mount to the app
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

Add ServiceMonitor for Prometheus/VictoriaMetrics scraping.
portName must match a port name from withPort(). name defaults to portName.

### fn withServiceName

```jsonnet
withServiceName(name)
```

PARAMETERS:

* **name** (`string`)

Set the name for the new kubernetes service
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
