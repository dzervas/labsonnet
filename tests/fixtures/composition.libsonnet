local lab = import '../../labsonnet/main.libsonnet';
local reusable = lab.withEnv(function(ctx) { INSTANCE: ctx.name + '/' + ctx.namespace });

{
  composition:
    lab.new('compose-app', 'example/app:v1')
    + lab.withPort({ port: 8080, name: 'web' })
    + lab.withPort({ port: 9090, name: 'metrics' })
    + lab.withReplicas(2)
    + lab.withReplicas(3)
    + lab.withEnv({ FIRST: 'one', REPLACED: 'old' })
    + lab.withEnv({ SECOND: 'two', REPLACED: 'new' }),

  callbackContext:
    lab.new('callback-app', 'example/callback:v1')
    + lab.withEnv(function(ctx) {
      APP_NAME: ctx.name,
      APP_NAMESPACE: ctx.namespace,
    })
    + lab.withPort(function(ctx) {
      port: 8123,
      name: ctx.name + '-web',
      httpRoute: {
        fqdn: ctx.name + '.example.test',
        gateway: { name: 'edge', namespace: ctx.namespace },
      },
    })
    + lab.withNamespace('callback-ns'),

  reusable_callbacks: {
    first: lab.new('first', 'example:v1') + reusable + lab.withPort({ port: 8080 }) + lab.withNamespace('one'),
    second: lab.new('second', 'example:v1') + reusable + lab.withPort({ port: 8080 }) + lab.withNamespace('two'),
  },
}
