# FJORD — FreeBSD Jail Orchestration Runtime Descriptor

> **Captured reference.** Local copy of an external draft spec, stored here as
> context for daemonless porting work.
>
> - **Source:** <https://docs.google.com/document/d/1716U54ZimcxgxHgmdH1Q3xNnbU-d6-NDW2EXFzFD12c/edit?tab=t.0>
> - **Doc ID:** `1716U54ZimcxgxHgmdH1Q3xNnbU-d6-NDW2EXFzFD12c`
> - **Author:** ahze@ahze.net
> - **Version:** 1.0.0-Draft
> - **Captured:** 2026-06-20

---

**Status:** Draft
**Scope:** Standardized Metadata and Orchestration for OCI Containers on FreeBSD

---

## 1. Overview

This document defines a vendor-neutral standard for packaging, distributing, and installing OCI container applications on FreeBSD. The goal is to enable a simple, "one-click" app store experience while remaining fully compatible with the existing OCI and Compose ecosystems.

While standard container orchestration focuses on Linux-centric primitives, FJORD extends standard OCI formats to support FreeBSD-native features such as Jails, ZFS, VNET, and devfs rules without breaking upstream compatibility.

### 1.1 Problem Statement

Installing a self-hosted OCI application on FreeBSD currently requires manual, host-level provisioning that has no equivalent on Linux. Deployments often require creating ZFS datasets, configuring devfs rulesets, setting up VNET interfaces, and tuning specific jail parameters. Currently, none of this metadata is expressible in a standard compose.yaml.

The Linux ecosystem solved this UX friction by building vertical silos. Platforms like CasaOS and TrueNAS SCALE offer a frictionless "one-click" experience, but they achieve it by strictly controlling the entire stack—the OS distribution, the UI, and the orchestration engine.

FreeBSD possesses superior native primitives for isolating and running containers, but it does not need a proprietary vertical appliance to utilize them. It needs a horizontal standard.

FJORD defines a vendor-neutral schema for host-level hints and UI orchestration. By decoupling the app definition from the execution client, FJORD enables any compliant tool—whether a rich UI or a headless CLI—to deliver a one-click app store experience natively across a modern FreeBSD environment.

### 1.2 Goals

- **Vendor-Neutrality:** Establish an open, horizontal standard that any UI, CLI, or orchestration tool can adopt to manage containers on FreeBSD.
- **Frictionless UX:** Enable a "one-click" app store experience equivalent to Linux-based vertical appliances (e.g., CasaOS, TrueNAS SCALE) without requiring a proprietary OS.
- **Upstream Compatibility:** Utilize standard OCI formats and the Compose specification. Application maintainers should only need to append metadata, not rewrite their deployment logic.
- **Native Primitive Integration:** Expose FreeBSD's superior isolation and storage features (Jails, ZFS, VNET, devfs) declaratively within the app manifest.
- **Declarative Host Provisioning:** Shift complex host-level requirements (like ZFS dataset creation and multi-layered UID/GID permission mapping) to a pre-flight execution phase, eliminating fragile in-container initialization scripts.

### 1.3 Non-Goals

- **Building an Execution Client:** FJORD is strictly a metadata and orchestration specification. It does not dictate the language, architecture, or interface of the tools that implement it (e.g., Sylve, podman, or a headless CLI).
- **Creating a New Container Runtime:** The standard relies entirely on existing OCI-compliant runtimes and orchestrators. A compliant execution client MUST use an OCI-compatible runtime that supports FreeBSD jail parameters.
- **Cross-Platform Portability of `x-fjord`:** While the base compose.yaml remains valid on Linux, the `x-fjord` block and its associated host hints are strictly scoped to FreeBSD environments.
- **Replacing Power-User Jail Management:** FJORD targets containerized application workloads. It is not intended to replace traditional jail managers (like AppJail or Bastille) for users who want to build and manage custom, raw FreeBSD environments from the ground up.
- **Defining App Internal Architecture:** The standard dictates how an app interfaces with the FreeBSD host, but it does not impose rules on how the app structures its internal services, databases, or reverse proxies.
- **Defining a Package Distribution Format:** FJORD describes how to install and configure apps. It does not define how images are built, versioned, or published to a registry. Image build pipelines and registry conventions are out of scope.

### 1.4 Security & Threat Mitigation

FJORD's design strictly mitigates the risk of host compromise (e.g., malicious scripts attempting to run `rm -rf /`). This is achieved by being strictly declarative: the standard explicitly forbids arbitrary shell scripts or command execution within the application manifest. The execution client interacts with the host entirely through strongly-typed variables and executes its own heavily sanitized internal logic for provisioning and cleanup.

### 1.5 Assumptions

A compliant FJORD environment is assumed to provide:

- **FreeBSD 15+** — Required for modern jail parameters.
- **ZFS** — Required for dataset creation and property management (recordsize, compression, etc.).
- **OCI-Compliant Runtime** — An execution engine capable of parsing standard OCI images and applying `org.freebsd.jail.*` annotations (e.g., Podman, AppJail, containerd).
- **VNET** — Required for network-isolated jails (`if_epair` kernel module must be loaded).
- **Privilege escalation (`doas` or `sudo`)** — Host provisioning operations (ZFS dataset creation, chown, devfs rule application) require elevated privileges.
- **pkg** — Required for base image package management.

The specification relies on three components:

- **App Manifest:** A standard compose.yaml utilizing variable interpolation and an `x-fjord` extension block.
- **App Catalog:** A centralized `catalog.json` index file.
- **Execution & UI Contract:** The required execution flow for any compliant client.

---

## 2. App Manifest (compose.yaml)

FJORD utilizes the Compose Specification as its base. All application definitions MUST be valid Compose files. Tools implementing this spec should utilize a Compose-compatible orchestrator or native OCI engine to deploy the application.

FreeBSD-specific metadata and UI wizard configuration lives entirely within a reserved extension block at the root of the file: `x-fjord`.

> **Note:** It is recommended that this block include a JSON Schema reference (e.g., `https://daemonless.io/schemas/fjord-compose-v1.json`) to enable IDE autocomplete and validation.

### 2.1 Example Manifest

```yaml
services:
  plex:
    image: ghcr.io/daemonless/plex:latest
    ports:
      - "${WEB_PORT}:32400"
    volumes:
      - ${CONFIG_DATA}:/config
      - ${MEDIA_PATH}:/media:ro
    environment:
      - PLEX_CLAIM=${PLEX_TOKEN}
    annotations:
      org.freebsd.jail.param.allow.raw_sockets: "1"
    restart: unless-stopped

x-fjord:
  version: "1.0"
  info:
    name: "Plex Media Server"
    description: "Stream your personal media collection using high-performance Jails."
    category: "Media"
    class: "service"
    icon: "https://daemonless.io/icons/plex.png"

  host:
    vnet_required: true
    vnet_bridge: "${NETWORK_IFACE}"
    min_freebsd_version: "15.0"
    devfs_rules:
      - "add path 'drm/*' unhide"

  variables:
    - name: NETWORK_IFACE
      label: "Network Bridge Interface"
      type: network_interface
      default: "bridge0"

    - name: WEB_PORT
      label: "External Web Port"
      type: port
      default: "32400"

    - name: CONFIG_DATA
      label: "Config storage dataset"
      type: zfs_dataset
      default: "config"
      zfs_properties:
        recordsize: "16K"
        compression: "lz4"
      host_permissions:
        uid: 972
        gid: 972
        mode: "755"

    - name: MEDIA_PATH
      label: "Media library path"
      type: path
      default: ""

    - name: PLEX_TOKEN
      label: "Plex Claim Token"
      type: secret
```

### 2.2 The `x-fjord` Extension Block

**`version` (Required):** The version of the FJORD schema used by this block (e.g., `"1.0"`). Clients MUST check this to ensure compatibility before attempting execution.

#### 2.2.1 `info` (App Metadata)

Basic information used to render the application in a catalog or store UI.

| Field | Required | Description |
|---|---|---|
| `name` | Yes | Human-readable name of the application. |
| `description` | Yes | A short summary of the application's purpose. |
| `category` | Yes | App category (e.g., Media, Network, Storage). |
| `class` | Yes | App class — determines post-install UI behavior. See App Classes below. |
| `icon` | Yes | URL to a PNG, WebP, or SVG image. See section 2.2.1.1 for asset constraints. |
| `version` | No | The app version string. Used for client update checks. |
| `only_for_archs` | No | List of supported architectures (e.g., `[amd64]`). The UI should hide incompatible apps. |
| `requires` | No | List of app dependencies. Each entry has an `id`, optional flag, and `reason` string. |
| `health_url` | No | Relative HTTP path the UI polls to show live app status after install (e.g., `/health`). Strongly recommended when `class` is `service`. |

##### 2.2.1.1 Icon Specification and Handling

To guarantee a fast, visually consistent "App Store" UI across any compliant client, FJORD enforces strict constraints on application icons. Maintainers MUST adhere to these asset rules, and Catalog Builders MUST enforce them during index generation.

**1. Asset Constraints**

Icons defined in the `x-fjord.info.icon` field must point to a publicly accessible URL containing an image that meets the following criteria:

- **Allowed Formats:** svg (Highly Recommended), png, or webp.
- **Aspect Ratio:** MUST be exactly 1:1 (Square).
- **Dimensions:** Raster formats (png, webp) MUST be a minimum of 256x256 pixels and a maximum of 512x512 pixels. Vector formats (svg) have no dimensional limits but must use a 1:1 viewBox.
- **File Size:** MUST NOT exceed 250KB. (Target < 50KB).
- **Visual Guidelines:**
  - **No Drop Shadows:** Icons MUST NOT include baked-in drop shadows or glows. UI clients will dynamically apply their own CSS shadows based on the user's system theme.
  - **Padding:** The icon's primary subject should not touch the absolute edges of the canvas; maintainers SHOULD leave a 5-10% transparent internal margin to ensure uniform sizing in UI grids.

**2. Catalog Builder Contract (Caching)**

To prevent broken links, slow load times, and UI stuttering, the centralized App Catalog (`catalog.json`) MUST NOT serve the maintainer's raw icon URL directly to the end-user.

When a CI/CD pipeline generates the `catalog.json`, it MUST execute the following flow:

1. **Fetch:** Download the image from the `x-fjord.info.icon` URL.
2. **Validate:** Reject the build or throw a warning if the image violates the Format, Aspect Ratio, or File Size constraints.
3. **Cache:** Mirror the validated image to the Catalog's own static media host or CDN.
4. **Rewrite:** Replace the raw URL with the mirrored CDN URL in the final compiled `catalog.json`.

Example of rewriting during catalog generation:

- **Before Catalog Generation:** `https://raw.githubusercontent.com/daemonless/apps/main/apps/plex/icon.svg`
- **After Catalog Generation:** `https://cdn.daemonless.io/assets/plex-icon-e04f.svg`

##### 2.2.1.2 App Class Specification

| Class | Description | Post-Install UI Behavior |
|---|---|---|
| `service` | Runs persistently and exposes a web UI or network endpoint. | UI shows a live status indicator and an "Open" button linking to `health_url`. |
| `cli` | A run-once command-line tool invoked by the user on demand. | UI shows a usage snippet (e.g., `oci-run plex-cli ...`) instead of a status dashboard. |
| `agent` | A persistent background daemon with no user-facing interface. | UI shows running/stopped status only; no "Open" button. |
| `gui` | A graphical desktop application (reserved for future use). | TBD. |

#### 2.2.2 `host` (Host Hints)

Instructions for the Client to prepare the FreeBSD host before the container starts.

| Field | Type | Description |
|---|---|---|
| `vnet_required` | boolean | If true, the container must be deployed in a VNET jail with an independent network stack. |
| `vnet_bridge` | string | A variable reference (e.g., `"${MY_BRIDGE}"`) used to bind a `network_interface` variable to the jail bridge. |
| `devfs_rules` | list | A list of devfs rules required for hardware passthrough. |
| `min_freebsd_version` | string | The minimum host OS version required. |

> **Note:** If `vnet_required` is true and `vnet_bridge` is omitted, the client MUST default to `bridge0`.

#### 2.2.3 `variables` (UI Prompts, Resolution, & Injection)

FJORD uses standard Compose variable interpolation (`${VARIABLE_NAME}`) to inject user-provided data. The UI collects this data, generates a `.env` context, and runs Compose. The compose.yaml itself is never mutated.

| Field | Required | Description |
|---|---|---|
| `name` | Yes | The variable name found in the compose.yaml. |
| `label` | Yes | The text shown to the user in the UI wizard. |
| `type` | Yes | Determines the UI widget. |
| `default` | No | Fallback value. For `zfs_dataset` and `path` types, this MUST be a relative path or empty — the client resolves it against the app's base storage path. |
| `zfs_properties` | No | Map of ZFS properties to apply if the type is `zfs_dataset`. |
| `host_permissions` | No | Object defining UID/GID ownership and mode for path/dataset types. |

**Host Permissions Object**

Defines the required ownership and mode for the host path or dataset after resolution.

- `uid`: The numeric User ID that must own the path.
- `gid`: The numeric Group ID that must own the path.
- `mode`: The octal file mode (e.g., `"755"`) for the path.

**Prompt Types:**

| Type | Description |
|---|---|
| `path` | Plain host path selector. This enables the "Bring Your Own Data (BYOD)" workflow for legacy migrations. **Strict Rule:** If a variable of `type: path` is defined without a default value, the execution client MUST present an absolute path picker to the user. This guarantees users can easily attach and mount their existing datasets without the UI forcing the creation of a new, empty volume. |
| `zfs_dataset` | UI presents a ZFS dataset picker and creates the dataset if needed. |
| `string` | Free text input. |
| `port` | Port number; UI should validate for conflicts on the host. |
| `network_interface` | UI presents a dropdown of available host network bridges/interfaces. |
| `secret` | Masked text input; value is stored securely and injected safely. |

### 2.3 FreeBSD-Specific Jail Annotations

Applications often require specific jail privileges to function. These are declared natively in the compose.yaml under the service's `annotations:` block. The UI/execution engine must translate these into standard `jail(8)` parameters.

| Annotation | Purpose | Example Use Case |
|---|---|---|
| `org.freebsd.jail.allow.mlock` | Allows a jail to lock physical pages into memory. | Required for .NET applications (e.g., Jellyfin, Sonarr). |
| `org.freebsd.jail.allow.sysvipc` | Enables System V IPC primitives. | Required for PostgreSQL shared memory. |
| `org.freebsd.jail.param.allow.raw_sockets` | Grants access to raw network sockets. | Required for ping and network diagnostics. |

---

## 3. App Catalog Distribution

App Stores are populated via a single Catalog Index, ensuring decentralization and fast loading.

### 3.1 `catalog.json` Schema

A static JSON file served over HTTP/HTTPS, generated automatically via CI on every merge to an app repository.

```json
{
  "catalog_name": "Daemonless Official Apps",
  "catalog_version": "1.0.0",
  "maintainer": "https://daemonless.io",
  "generated": "2026-04-08T00:00:00Z",
  "apps": [
    {
      "id": "plex",
      "name": "Plex Media Server",
      "description": "Stream your personal media collection.",
      "category": "Media",
      "icon": "https://daemonless.io/icons/plex.png",
      "class": "service",
      "health_url": "/web",
      "manifest_url": "https://raw.githubusercontent.com/daemonless/apps/main/apps/plex/compose.yaml",
      "image": "ghcr.io/daemonless/plex:latest",
      "version": "1.10.6",
      "updated": "2026-04-08T00:00:00Z",
      "only_for_archs": ["amd64"]
    }
  ]
}
```

**Catalog Entry Fields**

| Field | Required | Description |
|---|---|---|
| `id` | Yes | Unique identifier for the app. |
| `name` | Yes | Display name. |
| `description` | Yes | Short description shown in the store grid. |
| `category` | Yes | App category. |
| `icon` | Yes | URL to app icon. |
| `health_url` | No | Relative HTTP path the UI uses for the "Open" button. |
| `manifest_url` | Yes | URL to the raw compose.yaml. |
| `image` | No | Primary OCI image reference. |
| `version` | No | Current app version. |
| `updated` | Yes | ISO 8601 timestamp of last change. |
| `only_for_archs` | No | List of supported architectures. Absent means all FreeBSD tier-1 architectures are supported. |
| `variants` | No | A list of alternate application configurations (e.g., database versions). If present, the UI must prompt the user to select one. |

**Variant Fields (used in `variants`)**

| Field | Required | Description |
|---|---|---|
| `id` | Yes | Unique identifier for the variant. |
| `label` | Yes | Human-readable name for the variant. |
| `default` | No | Boolean; if true, this variant is pre-selected. |
| `image` | Yes | OCI image reference for this variant. |
| `version` | Yes | App version string for this variant. |

---

## 4. Execution, UI, & Lifecycle Contract

A compliant UI or CLI tool MUST execute the following workflows to manage the full lifecycle of an application reliably:

### 4.1 Deployment (Install) Contract

1. **Load Catalog:** Fetch `catalog.json` from configured store URLs.
2. **Fetch Manifest:** Download the compose.yaml only when a user initiates an installation.
3. **Base Path Resolution (The Storage Contract):**
   - The Client identifies the global storage base for the app (e.g., `/tank/apps/<app_id>`).
   - If a variable is of type `zfs_dataset` or `path` and provides a relative default (e.g., `config`), the client MUST resolve it against the base path (e.g., `/tank/apps/<app_id>/config`) before injection.
   - If a variable is left empty by default (e.g., requesting a pre-existing media library), the client MUST prompt the user for an absolute host path and pass it through directly.
4. **Run Wizard:** Present input fields for each variable based on its type.
5. **Host Preparation (Pre-flight):**
   - Intercept `vnet_required` and configure the host network bridge, using the interface resolved from the `vnet_bridge` variable reference, defaulting to `bridge0` if `vnet_bridge` is omitted.
   - Apply any required `devfs_rules`.
   - If `zfs_dataset` is used, create the dataset applying any specified `zfs_properties`.
6. **Apply Permissions:** If `host_permissions` is defined, the client MUST execute `chown` and `chmod` on the resolved absolute path on the host.
7. **Execution:** Generate a `.env` file (or equivalent state mapping) binding user inputs and absolute paths to their variables.
   - **Variant Handling:** If the user selected a variant from the catalog, the client MUST dynamically override the `image` key. Note: Variants are defined in the catalog only. Clients installing directly from a manifest URL do not support variant selection—the `image` in the services block is used as-is.
   - Pass the final configuration to the system's designated OCI orchestrator (e.g., `oci-run`, `appjail make`, or a native Docker API).

### 4.2 Teardown (Uninstall) Contract

Because FJORD provisions host-level resources outside the OCI runtime, the client MUST handle cleanup:

1. **Stop Workload:** Instruct the OCI orchestrator to stop and remove the container instances and local networks.
2. **Resource Prompt:** The client MUST prompt the user at uninstall time whether to preserve or destroy any `zfs_dataset` paths created during install. The default answer is always to preserve.
3. **Host Cleanup:** Remove any dynamically generated `devfs_rules` specific to the application instance if they are no longer in use.

### 4.3 Update Contract

1. **State Diffing:** The client MUST persist the user's initial variable inputs attached to the deployment. When pulling a new compose.yaml from the catalog for an update, the client MUST compare the new `x-fjord.variables` block against this saved state.
2. **Delta Wizard:** If new variables have been introduced by the maintainer, the UI MUST present a prompt to the user to capture the missing variables before executing the update.
3. **Execution:** Pull the updated OCI image and instruct the orchestrator to recreate the application with the appended configuration state.

---

## Relation to porting-toolkit & daemonless work

FJORD is an *install/orchestration* standard: it describes how a compliant UI or CLI installs and configures an already-built OCI image on a FreeBSD host. The porting-toolkit and the daemonless ports it produces sit one layer below — they *build and publish* the `ghcr.io/daemonless/*` images that an FJORD manifest would reference (FJORD §1.3 explicitly lists image build/publish as a non-goal). The two are complementary: this toolkit makes the images; FJORD describes how to deploy them.

Concrete connections:

- **The images FJORD installs are what this toolkit produces.** The example manifest references `ghcr.io/daemonless/plex:latest`; the same `ghcr.io/daemonless/*` registry holds the ports built with this toolkit's `/port-package` workflow — see [`../.claude/skills/port-package/`](../.claude/skills/port-package/) and the published examples in `papra-daemonless`, `sparky-fitness-daemonless`, `immich-cli-daemonless`, and `trip-daemonless` (each repo's `Containerfile` + `compose.yaml`).

- **`x-fjord.info.class` maps onto image archetypes the toolkit already handles.** FJORD's `service` / `cli` / `agent` classes (§2.2.1.2) line up with ports built here: `papra-daemonless` and `sparky-fitness-daemonless` are `service`-class web apps; `immich-cli-daemonless` is a `cli`-class run-once tool. A future port's `compose.yaml` could gain the matching `x-fjord` block with little extra work.

- **`x-fjord.variables` + the Storage Contract overlap with existing compose conventions.** The ports' `compose.yaml` files (e.g. `sparky-fitness-daemonless/compose.yaml`, `trip-daemonless/compose.yaml`) already use `${VAR}` interpolation and bind-mount volumes — exactly the interpolation model FJORD §2.2.3 standardises. None of the current ports carry an `x-fjord` block yet (verified 2026-06-20); adopting one would be additive.

- **`host_permissions` (uid/gid/mode) is a recurring porting pain point.** UID/GID ownership of bind-mounted data is a known cookbook concern — see [`../.claude/reference/freebsd-porting-cookbook.md`](../.claude/reference/freebsd-porting-cookbook.md). FJORD §2.2.3 / §4.1 step 6 push that resolution to a declarative pre-flight phase, which is the host-side counterpart to the in-image fixes the cookbook records.

- **Jail annotations (`org.freebsd.jail.*`).** FJORD §2.3 declares jail privileges (`mlock`, `sysvipc`, `raw_sockets`) in compose annotations. These are the same host primitives the daemonless model relies on; the cookbook is the place to record any per-port annotation requirements discovered during a build.

- **Build tooling lives separately.** Image building is done with `dbuild` (`../../dbuild`), and the broader skill bundle / cookbook for authoring ports is in `daemonless-skills` (`../../daemonless-skills`) and `daemonless-claude-package-builder.md` (`../../daemonless-claude-package-builder.md`). FJORD does not touch this layer; it consumes its output.

- **Authorship.** The spec author (ahze@ahze.net) is the daemonless maintainer this toolkit's ports are PR'd to, so FJORD is upstream context for where the `ghcr.io/daemonless/*` ecosystem is heading.
