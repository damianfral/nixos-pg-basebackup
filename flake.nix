{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-24.11";
    flake-utils.url = "github:numtide/flake-utils";
    pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";
  };
  outputs = {
    self,
    nixpkgs,
    flake-utils,
    pre-commit-hooks,
  }:
    {
      nixosModules.pg-basebackup = {
        config,
        lib,
        pkgs,
        ...
      }:
        with lib; let
          cfg = config.services.pg-basebackup;
          pg-basebackup-script = pkgs.writeShellScript "pg-basebackup-script" ''
            set -e
            echo "Preparing PostgreSQL backup"

            # environment
            export AWS_ACCESS_KEY_ID=$(cat ${cfg.awsAccessKeyIdPath})
            export AWS_SECRET_ACCESS_KEY=$(cat ${cfg.awsSecretAccessKeyPath})
            export NOW=$(date -u +%Y%m%d-%H%M%S)
            export BACKUP_DIR_BASE=${cfg.backupBaseDir}
            export BACKUP_DIR=$BACKUP_DIR_BASE/$NOW
            export BACKUP_FILE=$BACKUP_DIR_BASE/postgresql-backup-$NOW.tar.zst

            # Create backup directory
            mkdir -p $BACKUP_DIR

            # Perform PostgreSQL base backup
            ${cfg.postgresPackage}/bin/pg_basebackup \
              -U ${cfg.postgresUser} \
              -D $BACKUP_DIR \
              ${concatStringsSep " " cfg.backupOptions}

            # Compress the backup
            ${pkgs.gnutar}/bin/tar -C $BACKUP_DIR_BASE -c $NOW  \
              | ${pkgs.zstd}/bin/zstd \
                -${toString cfg.zstdCompressionLevel} -o $BACKUP_FILE

            # Clean up temporary backup directory
            rm -r $BACKUP_DIR

            # Sync to S3
            echo "Pushing $BACKUP_FILE to ${cfg.s3Bucket}"
            ${pkgs.awscli2}/bin/aws s3 sync --include "*.tar.zst" \
               $BACKUP_DIR_BASE s3://${cfg.s3Bucket}
            echo "Backup uploaded"
          '';
        in {
          # Define the options for the module
          options.services.pg-basebackup = {
            enable = mkEnableOption "PostgreSQL backup service";

            backupOnCalendar = mkOption {
              type = types.str;
              description = "Systemd calendar event to schedule backups";
              default = "weekly";
            };

            backupBaseDir = mkOption {
              type = types.str;
              description = "Base directory for storing backups";
              default = "/data/backup/postgresql";
            };

            backupOptions = mkOption {
              type = types.listOf types.str;
              description = "Additional pg_basebackup options";
              default = ["-X" "stream" "-Ft" "-v"];
            };

            postgresUser = mkOption {
              type = types.str;
              description = ''
                PostgreSQL user to use for backup.

                To allow the backup user to perform base backups via replication
                privileges, add a line like to
                {option}`services.postgresql.authentication` (pg_hba.conf):
                ```local replication <postgresUser> trust```
              '';
              default = "postgres";
            };

            postgresPackage = mkOption {
              type = types.package;
              description = "PostgreSQL package to use";
              default = config.services.postgresql.package;
            };

            s3Bucket = mkOption {
              type = types.str;
              description = "S3 bucket to sync backups to";
            };

            awsAccessKeyIdPath = mkOption {
              type = types.str;
              description = "Path to the AWS access key ID file";
            };

            awsSecretAccessKeyPath = mkOption {
              type = types.str;
              description = "Path to the AWS secret access key file";
            };

            zstdCompressionLevel = mkOption {
              type = types.ints.between 1 19;
              description = ''
                Zstandard compression level (1-19, higher means more compression)
              '';
              default = 19;
            };
          };

          # Implementation of the module
          config = mkIf cfg.enable {
            # Systemd timer for periodic backups
            systemd.timers.pg-basebackup-timer = {
              wantedBy = ["timers.target"];
              timerConfig = {
                OnCalendar = cfg.backupOnCalendar;
                Persistent = true;
                Unit = "pg-basebackup.service";
              };
            };

            # Systemd service for performing backups
            systemd.services.pg-basebackup = {
              enable = true;
              serviceConfig = {
                Type = "oneshot";
                StandardOutput = "journal";
                StandardError = "journal";
                ExecStart = pg-basebackup-script;
              };
            };
          };
        };
    }
    // flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {inherit system;};
        precommitCheck = pre-commit-hooks.lib.${system}.run {
          src = ./.;
          hooks = {
            actionlint.enable = true;
            alejandra.enable = true;
            markdownlint.enable = true;
            nil.enable = true;
          };
        };
      in {
        devShells.default =
          pkgs.mkShell {shellHook = precommitCheck.shellHook;};
        checks = {inherit precommitCheck;};
      }
    );
}
