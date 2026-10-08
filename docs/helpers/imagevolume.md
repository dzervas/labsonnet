# imagevolume

Build Kubernetes image volume sources and volume entries.
## Install

```
jb install github.com/dzervas/labsonnet/labsonnet@main
```

## Usage

```jsonnet
local imagevolume = import 'labsonnet/helpers/imagevolume.libsonnet'
```


## Index

* [`fn new(name, image, pullPolicy=null)`](#fn-new)
* [`fn source(image, pullPolicy=null)`](#fn-source)

## Fields

### fn new

```jsonnet
new(name, image, pullPolicy=null)
```

PARAMETERS:

* **name** (`string`)
* **image** (`string`)
* **pullPolicy** (`null`,`string`)
   - default value: `null`
   - valid values: `"Always"`, `"IfNotPresent"`, `"Never"`, `null`

Create an image volume entry. The name must be a valid Kubernetes volume name.

Example:

```jsonnet
local imagevolume = import 'labsonnet/helpers/imagevolume.libsonnet';
{
  volume: imagevolume.new('extension-files', 'ghcr.io/example/plugin:v1'),
}
```

### fn source

```jsonnet
source(image, pullPolicy=null)
```

PARAMETERS:

* **image** (`string`)
* **pullPolicy** (`null`,`string`)
   - default value: `null`
   - valid values: `"Always"`, `"IfNotPresent"`, `"Never"`, `null`

Create the `image` source object for a Kubernetes volume. `pullPolicy` may be `Always`, `IfNotPresent`, or `Never`; null omits it.

Example:

```jsonnet
local imagevolume = import 'labsonnet/helpers/imagevolume.libsonnet';
{
  image: imagevolume.source('ghcr.io/example/plugin:v1', 'IfNotPresent'),
}
```
