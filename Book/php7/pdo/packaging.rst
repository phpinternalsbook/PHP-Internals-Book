Packaging and distribution
==========================

Creating a package
------------------

PDO drivers are released via PECL; all the usual rules for PECL extensions
apply.  Packaging is accomplished by creating a valid
``package.xml`` file and then running:

.. code-block:: none

    $ pecl package

This will create a tarball named ``PDO_SKEL-X.Y.Z.tgz``.

Before releasing the package, you should test that it builds correctly; if
you've made a mistake in your ``config.m4`` or
``package.xml`` files, the package may not function
correctly.  You can test the build, without installing anything, using the
following invocation:

.. code-block:: bash

    $ pecl build package.xml

Once this is proven to work, you can test installation:

.. code-block:: bash

    $ pecl package
    $ sudo pecl install PDO_SKEL-X.Y.X.tgz

Full details about ``package.xml`` can be found in the PEAR
Programmer's documentation (`<https://pear.php.net/manual/>`_).

Releasing the package
---------------------

A PDO driver is released via the PHP Extension Community Library (PECL).
Information about PECL can be found at `<https://pecl.php.net/>`_.
