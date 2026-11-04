{ config, pkgs, lib, inputs, ... }:

{
  # --- Tools that need shell integration ---
  programs.zoxide.enable = true;        # gives you `z` and `zi`
  programs.atuin.enable = true;         # takes over Ctrl+R / up-arrow
  programs.pay-respects.enable = true;  # type `f` after a typo
  programs.nix-your-shell = {
    enable = true;
    package = inputs.nix-your-shell.packages.${pkgs.stdenv.hostPlatform.system}.default;
    enableZshIntegration = true;
  };
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.zsh = {
    enable = true;

    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    # Oh My Zsh Integration & Plugins
    oh-my-zsh = {
      enable = true;
      plugins = [
        "git"
        "command-not-found"
      ];
    };

    # Powerlevel10k theme
    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
    ];

    # Environment variables set on shell startup
    sessionVariables = {
      COLORTERM = "truecolor";
      LANG = "en_US.UTF-8";
      LC_ALL = "en_US.UTF-8";
      DENO_INSTALL = "$HOME/.deno";
      NVM_DIR = "$HOME/.nvm";
      VITE_ALLOW_REMOTE_WORKSPACE = "true";
    };

    # Aliases
    shellAliases = {
      # --- Existing ---
      man = "tldr";
      git = "jj git";
      jjpush = "jj bookmark set main -r @- && jj git push --remote origin --bookmark main";
      ff = "hyfetch";
      reboot = "systemctl reboot";
      jctl = "journalctl -p 3 -xb";
      nano = "fresh";
      xdg-restart = "systemctl --user restart xdg-desktop-portal-gtk.service xdg-desktop-portal-gnome.service xdg-desktop-portal-wlr.service xdg-desktop-portal.service";
      "xali" = "ssh ashlyn@40.160.23.89";
      "pulsar" = "ssh ashlyn@pulsar.ltd";

      # --- Drop-in replacements ---
      ls = "lsd";
      ll = "lsd -l";
      la = "lsd -la";
      lt = "lsd --tree";
      du = "dust";
      df = "duf";
      top = "btop";
      htop = "btop";
      ps = "procs";
      ping = "gping";
      dig = "doggo";
      http = "xh";

      # --- TUIs ---
      lg = "lazygit";
      ld = "lazydocker";
      sctl = "systemctl-tui";

      # --- NixOS (nh / nvd / nix-tree) ---
      nrs = "nh os switch /etc/nixos --hostname server";
      nrt = "nh os test /etc/nixos --hostname server";
      nrb = "nh os boot /etc/nixos --hostname server";
      nclean = "nh clean all --keep 5";
      nixdiff = "nvd diff /run/booted-system /run/current-system";
      ntree = "nix-tree /run/current-system";
    };

    # Early shell startup logic (runs before completions)
    initContent = lib.mkOrder 550 ''
      typeset -g POWERLEVEL9K_INSTANT_PROMPT=off

      # --- PATH additions ---
      typeset -U path fpath
      path=(
        $HOME/.cargo/bin
        $HOME/.local/bin
        $HOME/bin
        $HOME/.deno/bin
        $HOME/.jdks/azul-26.0.2/bin
        $HOME/.jdks/azul-25.0.4/bin
        $path
      )
      export PATH

      if [[ -d "$HOME/.zsh/completions" ]]; then
        fpath=("$HOME/.zsh/completions" $fpath)
      fi

      # --- Custom Shell Functions ---
      rebuild() (
        setopt noxtrace noverbose
        local github_token
        github_token=$(<${lib.escapeShellArg config.sops.secrets.github-token.path}) || return 1
        if [[ -z "$github_token" ]]; then
          print -u2 -- "SOPS GitHub token is empty; check systemctl --user status sops-nix."
          return 1
        fi
        export NIX_CONFIG="''${NIX_CONFIG-}"$'\n'"access-tokens = github.com=$github_token"
        export GH_TOKEN="$github_token"
        unset github_token

        cd /etc/nixos &&
          jj commit -m 'Update NixOS configuration' &&
          jj bookmark set main -r @- &&
          jj git push --remote origin --bookmark main &&
          nix --quiet flake update &&
          sudo --preserve-env=NIX_CONFIG nixos-rebuild switch --quiet --flake /etc/nixos#server
      )

      mf() {
        sudo $(fc -ln -1)
      }

      nixzsh() {
        local orig_dir="$PWD"
        cd /etc/nixos || return 1
        git add . || { cd "$orig_dir"; return 1; }
        sudo nixos-rebuild switch --flake /etc/nixos#server || { cd "$orig_dir"; return 1; }
        cd "$orig_dir" || return 1
        exec zsh
      }

      # --- External Toolchains & Shell Environment Files ---
      # Homebrew
      [[ -d "/home/linuxbrew/.linuxbrew" ]] && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

      # Rust / Cargo
      [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"

      # Deno
      [[ -f "$HOME/.deno/env" ]] && source "$HOME/.deno/env"

      # Vite+
      [[ -f "$HOME/.vite-plus/env" ]] && source "$HOME/.vite-plus/env"

      # NVM
      [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh" --no-use

      # Source custom env.d scripts
      if [[ -d "$HOME/.config/zsh/env.d" ]]; then
        for env_script in "$HOME/.config/zsh/env.d"/*.sh; do
          [[ -f "$env_script" ]] && source "$env_script"
        done
      fi

      # --- Visual Integrity & Hooks ---
      # Powerlevel10k configuration file
      [[ -f "$HOME/.p10k.zsh" ]] && source "$HOME/.p10k.zsh"

      # Fastfetch startup prompt check
      if [[ -o interactive ]] && [[ -t 1 ]] && command -v fastfetch > /dev/null 2>&1; then
        if [[ -x "$HOME/.config/fastfetch/ffbox.sh" ]]; then
          "$HOME/.config/fastfetch/ffbox.sh"
        else
          fastfetch
        fi
      fi
    '';
  };
}
