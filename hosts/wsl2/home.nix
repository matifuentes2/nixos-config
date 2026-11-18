{
  lib,
  pkgs,
  username,
  ...
}:

let
  glazewmConfig = import ./windows/glazewm.nix { inherit lib pkgs; };

  # Copy the Windows-side configuration into the Windows profile.
  # Profile paths are resolved at runtime through WSL interop, so no
  # Windows account name is tracked in this repository.
  windowsConfigSync = pkgs.writeShellApplication {
    name = "windows-config-sync";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      cmd=/mnt/c/Windows/System32/cmd.exe
      if [[ ! -x "$cmd" ]]; then
        echo "windows-config-sync: Windows interop is unavailable ($cmd not found)" >&2
        exit 1
      fi

      # Resolve a Windows environment variable such as APPDATA to a WSL path.
      win_dir() {
        local value drive rest
        value=$(cd /mnt/c && "$cmd" /c "echo %$1%" | tr -d '\r')
        if [[ ! "$value" =~ ^[A-Za-z]:\\ ]]; then
          echo "windows-config-sync: unexpected %$1% path: $value" >&2
          return 1
        fi
        drive=''${value:0:1}
        rest=''${value:2}
        printf '/mnt/%s%s\n' "''${drive,,}" "''${rest//\\//}"
      }

      deploy() {
        install -Dm644 "$1" "$2"
        echo "windows-config-sync: wrote $2"
      }

      profile=$(win_dir USERPROFILE)
      appdata=$(win_dir APPDATA)
      deploy ${glazewmConfig} "$profile/.glzr/glazewm/config.yaml"
      deploy ${./windows/kanata.kbd} "$appdata/kanata/kanata.kbd"
      deploy ${./windows/wslconfig} "$profile/.wslconfig"

      # Remove the old standalone server's keepalive task for this user/distro.
      # shellcheck disable=SC2016
      /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe \
        -NoProfile -NonInteractive -Command '
          $ErrorActionPreference = "Stop"
          $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
          $distribution = $env:WSL_DISTRO_NAME
          if (-not $distribution) { $distribution = "NixOS" }
          if ($distribution -notmatch "^[A-Za-z0-9._-]+$") { throw "Invalid WSL distribution name" }
          $name = "NixOS-WSL-T3-$distribution-$($identity.User.Value)"
          $task = Get-ScheduledTask | Where-Object { $_.TaskName -eq $name -and $_.TaskPath -eq "\" }
          if ($task) {
            $task | Stop-ScheduledTask
            $task | Unregister-ScheduledTask -Confirm:$false
          }
        '

      # Windows' built-in Office key otherwise launches Microsoft 365 Chat.
      # Override the protocol handler with a no-op for the current user.
      /mnt/c/Windows/System32/reg.exe add \
        'HKCU\Software\Classes\ms-officeapp\Shell\Open\Command' \
        /ve /t REG_SZ /d rundll32 /f
    '';
  };
in
{
  # The Linux module currently owns the Raspberry Pi's Hyprland desktop, so a
  # terminal-oriented WSL environment imports only the portable shared module.
  imports = [
    ../../modules/home/common.nix
  ];

  home.username = username;
  home.homeDirectory = "/home/${username}";

  # Keep this at the Home Manager version used for the first WSL2 activation.
  home.stateVersion = "26.11";

  home.packages = [
    pkgs.tree
    windowsConfigSync
  ];

  home.shellAliases.rebuild = "sudo nixos-rebuild switch --flake ~/nixos-config#wsl2";

  # Stop the retired server on upgrades, before its unit disappears.
  # The Windows app manages its own WSL backend. Preserve ~/.t3 data.
  home.activation.retireT3Server = lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ] ''
    if ${pkgs.systemd}/bin/systemctl --user is-active --quiet t3-server.service; then
      run ${pkgs.systemd}/bin/systemctl --user stop t3-server.service
    fi
  '';

  # GlazeWM and Kanata run on the Windows host; see docs/wsl2-glazewm.md.
  # A failed copy must not block activation, because interop can be disabled
  # per instance.
  home.activation.deployWindowsConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${lib.getExe windowsConfigSync} || warnEcho "Windows configs not deployed; run windows-config-sync from a WSL shell"
  '';
}
