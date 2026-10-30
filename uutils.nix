{ pkgs, ... }:

let
  coreutilsFullReplacementName =
    "coreuutils-full"
    + builtins.concatStringsSep "" (builtins.genList (_: "_") (builtins.stringLength pkgs.coreutils-full.version));
  coreutilsReplacementName =
    "coreuutils"
    + builtins.concatStringsSep "" (builtins.genList (_: "_") (builtins.stringLength pkgs.coreutils.version));
  findutilsReplacementName =
    "finduutils"
    + builtins.concatStringsSep "" (builtins.genList (_: "_") (builtins.stringLength pkgs.findutils.version));
  diffutilsReplacementName =
    "diffuutils"
    + builtins.concatStringsSep "" (builtins.genList (_: "_") (builtins.stringLength pkgs.diffutils.version));
in
{
  system.replaceDependencies.replacements = [
    {
      oldDependency = pkgs.coreutils-full;
      newDependency = pkgs.symlinkJoin {
        name = coreutilsFullReplacementName;
        paths = [ pkgs.uutils-coreutils-noprefix ];
      };
    }
    {
      oldDependency = pkgs.coreutils;
      newDependency = pkgs.symlinkJoin {
        name = coreutilsReplacementName;
        paths = [ pkgs.uutils-coreutils-noprefix ];
      };
    }
    {
      oldDependency = pkgs.findutils;
      newDependency = pkgs.symlinkJoin {
        name = findutilsReplacementName;
        paths = [ pkgs.uutils-findutils ];
      };
    }
    {
      oldDependency = pkgs.diffutils;
      newDependency = pkgs.symlinkJoin {
        name = diffutilsReplacementName;
        paths = [ pkgs.uutils-diffutils ];
      };
    }
  ];
}
