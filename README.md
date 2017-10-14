Interim images for Fedora 27 Modular Server
===========================================

This repo defines the Dockerfile, build script, and self-tests for
https://hub.docker.com/r/jamesantill/boltron-27/

It's a temporary measure to allow initial image and module testing to proceed
while the full automated pipeline for
https://fedoraproject.org/wiki/Changes/Modular_Server is still being
established.

Using the image
---------------

To run the pre-built image locally, do:

    $ docker run --rm -it jamesantill/boltron-27 bash

This will give you an environment with DNF module management commands and
several modules available. To see the list of available modules, run:

    $ docker run --rm -it jamesantill/boltron-27 /list-modules-py3.py

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

