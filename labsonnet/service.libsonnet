local k = import 'k.libsonnet';

local service = k.core.v1.service;
local servicePort = k.core.v1.servicePort;

local servicePorts(ports) =
  std.map(
    function(p)
      servicePort.newNamed(p.name, p.port, p.port)
      + servicePort.withProtocol(p.protocol),
    ports
  );

{
  new(name, cfg)::
    service.new(name, cfg.labels, servicePorts(cfg.servicePorts))
    + service.metadata.withNamespace(cfg.namespace)
    + service.metadata.withLabels(cfg.labels)
    + service.spec.withType(cfg.serviceType),

  newHeadless(name, cfg)::
    service.new(name, cfg.labels, servicePorts(cfg.headlessServicePorts))
    + service.metadata.withNamespace(cfg.namespace)
    + service.metadata.withLabels(cfg.labels)
    + service.spec.withClusterIP('None')
    + (if cfg.headlessPublishNotReady
       then service.spec.withPublishNotReadyAddresses(true)
       else {}),
}
