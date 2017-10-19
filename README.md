Interim images for Fedora 27 Modular Server
===========================================

This repo defines the Dockerfile, build script, and self-tests for
https://hub.docker.com/r/jamesantill/boltron-bikeshed/

It's a temporary measure to allow initial image and module testing to proceed
while the full automated pipeline for
https://fedoraproject.org/wiki/Changes/Modular_Server is still being
established.

Using the image
---------------

To run the pre-built image locally, do:

    $ docker run --rm -it jamesantill/boltron-bikeshed bash

This will give you an environment with DNF module management commands and
several modules available. To see the list of available modules, run:

    $ docker run --rm -it jamesantill/boltron-bikeshed /list-modules-py3.py

Building the image locally
--------------------------

Building the image locally requires access to pre-release F27 images, which
aren't currently pushed to a registry anywhere. To get the latest available
image and tag it locally, run:

    $ make upbase

(Note: if you encounter problems with the implicit curl download failing, try
downlading the file with a web browser and then running the command again - it
will detect that the file has already been downloaded and use that, rather
than trying to download it again)

You should now be able to build the image locally:

    $ make build

The basic image tests, which run through and check that each currently
defined module can be installed, can be run via:

    $ make tests

Checking released modules
-------------------------

The main purpose of the Boltron F27 image is to provide a locally available
pre-release testing platform for the individual modules included in the F27
Modular Server release.

The most recent test logs for the actual F27 Modular Server builds can be
found [here](https://ci.centos.org/job/fedora-qa-compose_tester/lastCompletedBuild/artifact/compose_tester/mod_install_results.log), with the error details
[here](https://ci.centos.org/job/fedora-qa-compose-tests/lastCompletedBuild/artifact/compose-tests/error.log).

Before checking the behaviour of a module in the image, confirm that it has
been built successfully by going to
`https://mbs.fedoraproject.org/module-build-service/1/module-builds/?order_desc_by=id&name=<name>`
and looking for the state of the builds with the highest ids (state=5 <-> successful).
(The reverse ordering by ID ensures that the most recent builds appear on the
first page of the results).

If this indicates that the module builds themselves are failing, investigate further by
[building the module locally](https://docs.pagure.org/modularity/development/building-modules/building-local.html)
and (once the module is building successfully locally) resubmitting the build to the
[Fedora module build service](https://docs.pagure.org/modularity/development/building-modules/building-infra.html).

Assuming that the module is building correctly in the Fedora infrastructure,
check it's working as expected by running through the following commands in
the Boltron F27 container image:

1. Ensure the listed stream names are as expected (For the initial module set,
   the expected stream names are listed in the
   [F27 Content Tracking repository](https://github.com/fedora-modularity/f27-content-tracking)):

       # dnf module list <name>

2. Check that the module is enabled by default and installs correctly (this
   may fail if the module doesn’t have valid profiles defined, for example:
   `Error: No such profile: ...`):

       # dnf module install <name>

3. If the module has more than one stream, try to switch streams (and back):

       # dnf module install <name>:<stream>

4. Remove the module (this will uninstall the module's packages, but leave the
   stream enabled, which means the packages from the module will still be
   available for dnf to install, both directly and implicitly as a dependency
   of another package):

       # dnf module remove <name>

5. Disable the module (this will make the packages contained in the module
   unavailable to dnf, preventing the installation of other packages that
   depend on the packages provided by that module):

       # dnf module disable <name>

Checking pre-release modules
----------------------------

Module releases may take a day or more to become available in the default
image, so the Boltron image provides a helper script to download built
modules directly from the Module Build Service and incorporate them into
the currently running image. For example:

    # /LOCAL.sh postgresql:9.6:20171018083530

This will download the binary artifacts for that particular build of the
PostreSQL 9.6 stream, set up a local repository for them (including the
module metadata), enable that repository, and then install the module with
its default profile.

A non-default profile can be requested by appending the profile name to the
build identifer, separated by a `/`:

    # /LOCAL.sh postgresql:9.6:20171018083530/client

The list of currently build modules and their identifiers can be found at
http://modularity.fedorainfracloud.org/modularity/mbs/.
