{ lib, baseline }:

let
  featureNames = baseline.featureOrder;
  featureCapabilities = baseline.featureCapabilities or { };
  capabilityDependencies = baseline.capabilityDependencies or { };
  unknownFeatures = feature: !(builtins.elem feature featureNames);
  select = requested:
    lib.unique ([ "core" ] ++ requested);
  unknownCapabilities = capability: !(builtins.hasAttr capability capabilityDependencies);
  visitCapability = active: capability:
    if unknownCapabilities capability then
      throw "unknown Omanixy capability: ${capability}"
    else if builtins.elem capability active then
      throw "cyclic Omanixy capability dependency: ${lib.concatStringsSep " -> " (active ++ [ capability ])}"
    else
      [ capability ] ++ lib.concatLists (map (visitCapability (active ++ [ capability ])) (capabilityDependencies.${capability} or [ ]));
  resolveCapabilities = requested:
    lib.unique (lib.concatLists (map (visitCapability [ ]) (lib.concatLists (map
      (feature: featureCapabilities.${feature} or [ ])
      (select requested)))));
  invalidFeatureCapabilities = lib.concatLists (lib.mapAttrsToList
    (feature: values:
      lib.optional (unknownFeatures feature) "unknown feature capability key: ${feature}"
      ++ lib.filter (capability: unknownCapabilities capability)
        (if builtins.isList values then values else [ ]))
    featureCapabilities);
  invalidCapabilityEdges = lib.concatLists (lib.mapAttrsToList
    (capability: values:
      lib.optional (unknownCapabilities capability) "unknown capability dependency key: ${capability}"
      ++ lib.filter (dependency: unknownCapabilities dependency)
        (if builtins.isList values then values else [ ]))
    capabilityDependencies);
in
assert builtins.isList featureNames;
assert invalidFeatureCapabilities == [ ];
assert invalidCapabilityEdges == [ ];
{
  inherit featureCapabilities capabilityDependencies featureNames select resolveCapabilities;
  validate = requested:
    builtins.isList requested
    && lib.all (feature: !unknownFeatures feature) requested;
}
