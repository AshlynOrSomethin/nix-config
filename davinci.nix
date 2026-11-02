{ config, lib, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    (davinci-resolve-studio.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ perl ];
      postInstall = ''
        ${old.postInstall or ""}
        
        # 1. Locate and patch the resolve binary dynamically within the package store output
        find "$out" -name "resolve" -type f -path "*/bin/resolve" | while read -r file; do
          echo "Patching binary: $file"
          
          perl -pi -e 's/\x03\x00\x89\x45\xFC\x83\x7D\xFC\x00\x74\x11\x48\x8B\x45\xC8\x8B/\x03\x00\x89\x45\xFC\x83\x7D\xFC\x00\xEB\x11\x48\x8B\x45\xC8\x8B/g' "$file"
          
          perl -pi -e 's/\x74\x11\x48\x8B\x45\xC8\x8B\x55\xFC\x89\x50\x58\xB8\x00\x00\x00/\xEB\x11\x48\x8B\x45\xC8\x8B\x55\xFC\x89\x50\x58\xB8\x00\x00\x00/g' "$file"
          
          perl -0777 -pi -e 's/(\x40\x84\xED)\x74(.\xBF\x16\x00\x00\x00\BE.\x01\x00\x00\xE8)/$1\x75$2/g' "$file"
        done

        # 2. Generate the license file inside the package installation structure
        # (DaVinci Resolve looks for this in its home/license directory paths)
        LICENSE_DIR="$out/share/DaVinciResolve/.license"
        mkdir -p "$LICENSE_DIR"
        
        printf "LICENSE blackmagic davinciresolvestudio 999999 permanent uncounted\n hostid=ANY issuer=CGP customer=CGP issued=28-dec-2023\n akey=0000-0000-0000-0000 _ck=00 sig=\"00\"\n" > "$LICENSE_DIR/blackmagic.lic"
      '';
    }))
  ];

  environment.variables = {
    RUSTICL_ENABLE = "radeonsi";
  };

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      mesa.opencl # Enables Rusticl (OpenCL) support
    ];
  };
}
