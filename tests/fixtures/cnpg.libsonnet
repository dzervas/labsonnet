local cnpg = import '../../labsonnet/helpers/cnpg.libsonnet';
local remote = { mode: 'remote', store: 'app-secrets', storeKind: 'ClusterSecretStore', remoteKey: 'app', property: 'password' };
local generated = { mode: 'generated', generatorName: 'postgres-password' };

local es = import '../../labsonnet/helpers/externalsecret.libsonnet';
local fixedReader = { name: 'shared-reader', namespace: 'readers' };
local configuredCnpg = cnpg {
  newCredentialReadGrant(role, serviceAccountName=fixedReader.name, serviceAccountNamespace=fixedReader.namespace)::
    super.newCredentialReadGrant(role, serviceAccountName, serviceAccountNamespace),
};
local flow(name, sourceNamespace, secretName=null) =
  local setup = cnpg.newCredentialInfrastructure(
    name + '-export',
    sourceNamespace,
    generatorName=name + '-generator',
    serviceAccountName=fixedReader.name,
    serviceAccountNamespace=fixedReader.namespace
  );
  local tenant = configuredCnpg.newTenant(
    name,
    'db-main',
    sourceNamespace,
    appNamespace='payments',
    credentials=cnpg.generatedCredentials(
      setup.passwordGenerator.metadata.name,
      setup.credentialStore.metadata.name
    ),
    secretName=secretName
  );
  {
    infrastructure: setup,
    tenant: tenant,
  };

{

  generated_flows: {
    customSecret: flow('billing', 'ledger', 'billing-db-auth'),
    defaultSecret: flow('events', 'ledger'),
    customNamespace: flow('archive', 'archive-db', 'archive-db-auth'),
  },
  remote_key_flow: cnpg.newTenant(
    'billing',
    'db-main',
    'ledger',
    appNamespace='payments',
    credentials=cnpg.remoteCredentials('ops-store', 'billing/password')
  ),
  ineligible_configured_tenants: {
    remote: configuredCnpg.newTenant(
      'billing',
      'db-main',
      'ledger',
      appNamespace='payments',
      credentials=cnpg.remoteCredentials('ops-store', 'billing/password')
    ),
    sameNamespace: configuredCnpg.newTenant(
      'billing',
      'db-main',
      'ledger',
      appNamespace='ledger',
      credentials=cnpg.generatedCredentials('billing-generator')
    ),
  },
  generic_tenants: {
    sameNamespace: cnpg.newTenant(
      'billing',
      'db-main',
      'ledger',
      appNamespace='ledger',
      credentials=cnpg.generatedCredentials('billing-generator')
    ),
    crossNamespace: cnpg.newTenant(
      'billing',
      'db-main',
      'ledger',
      appNamespace='payments',
      credentials=cnpg.generatedCredentials('billing-generator', 'billing-export')
    ),
  },
  unsafe_empty_grant: es.newSecretReadGrant('billing-owner', 'ledger', [], fixedReader.name),
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
    'affine',
    clusterName='shared',
    clusterNamespace='postgres',
    appNamespace='apps',
    credentials=remote,
    resourceName='affine-tenant',
    secretName='affine-credentials'
  ),
  remote_same_namespace: cnpg.newTenant(
    'outline',
    clusterName='shared',
    clusterNamespace='postgres',
    appNamespace='postgres',
    credentials=remote
  ),
  generated_cross_namespace: cnpg.newTenant(
    'paperless',
    clusterName='shared',
    clusterNamespace='postgres',
    appNamespace='paperless',
    credentials=generated {
      generatorKind: 'ClusterGenerator',
      replicationStore: 'postgres-secrets',
      replicationStoreKind: 'ClusterSecretStore',
    }
  ),
  generated_same_namespace: cnpg.newTenant(
    'grafana',
    clusterName='shared',
    clusterNamespace='postgres',
    appNamespace='postgres',
    credentials=generated
  ),

  invalid_generated_replication: cnpg.newTenant(
    'app',
    clusterName='shared',
    clusterNamespace='postgres',
    appNamespace='apps',
    credentials=generated
  ),
  invalid_database_identity: cnpg.newTenant(
    'app',
    clusterName='shared',
    clusterNamespace='postgres',
    credentials=remote,
    databaseSpec={ name: 'different' }
  ),
  invalid_role_identity: cnpg.newTenant(
    'app',
    clusterName='shared',
    clusterNamespace='postgres',
    credentials=remote,
    roleSpec={ passwordSecret: { name: 'different' } }
  ),
}
