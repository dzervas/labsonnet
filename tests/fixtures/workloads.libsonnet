local lab = import '../../labsonnet/main.libsonnet';
local app = lab.new('identity', 'example:v1') + lab.withPort({ port: 8080 });

{
  labeled_deployment: app + lab.withPodLabels({ team: 'platform', app: 'identity' }),
  labeled_statefulset: app + lab.withType('StatefulSet') + lab.withHeadlessService()
                          + lab.withPodLabels({ team: 'platform' }),
  invalid_identity_label: app + lab.withPodLabels({ app: 'other' }),
  invalid_generated_label: app + lab.withPodLabels({ name: 'other' }),
  invalid_statefulset_label: app + lab.withType('StatefulSet') + lab.withHeadlessService()
                               + lab.withPodLabels({ 'app.kubernetes.io/name': 'other' }),
  security_defaults: app,
  security_overrides: app + lab.withPodSecurityContext({
    fsGroup: null, fsGroupChangePolicy: null,
    runAsNonRoot: false, runAsUser: 0, supplementalGroups: [],
  }),
}
