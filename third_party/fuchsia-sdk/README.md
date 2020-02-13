# Fuchsia Core SDK

This archive contains the Fuchsia Core SDK, which is a small set of
Fuchsia-specific libraries and tools required to start building and running
programs for Fuchsia.

This SDK differs from traditional SDKs in that it is not readily usable out of
the box.
For example, it does not contain any build system, favor any
toolchain, or provide standard non-Fuchsia libraries (e.g. for crypto or
graphics).
Instead, it provides metadata accurately describing its various
parts, so that this SDK can be post-processed and augmented with all the pieces
necessary for a satisfactory end-to-end development experience.

Most developers who wish to build something for Fuchsia should not need to
deal directly with this particular SDK.
They will instead consume a transformed version of it, for instance within the
development environment and ecosystem supporting a given language runtime.
Maintainers of development environments who wish to add support for Fuchsia are
the main audience for this SDK.
See [the section below](#ingestion) for a description of how to process this
SDK.

As such, the Core SDK is the representation of the Fuchsia platform developers'
contract with other developers who work with Fuchsia.
While that contract is absolutely necessary, as this SDK contains the very bits
that are unique to Fuchsia, it is not sufficient and will be complemented by
other "contracts".
The Fuchsia Core SDK is mirroring the Fuchsia platform in that respect: highly
composable and extensible, with a clear separation of concerns.


## Structure

From this point on, the root of the SDK archive will be referred to as `//`.

### Metadata

Metadata is present throughout this SDK in the form of JSON files.
Every element in this SDK has its own metadata file: for example, a FIDL library
`//fidl/fuchsia.foobar` has its metadata encoded in
`//fidl/fuchsia.foobar/meta.json`.

Every metadata file follows a JSON schema available under `//meta/schemas`: for
example, a FIDL library's metadata file conforms to
`//meta/schemas/fidl_library.json`.
Schemas act as the documentation for the metadata and may be used to facilitate
the SDK ingestion process.

### Documentation

General documentation is available under [`//docs`](docs/README.md).
Some individual SDK elements will also provide documentation directly under the
path where they are hosted in the SDK.

### Target prebuilts

Target prebuilts are hosted under `//arch/<architecture>`.
This includes a full-fledged sysroot for each available architecture.

### Source libraries

The SDK contains sources for a large number of FIDL libraries (under
`//fidl`) as well as a few C/C++ libraries (under `//pkg`).

### Host tools

Multiple host-side tools can be found under `//tools`.
This includes tools for building programs, deploying to a device, debugging,
etc...
Some information about how to use these tools can be found under `//docs`.

### Images

`//device` contains metadata describing device configurations matching a given
version of the SDK.
This metadata contains pointers to images that can be flashed onto said devices.


## Ingestion

This section describes the basic process of consuming the Core SDK and turning
it into something usable.

The main entry point for the ingestion process is a file at
`//meta/manifest.json`.
As with every metadata file in the SDK, the manifest follows a JSON schema which
is included under `//meta/schemas/manifest.json`.

This file contains a list of all the elements included in this SDK, represented
by the path to their respective metadata file.
Each element file is guaranteed to contain a top-level `type` attribute, which
may be used to apply different treatments to different element types, e.g.
generating a build file for a FIDL library vs. just moving a host tool to a
convenient location in the final development environment.

The existence of the various metadata files as well as the exhaustiveness of
their contents should make it so that the ingestion process may be fully
automated.
JSON schemas may even be used to generate code representing the metadata
containers and let the ingestion program handle idiomatic data structures
instead of raw JSON representations.

The metadata schemas will evolve over time.
In order to allow consumers of that metadata to adjust to schema changes, the
main metadata file contains a property named `schema_version` which is an opaque
version identifier for these schemas.
This version identifier will be modified every time the metadata schemas evolve
in a way that requires the attention of a developer.
SDK consumers may record the version identifier of the metadata they used to last
ingest an SDK and compare that version identifier to next SDK's version
identifier in order to detect when developer action may be required.
