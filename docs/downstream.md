# Downstream helpers and overrides

Keep cluster-specific settings in your Tanka project's `lib/` directory.
Extend the upstream library once, then import the local wrapper in environments.
Unchanged upstream helpers remain available through that wrapper.

## Project layout

```text
lib/
  k.libsonnet                 # One-line dependency import
  gateway-api.libsonnet      # One-line dependency import
  external-secrets.libsonnet # One-line dependency import
  service.libsonnet          # Workload defaults and convenience methods
  helpers/
    affinity.libsonnet       # Local placement presets
    pvc.libsonnet            # Local storage defaults
    cnpg.libsonnet           # Local database defaults and checks
environments/
  dashboard/main.jsonnet     # Named resource groups
```

See [Tanka setup](README.md#tanka-setup) for dependency imports. Environment
files can import `service.libsonnet` or `helpers/pvc.libsonnet` directly.

The examples below keep wrapper definitions inline so you can try them as
complete environment files. To reuse a wrapper, move its `base { ... }`
expression and the imports it uses into the matching file under `lib/`,
and return that expression. Consumers then import the local file.

## Re-export helpers and add presets

`base { ... }` extends the imported object. It retains every upstream method
and adds or replaces only the fields you specify. `::` keeps helper methods
and presets out of generated manifests.

```jsonnet
local base = import 'labsonnet/helpers/affinity.libsonnet';
local lab = import 'labsonnet/main.libsonnet';
local affinity = base {
  requireApps:: base.requireNodeLabel('nodepool', ['apps']),
};
{
  worker:
    lab.new('worker', 'ghcr.io/example/worker:1.0')
    + lab.withPort({ port: 8080 })
    + lab.withAffinity(affinity.requireApps),
}
```

The wrapper still exposes methods such as `affinity.spreadAcrossNodes`.
Add presets locally without copying the upstream implementation.

## Override a helper's defaults

Keep the original arguments and change their defaults. Callers can still
supply another value, and methods you do not override remain available.

```jsonnet
local base = import 'labsonnet/helpers/pvc.libsonnet';
local pvc = base {
  new(name, namespace, size, accessModes=['ReadWriteOnce'],
      storageClassName='fast', labels={})::
    super.new(name, namespace, size,
              accessModes=accessModes,
              storageClassName=storageClassName,
              labels=labels),
};
{
  media: pvc.new('media', 'apps', '20Gi'),
  archive: pvc.new('archive', 'apps', '100Gi', storageClassName='bulk'),
}
```

Both storage classes must exist. The wrapper chooses `fast` by default;
the `archive` resource explicitly chooses `bulk`.

## Wrap the workload generator

A local service wrapper can set placement in `new` and add methods for
routing, secrets, or monitoring. All other `with*` methods are inherited.
A shared overlay can also hold settings used by several workloads.

```jsonnet
local base = import 'labsonnet/main.libsonnet';
local affinity = import 'labsonnet/helpers/affinity.libsonnet';
local svc = base {
  new(name, image)::
    super.new(name, image)
    + base.withAffinity(affinity.requireNodeLabel('nodepool', ['apps'])),
  withMetrics(port=9090)::
    base.withPort({ port: port, name: 'metrics' })
    + base.withServiceMonitor(),
  withPasswordEnvs(name, envs)::
    base.withExternalSecretEnvs(name, envs, {
      store: 'password-store', refreshPolicy: 'CreatedOnce',
    }),
};
local defaults =
  svc.withNamespace('apps')
  + svc.withEnv({ TZ: 'Europe/Athens', LOG_LEVEL: 'info' });
{
  worker:
    svc.new('worker', 'ghcr.io/example/worker:1.0')
    + defaults
    + svc.withPort({ port: 8080 })
    + svc.withMetrics()
    + svc.withPasswordEnvs('worker-login', { API_TOKEN: 'token' })
    + svc.withEnv({ LOG_LEVEL: 'debug' }),
  dashboard:
    svc.new('dashboard', 'ghcr.io/example/dashboard:1.0')
    + defaults
    + svc.withPort({ port: 8080 })
    + svc.withAffinity(affinity.preferNodeLabel('nodepool', ['compute'])),
}
```

The namespace, secret store, and matching controllers must already exist.
The worker changes one environment value; the dashboard replaces the default
placement rule. A default remains something callers can override.

## Choose the right call target

| Call                    | Use                                                                            |
| ----------------------- | ------------------------------------------------------------------------------ |
| `super.new(...)`        | Extend the inherited implementation of the method you are overriding.          |
| `base.withPort(...)`    | Reuse an upstream helper when adding a local convenience method.               |
| `self.otherMethod(...)` | Call another method through the final wrapper, including downstream overrides. |

Calling `self.new(...)` inside an override of `new` calls that same override
again and causes recursion. Calling `base.new(...)` deliberately uses the
original library object.

This distinction matters for methods that call other helpers through `self`.
For example, CNPG's `newTenant` calls `self.newCredentialReadGrant`. When
overriding `newTenant`, delegate with `super.newTenant(...)` so your local
reader defaults remain in effect. Calling `base.newTenant(...)` bypasses
those overrides.

At workload level, later scalar settings such as `withAffinity` win; ports,
mounts, and containers accumulate; environment maps merge by key. Inside a
wrapper, `defaults + overrides` lets caller keys win, but that merge is
shallow: replacing a nested object replaces the whole nested object. Arrays
concatenate only when you explicitly use `+` or a helper appends them.

When a convenience method needs the final app name or namespace, use a
[configuration callback](README.md#lazy-configuration-callbacks). Avoid reading
the app being built from the configuration you are resolving.

## Require a choice after composition

A wrapper can require explicit placement instead of supplying a default.
Check the final resource in a field so later `withAffinity` calls are visible.
`super.cluster` keeps the original Cluster generation while adding a check.

```jsonnet
local base = import 'labsonnet/helpers/cnpg.libsonnet';
local affinity = import 'labsonnet/helpers/affinity.libsonnet';
local cnpg = base {
  newCluster(name)::
    super.newCluster(name)
    + base.withNamespace('database')
    + base.withStorageClass('fast')
    + {
      cluster:
        local resource = super.cluster;
        assert std.objectHas(resource.spec.affinity, 'nodeAffinity') :
          'Choose database placement with withAffinity()';
        resource,
    },
};
{
  cluster:
    cnpg.newCluster('postgres')
    + cnpg.withInstances(3)
    + cnpg.withStorageSize('50Gi')
    + cnpg.withAffinity(affinity.requireNodeLabel('nodepool', ['database'])),
}
```

Omitting placement now fails during rendering. The check runs against the
completed builder, so placement can be added after `newCluster`.

Keep shared defaults and checks in local wrappers; keep app-specific choices
in named environment fields. Preview the result with `tk show` before using
`tk diff` and `tk apply`.
