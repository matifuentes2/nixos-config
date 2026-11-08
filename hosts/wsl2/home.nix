{
  config,
  lib,
  pkgs,
  username,
  ...
}:

let
  glazewmConfig = import ./windows/glazewm.nix { inherit lib pkgs; };
  t3Cli = pkgs.callPackage ../../packages/t3-cli.nix { };

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

      # WSL's systemd services do not keep the distribution alive. A Windows
      # logon task owns a persistent WSL command, allowing t3-server to run
      # without an open terminal. Reconcile and start it on every activation.
      # Restart settings only cover launch failures, not the command exiting
      # when WSL stops the VM, so a repeating trigger relaunches it within five
      # minutes; IgnoreNew skips repeats while it is still running.
      # Dollar expressions below belong to PowerShell, not the shell.
      # shellcheck disable=SC2016
      /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe \
        -NoProfile -NonInteractive -Command '
          $ErrorActionPreference = "Stop"
          $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
          $distribution = $env:WSL_DISTRO_NAME
          if (-not $distribution) { $distribution = "NixOS" }
          if ($distribution -notmatch "^[A-Za-z0-9._-]+$") { throw "Invalid WSL distribution name" }
          $name = "NixOS-WSL-T3-$distribution-$($identity.User.Value)"
          $action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\wsl.exe" `
            -Argument "--distribution $distribution --exec /run/current-system/sw/bin/sleep infinity"
          $trigger = @(
            New-ScheduledTaskTrigger -AtLogOn -User $identity.Name
            New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5)
          )
          $principal = New-ScheduledTaskPrincipal -UserId $identity.Name -LogonType Interactive -RunLevel Limited
          $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) `
            -MultipleInstances IgnoreNew -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
          Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger `
            -Principal $principal -Settings $settings -Force | Out-Null
          Start-ScheduledTask -TaskName $name
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
    t3Cli
    pkgs.tree
    windowsConfigSync
  ];

  home.shellAliases.rebuild = "sudo nixos-rebuild switch --flake ~/nixos-config#wsl2";

  home.sessionVariables.T3CODE_PORT = "3773";

  # Headless T3 Code server. The native Windows T3 Code app is the UI and
  # connects to it through WSL's localhost forwarding; see
  # docs/t3-code-wsl2.md. Binding 0.0.0.0 also keeps the firewall-allowed port
  # reachable over the network. It shares ~/.t3 with the Linux desktop app,
  # which is therefore not installed on this host.
  systemd.user.services.t3-server = {
    Unit = {
      Description = "T3 Code server";
      After = [ "network.target" ];
    };
    Service = {
      ExecStart = "${lib.getExe t3Cli} serve --host 0.0.0.0 --port 3773 --no-browser ${config.home.homeDirectory}";
      WorkingDirectory = config.home.homeDirectory;
      # Agents (claude, codex, git, ...) are resolved from the user profile.
      Environment = [
        "PATH=${config.home.profileDirectory}/bin:/run/current-system/sw/bin:/run/wrappers/bin"
      ];
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "default.target" ];
  };

  # GlazeWM and Kanata run on the Windows host; see docs/wsl2-glazewm.md.
  # A failed copy must not block activation, because interop can be disabled
  # per instance.
  home.activation.deployWindowsConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${lib.getExe windowsConfigSync} || warnEcho "Windows configs not deployed; run windows-config-sync from a WSL shell"
  '';
}
