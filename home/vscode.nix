# vscode.nix
{ pkgs, inputs, ... }:

let
  # Extensions compatible with the VS Code version in nixpkgs
  marketplace =
    (pkgs.nix-vscode-extensions.forVSCodeVersion pkgs.vscode.version).vscode-marketplace;

  # Workaround for nixpkgs#573021: the asar repack drops the executable bit
  # on Copilot's bundled runtime. Remove once the fix is merged.
  vscodeFixed = pkgs.vscode.overrideAttrs (old: {
    postFixup = (old.postFixup or "") + ''
      rt="$out/lib/vscode/resources/app/node_modules.asar.unpacked/@github/copilot-sdk-linux-x64/prebuilds/linux-x64/copilot-runtime"
      if [ -f "$rt" ]; then chmod +x "$rt"; fi
    '';
  });
in
{
  nixpkgs.overlays = [ inputs.nix-vscode-extensions.overlays.default ];

  # Native Wayland for Electron apps (applies at next login)
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  environment.systemPackages = with pkgs; [
    (vscode-with-extensions.override {
      vscode = vscodeFixed;

      vscodeExtensions =
        (with marketplace; [
          # Nix
          jnoortheen.nix-ide

          # Java
          redhat.java
          vscjava.vscode-java-debug
          vscjava.vscode-java-test
          vscjava.vscode-maven
          vscjava.vscode-gradle
          vscjava.vscode-java-dependency

          # C / C++
          llvm-vs-code-extensions.vscode-clangd
          ms-vscode.cmake-tools
          ms-vscode.makefile-tools

          # JSON is built in; YAML and TOML need these
          redhat.vscode-yaml
          tamasfe.even-better-toml

          # General quality of life
          editorconfig.editorconfig
          eamodio.gitlens
          usernamehw.errorlens

          # Looks
          catppuccin.catppuccin-vsc
          catppuccin.catppuccin-vsc-icons


	  #SSH
	  ms-vscode-remote.remote-ssh
    	  ms-vscode-remote.remote-ssh-edit
	  ms-vscode.remote-explorer
        ])
        ++ [
          # RPM spec syntax (attribute starts with a digit, so it needs quoting)
          marketplace."1dot75cm".rpmspec

          # Ships a native debugger binary, so use the NixOS-patched build
          vscode-extensions.vadimcn.vscode-lldb
        ];
    })

    # Tools the extensions call out to
    nixd
    nixfmt
    jdk
    clang-tools
    gcc
    gdb
    cmake
    gnumake
  ];
}
