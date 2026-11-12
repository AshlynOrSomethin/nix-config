{ lib, rustPlatform, fetchCrate }:

rustPlatform.buildRustPackage rec {
  pname = "puressh";
  version = "0.2.9";

  src = fetchCrate {
    inherit pname version;
    hash = "sha256-Px7taSTMzo773hInFahY7tjnB4bn8ipKCzEKRvsZ6KU=";
  };

  cargoHash = "sha256-XgZSdDArC1uBI0zw2vVJAehUCJ6yJ3lw4+BoCMylToU=";
  buildFeatures = [ "server" "pam" "agent" ];

  meta = {
    description = "Pure Rust SSH client and server";
    homepage = "https://github.com/KarpelesLab/puressh";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
