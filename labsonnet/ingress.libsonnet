// Ingress resource builder — dispatches to helpers/ingress.libsonnet.
// Exports meta (routing metadata).

local ingressHelper = import 'helpers/ingress.libsonnet';

{
  meta:: {
    ingress: {
      layer: 'L7',
      protocol: 'TCP',
    },
  },

  new(resourceName, serviceName, namespace, fqdn, port, ingressCfg)::
    local clusterIssuer =
      if std.objectHas(ingressCfg, 'clusterIssuer') && ingressCfg.clusterIssuer != null
      then ingressCfg.clusterIssuer
      else 'letsencrypt-prod';
    local annotations =
      if std.objectHas(ingressCfg, 'annotations') then ingressCfg.annotations else {};
    local className =
      if std.objectHas(ingressCfg, 'className') then ingressCfg.className else null;

    ingressHelper.new(resourceName, namespace, serviceName, port, fqdn, clusterIssuer, className, annotations),
}
