local cnpg = import '../../labsonnet/helpers/cnpg.libsonnet';
local remote = { mode: 'remote', store: 'app-secrets', storeKind: 'ClusterSecretStore', remoteKey: 'app', property: 'password' };
local generated = { mode: 'generated', generatorName: 'postgres-password' };

{
  configured_cluster:
    cnpg.newCluster('shared')
    + cnpg.withNamespace('postgres')
    + cnpg.withInstances(3)
    + cnpg.withExtension('postgis', 'registry.example/postgis:18', {
      image: { pullPolicy: 'IfNotPresent' },
      extension_control_path: ['share'],
      dynamic_library_path: ['lib'],
    })
    + cnpg.withExtension('pg_trgm', 'registry.example/extensions:18')
    + cnpg.withExtension('plpgsql', null)
    + cnpg.withSharedPreloadLibraries(['pg_stat_statements', 'auto_explain'])
    + cnpg.withSharedPreloadLibraries(['auto_explain', 'pg_cron'])
    + cnpg.withClusterSpec({
      imageCatalogRef: { apiGroup: 'postgresql.cnpg.io', kind: 'ClusterImageCatalog', name: 'pg-extensions', major: 18 },
      postgresql: { parameters: { work_mem: '32MB' } },
    })
    + cnpg.withClusterSpec({ instances: 4, postgresql: { parameters: { max_connections: '200' } } }),

  remote_cross_namespace: cnpg.newTenant(
    'affine', clusterName='shared', clusterNamespace='postgres', appNamespace='apps',
    credentials=remote, resourceName='affine-tenant', secretName='affine-credentials'
  ),
  remote_same_namespace: cnpg.newTenant(
    'outline', clusterName='shared', clusterNamespace='postgres', appNamespace='postgres',
    credentials=remote
  ),
  generated_cross_namespace: cnpg.newTenant(
    'paperless', clusterName='shared', clusterNamespace='postgres', appNamespace='paperless',
    credentials=generated + {
      generatorKind: 'ClusterGenerator', replicationStore: 'postgres-secrets',
      replicationStoreKind: 'ClusterSecretStore',
    }
  ),
  generated_same_namespace: cnpg.newTenant(
    'grafana', clusterName='shared', clusterNamespace='postgres', appNamespace='postgres',
    credentials=generated
  ),

  invalid_generated_replication: cnpg.newTenant(
    'app', clusterName='shared', clusterNamespace='postgres', appNamespace='apps',
    credentials=generated
  ),
  invalid_database_identity: cnpg.newTenant(
    'app', clusterName='shared', clusterNamespace='postgres', credentials=remote,
    databaseSpec={ name: 'different' }
  ),
  invalid_role_identity: cnpg.newTenant(
    'app', clusterName='shared', clusterNamespace='postgres', credentials=remote,
    roleSpec={ passwordSecret: { name: 'different' } }
  ),
}
