# Anylist Server (Nixified)

This project provides a server to interact with your Anylist lists via a REST API. It was originally a Home Assistant Addon and Docker container, but has been converted to be packaged and deployed using [Nix](https://nixos.org/).

If you're looking for a Home Assistant integration to manage your Anylist lists via intents, service calls, and the [to-do list feature](https://www.home-assistant.io/integrations/todo), you might still be able to use the [Anylist custom integration](https://github.com/kevdliu/hacs-anylist) alongside this server, though you'll need to configure the integration to point to the URL where you deploy this Nix-based server.

## Installation & Usage (Nix Flake)

This repository is now a Nix flake, providing a package for the Anylist server and a NixOS module for deploying it as a service.

### Prerequisites

You need to have Nix installed with flake support enabled. See the [official Nix documentation](https://nixos.org/download.html) for installation instructions.

### Building the Package

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/kevdliu/hassio-addon-anylist # Or your fork
    cd hassio-addon-anylist
    ```

2.  **Update `npmDepsHash` in `flake.nix`:**
    The `flake.nix` file contains a placeholder for `npmDepsHash`. You need to calculate the correct hash:
    *   Attempt to build the package:
        ```bash
        nix build .#anylist
        ```
    *   This command will likely fail with a hash mismatch error, providing you with the correct hash. It will look something like this:
        ```
        error: hash mismatch in fixed-output derivation '/nix/store/...-node-modules-anylist-1.0.0.drv':
                 specified: sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
                    got:    sha256-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx=
        ```
    *   Open `flake.nix` and replace the placeholder `sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=` with the `got:` hash value.

3.  **Build the package again:**
    ```bash
    nix build .#anylist
    ```
    This will create a `result` symlink in the current directory (e.g., `./result/bin/anylist-server`).

4.  **Running the server manually:**
    You can run the server directly using the compiled package:
    ```bash
    ./result/bin/anylist-server --email "your-email" --password "your-password" --port 8080
    ```
    See the "Configuration Options" section below for all available arguments.

### Using the NixOS Module

The flake provides a NixOS module to run the Anylist server as a systemd service.

1.  **Add the flake to your NixOS configuration:**
    In your `/etc/nixos/flake.nix` (or wherever your system flake is located):
    ```nix
    {
      inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
        # Add this repository
        anylist-server = {
          url = "github:kevdliu/hassio-addon-anylist"; # Or your fork's URL
          # Optional: if you want to pin to a specific commit
          # rev = "your-commit-hash";
        };
      };

      outputs = { self, nixpkgs, anylist-server }: {
        nixosConfigurations.your-hostname = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux"; # Or your system architecture
          modules = [
            ./configuration.nix
            anylist-server.nixosModules.default # Import the module
          ];
        };
      };
    }
    ```

2.  **Configure the service in your `configuration.nix`:**
    ```nix
    { ... }:

    {
      services.anylist = {
        enable = true;
        email = "your-anylist-email@example.com";
        passwordFile = "/path/to/your/anylist-password-file"; # IMPORTANT: Secure this file!
        # credentialsFileDir = "/var/lib/anylist"; # Default, stores .anylist-credentials.json
        # port = 8080; # Default
        # defaultList = "Groceries"; # Optional
        # ipFilter = "192.168.1.";   # Optional
      };

      # Example: Create a secrets file for the password
      # You'll need to ensure this file is created with the actual password.
      # For example, using agenix, sops-nix, or manual creation with restrictive permissions.
      # Make sure the 'anylist' user (or the user you configure) can read it.
      # environment.secrets.anylist-password = {
      #   file = /path/to/your/anylist-password-file;
      #   owner = config.services.anylist.user;
      #   group = config.services.anylist.group; # Or a group the user is in
      #   permissions = "0400";
      # };
    }
    ```
    **Security Note:** The `passwordFile` should contain your AnyList password and nothing else. Ensure it is readable only by the user the Anylist service runs as (default: `anylist` user). Tools like `agenix` or `sops-nix` are recommended for managing secrets in NixOS.

3.  **Rebuild your NixOS system:**
    ```bash
    sudo nixos-rebuild switch --flake .#your-hostname
    ```

## Configuration Options (Command-line / NixOS Module)

The server and the NixOS module accept the following configuration options:

| Argument / NixOS Option | Environment Variable | Description                                                                 | NixOS Default | CLI Default | Required |
| ----------------------- | -------------------- | --------------------------------------------------------------------------- | ------------- | ----------- | -------- |
| `--port` / `port`       | `PORT`               | Port for the server to listen on.                                           | `8080`        | `8080`      | No       |
| `--email` / `email`     | `EMAIL`              | Anylist account email.                                                      | *None*        | *None*      | Yes      |
| `--password` / (via `passwordFile`) | `PASSWORD` | Anylist account password. (Module uses `passwordFile` for security)       | *None*        | *None*      | Yes      |
| `--credentials-file` / (managed by `credentialsFileDir`) | `CREDENTIALS_FILE` | Path to store/read the `.anylist-credentials.json` session file. Module manages this in `credentialsFileDir`. | (`/var/lib/anylist/.anylist-credentials.json`) | *None*   | No       |
| `--ip-filter` / `ipFilter` | `IP_FILTER`        | Allow requests only from specified IP prefix (e.g., "192.168.1.").          | `null`        | *None*      | No       |
| `--default-list` / `defaultList` | `DEFAULT_LIST`   | Name of Anylist list if not specified in request.                         | `null`        | *None*      | No       |

**NixOS Module Specific Options:**
*   `services.anylist.enable`: (Boolean) Enable the service. Default: `false`.
*   `services.anylist.passwordFile`: (Path) Path to a file containing the AnyList password. **Required if enabled.**
*   `services.anylist.credentialsFileDir`: (Path) Directory to store the credentials JSON file. Default: `/var/lib/anylist`. The service user will own this directory.
*   `services.anylist.user`: (String) User to run the service as. Default: `anylist`.
*   `services.anylist.group`: (String) Group to run the service as. Default: `anylist`.

## API Usage

The API endpoints remain the same as described in the original project:

### Adding an item
Endpoint: POST /add
Body: JSON payload.
| Field  | Description        |
| ------ | ------------------ |
| name   | Name of the item   |
| notes  | Notes for the item |
| list   | Name of the list   |
Response: 200 if added, 304 if item is already on the list.

### Removing an item
Endpoint: POST /remove
Body: JSON payload.
| Field | Description      |
| ----- | ---------------- |
| name  | Name of the item |
| id    | ID of the item   |
| list  | Name of the list |
Note: Either `name` or `id` is required, but not both.
Response: 200 if removed, 304 if item is not on the list.

### Updating an item
Endpoint: POST /update
Body: JSON payload.
| Field   | Description             |
| ------- | ----------------------- |
| id      | ID of the item          |
| name    | New name for the item   |
| checked | New status for the item |
| notes   | Notes for the item      |
| list    | Name of the list        |
Note: Either `name` or `checked` is required. Both can be provided in order to update both properties.
Response: 200 if updated.

### Check or unchecking an item
Endpoint: POST /check
Body: JSON payload.
| Field   | Description             |
| ------- | ----------------------- |
| name    | Name of the item        |
| checked | New status for the item |
| list    | Name of the list        |
Response: 200 if updated, 304 if item status is already the same as `checked`.

### Getting items
Endpoint: GET /items
Query Parameters:
| Field | Description      |
| ----- | ---------------- |
| list  | Name of the list |
Response: 200 with JSON payload.
| Field  | Description      |
| ------ | ---------------- |
| items  | List of items    |

### Getting lists
Endpoint: GET /lists
Response: 200 with JSON payload.
| Field  | Description      |
| ------ | ---------------- |
| lists  | List of lists    |

## Docker Support
Docker support (Dockerfile, docker-compose.yaml, etc.) has been removed in favor of the Nix flake.

## Credit
This server is made possible by the [Anylist library](https://github.com/codetheweb/anylist) created by [@codetheweb](https://github.com/codetheweb). The original Home Assistant addon was by [@kevdliu](https://github.com/kevdliu).
Nix packaging and module by Your Name/Handle Here (or remove this line).
