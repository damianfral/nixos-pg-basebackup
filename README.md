# NixOS PostgreSQL basebackup module

A NixOS module for automated PostgreSQL base backups with compression and S3
sync using `pg_basebackup`, `zstd`, and AWS CLI.

## Installation

### Flake Input

Add to your flake inputs:

```nix
{
  inputs = {
    nixos-pg-basebackup = {
      url = "github:damianfral/nixos-pg-basebackup";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
```

### Import Module

Add to your NixOS configuration:

```nix
{
  nixosConfigurations.my-machine = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      ...
      inputs.nixos-pg-basebackup.nixosModules.default
    ];
  };
}
```

### Basic configuration

```nix
{
  services.postgresBackup = {
    enable = true;
    s3Bucket = "your-backup-bucket";
    awsAccessKeyIdPath = "/run/secrets/aws-access-key-id";
    awsSecretAccessKeyPath = "/run/secrets/aws-secret-key";
    backupOnCalendar = "*-*-* 03:00:00"; # Daily at 3AM
    zstdCompressionLevel = 15;
  };
}
```

## Options

- `enable`  
  type: `bool`  
  default: `false`  
  description: Enable the backup service.

- `backupOnCalendar`  
  type: `string`  
  default: `"weekly"`  
  description: Systemd calendar schedule for backups.

- `backupBaseDir`  
  type: `string`  
  default: `"/data/backup/postgresql"`  
  description: Base directory for storing backups.

- `backupOptions`  
  type: `list of strings`  
  default: `["-X" "stream" "-Ft" "-v"]`  
  description: Options passed to `pg_basebackup`.

- `postgresUser`  
  type: `string`  
  default: `"postgres"`  
  description: PostgreSQL user for backups.

- `postgresPackage`  
  type: `package`  
  default: `config.services.postgresql.package`  
  description: PostgreSQL package to use.

- `s3Bucket`  
  type: `string`  
  default: `null`  
  description: Target S3 bucket name (required for S3 sync).

- `awsAccessKeyIdPath`  
  type: `string`  
  default: `null`  
  description: Path to file containing AWS access key ID.

- `awsSecretAccessKeyPath`  
  type: `string`  
  default: `null`  
  description: Path to file containing AWS secret access key.

- `zstdCompressionLevel`  
  type: `integer (1-19)`  
  default: `19`  
  description: Zstandard compression level.  
