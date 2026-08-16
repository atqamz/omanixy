{ lib, baseline }:

let
  featureNames = baseline.featureOrder;
  dependencies = baseline.featureDependencies or { };
  unknownFeatures = feature: !(builtins.elem feature featureNames);
  visit = active: feature:
    if unknownFeatures feature then
      throw "unknown Omanixy feature: ${feature}"
    else if builtins.elem feature active then
      throw "cyclic Omanixy feature dependency: ${lib.concatStringsSep " -> " (active ++ [ feature ])}"
    else
      [ feature ] ++ lib.concatLists (map (visit (active ++ [ feature ])) (dependencies.${feature} or [ ]));
  select = requested:
    lib.unique (lib.concatLists (map (visit [ ]) ([ "core" ] ++ requested)));
  invalidEdges = lib.concatLists (lib.mapAttrsToList
    (feature: values:
      lib.optional (unknownFeatures feature) "unknown feature dependency key: ${feature}"
      ++ lib.filter (dependency: unknownFeatures dependency)
        (if builtins.isList values then values else [ ]))
    dependencies);
in
assert builtins.isList featureNames;
assert invalidEdges == [ ];
{
  inherit dependencies featureNames select;
  validate = requested:
    builtins.isList requested
    && lib.all (feature: !unknownFeatures feature) requested;
}
