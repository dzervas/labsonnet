local lab = import '../../labsonnet/main.libsonnet';

local app(name, image='example/app:1') =
  lab.new(name, image) + lab.withPort({ port: 8080 });

{
  stateful_pv:
    app('database')
    + lab.withType('StatefulSet')
    + lab.withHeadlessService()
    + lab.withPV('/var/lib/database', {
      name: 'database-data',
      size: '8Gi',
      storageClassName: 'fast',
    })
    + lab.withImageVolume('extensions', 'registry.example/postgres-extensions:18', 'Never')
    + lab.withVolumeMount('/usr/share/postgresql/extensions', 'extensions', readOnly=true),

  stateful_claim_template_mounts:
    app('worker')
    + lab.withType('StatefulSet')
    + lab.withHeadlessService()
    + lab.withClaimTemplate('state', { size: '2Gi', storageClassName: 'fast' })
    + lab.withClaimTemplate('state', { size: '2Gi', storageClassName: 'fast' })
    + lab.withVolumeMount('/config', 'state', subPath='config')
    + lab.withVolumeMount('/data', 'state', subPath='data'),

  existing_pvc_multiple_mounts:
    app('media-reader')
    + lab.withExistingPVC('media', 'shared-media.claim')
    + lab.withVolumeMount('/incoming', 'media')
    + lab.withVolumeMount('/movies', 'media', readOnly=true, subPath='movies')
    + lab.withVolumeMount('/series', 'media', readOnly=true, subPath='series'),

  duplicate_image_volume:
    app('duplicate-image')
    + lab.withImageVolume('extensions', 'registry.example/extensions:v1', 'IfNotPresent')
    + lab.withImageVolume('extensions', 'registry.example/extensions:v1', 'IfNotPresent')
    + lab.withVolumeMount('/opt/extensions', 'extensions', readOnly=true),

  volume_declared_after_mount:
    app('late-volume')
    + lab.withVolumeMount('/opt/extensions', 'extensions', readOnly=true)
    + lab.withImageVolume('extensions', 'registry.example/extensions:v1'),

  conflicting_volume_definitions:
    app('conflicting-volume')
    + lab.withImageVolume('shared', 'registry.example/one:v1')
    + lab.withImageVolume('shared', 'registry.example/two:v1'),

  deployment_managed_pv:
    app('invalid-database')
    + lab.withPV('/var/lib/database', { size: '8Gi' }),

  unknown_volume_reference:
    app('unknown-volume')
    + lab.withVolumeMount('/data', 'missing-volume'),

  duplicate_mount_path:
    app('duplicate-mount')
    + lab.withImageVolume('data', 'registry.example/data:v1')
    + lab.withVolumeMount('/data', 'data', readOnly=true)
    + lab.withVolumeMount('/data', 'data', readOnly=true),

  duplicate_secret_and_volume_mount_path:
    app('duplicate-cross-api-mount')
    + lab.withSecretMount('/data', 'secret-data')
    + lab.withVolumeMount('/data', 'secret-data'),

  writable_image_volume_mount:
    app('writable-image')
    + lab.withImageVolume('extensions', 'registry.example/extensions:v1')
    + lab.withVolumeMount('/opt/extensions', 'extensions'),
}
