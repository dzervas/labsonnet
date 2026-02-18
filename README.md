# labsonnet

Documentation in [docs](./docs)

To generate it:

```bash
jsonnet -S -c -m docs -J vendor/ --exec "(import 'github.com/jsonnet-libs/docsonnet/doc-util/main.libsonnet').render(import 'main.libsonnet')"
```
