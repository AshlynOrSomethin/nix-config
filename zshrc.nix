{ config, pkgs, lib, ... }:

{
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
      rebuild = "cd /etc/nixos && sudo nix flake update && jj commit -m 'Update NixOS configuration' && sudo nixos-rebuild switch --flake /etc/nixos";
      git = "jj git";
      ff = "hyfetch";
      reboot = "systemctl reboot";
      jctl = "journalctl -p 3 -xb";
      nano = "fresh";
      xdg-restart = "systemctl --user restart xdg-desktop-portal-gtk.service xdg-desktop-portal-gnome.service xdg-desktop-portal-wlr.service xdg-desktop-portal.service";
      "xali" = "ssh ashlyn@40.160.23.89";
      "pulsar" = "ssh ashlyn@pulsar.ltd";
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
      mf() {
        sudo $(fc -ln -1)
      }

      nixzsh() {
        local orig_dir="$PWD"
        cd /etc/nixos || return 1
        git add . || { cd "$orig_dir"; return 1; }
        sudo nixos-rebuild switch || { cd "$orig_dir"; return 1; }
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
        "$HOME/.config/fastfetch/ffbox.sh"
      fi
    '';
  };
}
