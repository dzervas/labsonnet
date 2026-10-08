// Kubernetes image volume source helpers.

local d = import 'github.com/jsonnet-libs/docsonnet/doc-util/main.libsonnet';


local validVolumeName(name) =
  std.isString(name) && std.length(name) > 0 && std.length(name) <= 63
  && std.all([
    std.member(std.stringChars('abcdefghijklmnopqrstuvwxyz0123456789-'), c)
    for c in std.stringChars(name)
  ])
  && std.member(std.stringChars('abcdefghijklmnopqrstuvwxyz0123456789'), name[0])
  && std.member(std.stringChars('abcdefghijklmnopqrstuvwxyz0123456789'), name[std.length(name) - 1]);

local imageSource(image, pullPolicy=null) =
  assert std.isString(image) && std.length(image) > 0 :
         'labsonnet image volume: image reference must be a non-empty string';
  assert pullPolicy == null || std.member(['Always', 'IfNotPresent', 'Never'], pullPolicy) :
         "labsonnet image volume: pullPolicy must be 'Always', 'IfNotPresent', or 'Never'";
  { reference: image }
  + (if pullPolicy == null then {} else { pullPolicy: pullPolicy });

{

  '#':: d.pkg(
    name='imagevolume',
    url='https://github.com/dzervas/labsonnet',
    filename=std.thisFile,
    version='main',
    help='Build Kubernetes image volume sources and volume entries.',
  ) + d.package.withInstallTemplate('jb install github.com/dzervas/labsonnet/labsonnet@main')
    + d.package.withUsageTemplate("local imagevolume = import 'labsonnet/helpers/imagevolume.libsonnet'"),

  '#source':: d.fn(|||
    Create the `image` source object for a Kubernetes volume. `pullPolicy` may be `Always`, `IfNotPresent`, or `Never`; null omits it.

    Example:

    ```jsonnet
    local imagevolume = import 'labsonnet/helpers/imagevolume.libsonnet';
    {
      image: imagevolume.source('ghcr.io/example/plugin:v1', 'IfNotPresent'),
    }
    ```
  |||, [
    d.arg('image', d.T.string),
    d.argument.fromSchema('pullPolicy', {
      type: ['string', 'null'], default: null,
      enum: ['Always', 'IfNotPresent', 'Never', null],
    }),
  ]),

  source(image, pullPolicy=null):: imageSource(image, pullPolicy),

  '#new':: d.fn(|||
    Create an image volume entry. The name must be a valid Kubernetes volume name.

    Example:

    ```jsonnet
    local imagevolume = import 'labsonnet/helpers/imagevolume.libsonnet';
    {
      volume: imagevolume.new('extension-files', 'ghcr.io/example/plugin:v1'),
    }
    ```
  |||, [
    d.arg('name', d.T.string),
    d.arg('image', d.T.string),
    d.argument.fromSchema('pullPolicy', {
      type: ['string', 'null'], default: null,
      enum: ['Always', 'IfNotPresent', 'Never', null],
    }),
  ]),

  new(name, image, pullPolicy=null)::
    assert validVolumeName(name) :
           'labsonnet image volume: name must be a valid Kubernetes volume DNS label';
    { name: name, image: imageSource(image, pullPolicy) },
}
