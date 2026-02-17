// Standalone cert-manager Certificate resource builder.

{
  new(name, namespace, secretName, issuerRef, spec={})::
    {
      apiVersion: 'cert-manager.io/v1',
      kind: 'Certificate',
      metadata: { name: name, namespace: namespace },
      spec: {
        secretName: secretName,
        issuerRef: issuerRef,
      } + spec,
    },
}
