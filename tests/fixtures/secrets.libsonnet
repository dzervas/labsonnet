local lab = import '../../labsonnet/main.libsonnet';

{
  secretReferences: {
    app:
      lab.new('secret-app', 'example/app:v1')
      + lab.withPort({ port: 8080 })
      + lab.withSecretEnv({ EXISTING_TOKEN: { name: 'existing-secret', key: 'token' } })
      + lab.withExternalSecretEnvs(
        'app-secret',
        { API_TOKEN: 'api-token' },
        { store: 'app-store', remoteKey: 'apps/secret-app' }
      )
      + lab.withSecretMount('/etc/tls', 'tls-secret')
      + lab.withExternalSecretMount(
        'file-secret',
        '/etc/app-secrets',
        { store: 'file-store', remoteKey: 'apps/files' }
      ),
  },
}
