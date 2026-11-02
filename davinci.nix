{ config, lib, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    (davinci-resolve-studio.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ perl ];
      postInstall = ''
        ${old.postInstall or ""}

        # 1. Locate and patch the resolve binaries inside the inner structure before packaging
        find "$out" -name "resolve" -type f | while read -r file; do
          echo "Patching resolve binary: $file"
          perl -pi -e 's/\x03\x00\x89\x45\xFC\x83\x7D\xFC\x00\x74\x11\x48\x8B\x45\xC8\x8B/\x03\x00\x89\x45\xFC\x83\x7D\xFC\x00\xEB\x11\x48\x8B\x45\xC8\x8B/g' "$file" || true
          perl -pi -e 's/\x74\x11\x48\x8B\x45\xC8\x8B\x55\xFC\x89\x50\x58\xB8\x00\x00\x00/\xEB\x11\x48\x8B\x45\xC8\x8B\x55\xFC\x89\x50\x58\xB8\x00\x00\x00/g' "$file" || true
          perl -0777 -pi -e 's/\x74(.\xBF\x16\x00\x00\x00\BE.\x01\x00\x00\xE8..\\x05)/\x75$1/g' "$file" || true
        done

        # 2. Inject the license file into all paths searched by the application runtime
        for loc in "$out/share/DaVinciResolve" "$out/libs" "$out/bin"; do
          mkdir -p "$loc/.license"
          printf "LICENSE blackmagic davinciresolvestudio 999999 permanent uncounted\n hostid=ANY issuer=CGP customer=CGP issued=28-dec-2023\n akey=0000-0000-0000-0000 _ck=00 sig=\"00\"\n" > "$loc/.license/blackmagic.lic"
        done
      '';
    }))
  ];

  environment.variables = {
    RUSTICL_ENABLE = "radeonsi";
  };

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      mesa.opencl
    ];
  };
}
