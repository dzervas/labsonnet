// Kubernetes image volume source helpers.


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

  source(image, pullPolicy=null):: imageSource(image, pullPolicy),

  new(name, image, pullPolicy=null)::
    assert validVolumeName(name) :
           'labsonnet image volume: name must be a valid Kubernetes volume DNS label';
    { name: name, image: imageSource(image, pullPolicy) },
}
