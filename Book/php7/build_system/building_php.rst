.. highlight:: bash

.. _building_php:

Building PHP
============

This chapter explains how you can compile PHP in a way that is suitable for development of extensions or core
modifications. We will only cover builds on Unixoid systems. If you wish to build PHP on Windows, you should take a look
at the `step-by-step build instructions`__ in the PHP wiki [#]_.

This chapter also provides an overview of how the PHP build system works and which tools it uses, but a detailed
description is outside the scope of this book.

.. __: https://wiki.php.net/internals/windows/stepbystepbuild_sdk_2

.. [#] Disclaimer: We are not liable for any adverse health effects caused by the attempt to compile PHP on Windows.

Why not use packages?
---------------------

If you are currently using PHP, you likely installed it through your package manager, using a command like
``sudo apt-get install php``. Before explaining the actual compilation you should first understand why doing your own
compile is necessary and you can't just use a prebuilt package. There are multiple reasons for this:

Firstly, the prebuilt package only contains the resulting binaries, but misses other things that are necessary to
compile extensions, e.g. header files. This can be easily remedied by installing a development package, which is
typically called ``php-dev``. To facilitate debugging with valgrind or gdb one could additionally install debug symbols,
which are usually available as another package called ``php-dbg``.

But even if you install headers and debug symbols, you'll still be working with a release build of PHP. This means that
it will be built with high optimization level, which can make debugging very hard. Furthermore release builds do not
enable assertions and do not generate warnings about memory leaks. Additionally, prebuilt packages don't enable
thread safety, which may be helpful to ensure your extension builds in a thread-safe configuration.

Another issue is that nearly all distributions apply additional patches to PHP. In some cases these patches only
contain minor changes related to configuration, but some distributions make use of highly intrusive patches like
Suhosin. Some of these patches are known to introduce incompatibilities with low-level extensions like opcache.

PHP only provides support for the software as provided on `php.net`_ and not for the distribution-modified versions. If
you want to report bugs, submit patches or make use of our help channels for extension-writing, you should always work
against the official PHP version. When we talk about "PHP" in this book, we're always referring to the officially
supported version.

.. _`php.net`: http://www.php.net

Obtaining the source code
-------------------------

Before you can build PHP you first need to obtain its source code. There are two ways to do this: You can either
download an archive from `PHP's download page`_ or clone the git repository from `Github`_.

The build process is slightly different for both cases: The git repository doesn't bundle a ``configure`` script, so
you'll need to generate it using the ``buildconf`` script, which makes use of autoconf. Furthermore the git repository
does not contain a pregenerated lexer and parser, so you'll also need to have re2c and bison installed.

We recommend to checkout out the source code from git, because this will provide you with an easy way to keep your
installation updated and to try your code with different versions. A git checkout is also required if you want to
submit patches or pull requests for PHP.

To clone the repository, run the following commands in your shell::

    ~> git clone https://github.com/php/php-src.git
    ~> cd php-src
    # by default you will be on the master branch, which is the current
    # development version. You can check out a stable branch instead:
    ~/php-src> git checkout PHP-8.1

If you have issues with the git checkout, take a look at the `Git FAQ`_ on the PHP wiki. The Git FAQ also explains how
to setup git if you want to contribute to PHP itself. Furthermore it contains instructions on setting up multiple
working directories for different PHP versions. This can be very useful if you need to test your extensions or changes
against multiple PHP versions and configurations.

Before continuing, you should also install some basic build dependencies with your package manager (you'll likely
already have the first three installed by default):

* ``gcc`` and ``g++``  or some other compiler toolchain.
* ``libc-dev``, which provides the C standard library, including headers.
* ``make``, which is the build-management tool PHP uses.
* ``autoconf``, which is used to generate the ``configure`` script.

  * 2.59 or higher (for PHP 7.0-7.1)
  * 2.64 or higher (for PHP 7.2)
  * 2.68 or higher (for PHP 7.3 and higher)
* ``libtool``, which helps manage shared libraries.
* ``bison`` which is used to generate the PHP parser.

  * 2.4 or higher (for PHP 7.0-7.3)
  * 3.0 or higher (for PHP 7.4 and higher)
* ``re2c``, which is used to generate the PHP lexer.

  * Optional for PHP <= 7.3.
  * 0.13.4 or higher (for PHP 7.4 and higher)

On Debian/Ubuntu you can install all these with the following command::

    ~/php-src> sudo apt-get install build-essential autoconf libtool bison re2c pkg-config

Depending on the extensions that you enable during the ``./configure`` stage PHP will need a number of additional
libraries. When installing these, check if there is a version of the package ending in ``-dev`` or ``-devel`` and
install them instead. The packages without ``dev`` typically do not contain necessary header files. For example a
default PHP build will require libxml and libsqlite3, which you can install via the ``libxml2-dev`` and
``libsqlite3-dev`` packages.

.. _PHP's download page: http://www.php.net/downloads.php
.. _git.php.net: http://git.php.net
.. _Github: http://www.github.com/php/php-src
.. _Git FAQ: https://wiki.php.net/vcs/gitfaq

Build overview
--------------

Before taking a closer look at what the individual build steps do, here are the commands you need to execute for a
"default" PHP build::

    ~/php-src> ./buildconf     # only necessary if building from git
    ~/php-src> ./configure
    ~/php-src> make -jN

For a fast build, replace ``N`` with the number of CPU cores you have available (you can run ``nproc`` to determine
this).

By default PHP will build binaries for the CLI and CGI SAPIs, which will be located at ``sapi/cli/php`` and
``sapi/cgi/php-cgi`` respectively. To check that everything went well, try running ``sapi/cli/php -v``.

Additionally you can run ``sudo make install`` to install PHP into ``/usr/local``. The target directory can be changed
by specifying a ``--prefix`` in the configuration stage::

    ~/php-src> ./configure --prefix=$HOME/myphp
    ~/php-src> make -jN
    ~/php-src> make install

Here ``$HOME/myphp`` is the installation location that will be used during the ``make install`` step. Note that
installing PHP is not necessary, but can be convenient if you want to use your PHP build outside of extension
development.

Now lets take a closer look at the individual build steps!

The ``./buildconf`` script
--------------------------

If you are building from the git repository, the first thing you'll have to do is run the ``./buildconf`` script. This
script does little more than invoking ``autoconf``.

The main job of ``autoconf`` is to generate the ``./configure`` script and ``autoheader`` to
generate the ``main/php_config.h.in`` template. The latter file will be used by configure to generate the final
configuration header file ``main/php_config.h``.

Both utilities produce their results from the ``configure.ac`` file (which specifies most of the PHP build process),
the ``build/php.m4`` file (which specifies a large number of PHP-specific M4 macros) and the ``config.m4`` files of
individual extensions and SAPIs (as well as a bunch of other `m4 files <http://www.gnu.org/software/m4/m4.html>`_).

The good news is that writing extensions or even doing core modifications will not require much interaction with the
build system. You will have to write small ``config.m4`` files later on, but those usually just use two or three of the
high-level macros that ``build/php.m4`` provides. As such we will not go into further detail here.

The ``./buildconf`` script only has two options: ``--debug`` will disable warning suppression when calling autoconf and
autoheader. Unless you want to work on the buildsystem, this option will be of little interest to you.

The second option is ``--force``, which will allow running ``./buildconf`` in release packages (e.g. if you downloaded
the packaged source code and want to generate a new ``./configure``) and additionally clear the configuration caches
``config.cache`` and ``autom4te.cache/``.

If you update your git repository using ``git pull`` (or some other command) and get weird errors during the ``make``
step, this usually means that something in the build configuration changed and you need to rerun ``./buildconf``.

The ``./configure`` script
--------------------------

Once the ``./configure`` script is generated you can make use of it to customize your PHP build. You can list all
supported options using ``--help``::

    ~/php-src> ./configure --help | less

The first part of the help will list various generic options, which are supported by all autoconf-based configuration
scripts. One of them is the already mentioned ``--prefix=DIR``, which changes the installation directory used by
``make install``. Another useful option is ``-C``, which will cache the result of various tests in the ``config.cache``
file and speed up subsequent ``./configure`` calls. Using this option only makes sense once you already have a working
build and want to quickly change between different configurations.

Apart from generic autoconf options there are also many settings specific to PHP. For example, you can choose which
extensions and SAPIs should be compiled using the ``--enable-NAME`` and ``--disable-NAME`` switches. If the extension or
SAPI has external dependencies you need to use ``--with-NAME`` and ``--without-NAME`` instead.

If a library needed by ``NAME`` is not located in the default location (e.g. because you compiled it yourself), some
extensions allow you to specify its location using ``--with-NAME=DIR``. However, since PHP 7.4 most extensions use
``pkg-config`` instead, in which case passing a directory to ``--with`` has no effect. In this case, it is necessary
to add the library to the ``PKG_CONFIG_PATH``::

    export PKG_CONFIG_PATH=/path/to/library/lib/pkgconfig:$PKG_CONFIG_PATH

By default PHP will build the CLI and CGI SAPIs, as well as a number of extensions. You can find out which extensions
your PHP binary contains using the ``-m`` option. For a default PHP 7.0 build the result will look as follows:

.. code-block:: none

    ~/php-src> sapi/cli/php -m
    [PHP Modules]
    Core
    ctype
    date
    dom
    fileinfo
    filter
    hash
    iconv
    json
    libxml
    pcre
    PDO
    pdo_sqlite
    Phar
    posix
    Reflection
    session
    SimpleXML
    SPL
    sqlite3
    standard
    tokenizer
    xml
    xmlreader
    xmlwriter

If you now wanted to stop compiling the CGI SAPI, as well as the *tokenizer* and *sqlite3* extensions and instead enable
*opcache* and *gmp*, the corresponding configure command would be::

    ~/php-src> ./configure --disable-cgi --disable-tokenizer --without-sqlite3 \
                           --enable-opcache --with-gmp

By default most extensions will be compiled statically, i.e. they will be part of the resulting binary. Only the opcache
extension is shared by default, i.e. it will generate an ``opcache.so`` shared object in the ``modules/`` directory. You
can compile other extensions into shared objects as well by writing ``--enable-NAME=shared`` or ``--with-NAME=shared``
(but not all extensions support this). We'll talk about how to make use of shared extensions in the next section.

To find out which switch you need to use and whether an extension is enabled by default, check ``./configure --help``.
If the switch is either ``--enable-NAME`` or ``--with-NAME`` it means that the extension is not compiled by default and
needs to be explicitly enabled. ``--disable-NAME`` or ``--without-NAME`` on the other hand indicate an extension that
is compiled by default, but can be explicitly disabled.

Some extensions are always compiled and can not be disabled. To create a build that only contains the minimal amount of
extensions use the ``--disable-all`` option::

    ~/php-src> ./configure --disable-all && make -jN
    ~/php-src> sapi/cli/php -m
    [PHP Modules]
    Core
    date
    hash
    json
    pcre
    Reflection
    SPL
    standard

The ``--disable-all`` option is very useful if you want a fast build and don't need much functionality (e.g. when
implementing language changes). For the smallest possible build you can additionally specify the ``--disable-cgi``
switch, so only the CLI binary is generated.

There are three more switches, which you should usually specify when developing extensions or working on PHP:

``--enable-debug`` enables debug mode, which has multiple effects: Compilation will run with ``-g`` to generate debug
symbols and additionally use the lowest optimization level ``-O0``. This will make PHP a lot slower, but make debugging
with tools like ``gdb`` more predictable. Furthermore debug mode defines the ``ZEND_DEBUG`` macro, which will enable
the use of assertions and enable various debugging helpers in the engine. Among other things memory leaks, as well as
incorrect use of some data structures, will be reported. It is possible to enable debug assertions without disabling
optimizations by using ``--enable-debug-assertions`` instead.

``--enable-zts`` (or ``--enable-maintainer-zts`` before PHP 8.0) enables thread-safety. This switch will define the
``ZTS`` macro, which in turn will enable the whole TSRM (thread-safe resource manager) machinery used by PHP. Since
PHP 7 having this switch continuously enabled is much less important than on previous versions. It is primarily
important to make sure you included all the necessary boilerplate code. If you need more information about thread
safety and global memory management in PHP, you should read :doc:`the globals management chapter <../extensions_design/globals_management>`

``--enable-werror`` (since PHP 7.4) enables the ``-Werror`` compiler flag, which will promote compiler warnings to
errors. Enabling this flag ensures that the PHP build remains warning free. However, generated warnings depend on the
used compiler, version and optimization options, so some compilers may not be usable with option.

On the other hand you should not use the ``--enable-debug`` option if you want to perform performance benchmarks for
your code. ``--enable-zts`` can also negatively impact runtime performance.

Note that ``--enable-debug`` and ``--enable-zts`` change the ABI of the PHP binary, e.g. by adding additional arguments
to functions. As such, shared extensions compiled in debug mode will not be compatible with a PHP binary built in
release mode. Similarly a thread-safe extension (ZTS) is not compatible with a non-thread-safe PHP build (NTS).

Due to the ABI incompatibility ``make install`` (and PECL install) will put shared extensions in different directories
depending on these options:

* ``$PREFIX/lib/php/extensions/no-debug-non-zts-API_NO`` for release builds without ZTS
* ``$PREFIX/lib/php/extensions/debug-non-zts-API_NO`` for debug builds without ZTS
* ``$PREFIX/lib/php/extensions/no-debug-zts-API_NO`` for release builds with ZTS
* ``$PREFIX/lib/php/extensions/debug-zts-API_NO`` for debug builds with ZTS

The ``API_NO`` placeholder above refers to the ``ZEND_MODULE_API_NO`` and is just a date like ``20100525``, which is
used for internal API versioning.

For most purposes the configuration switches described above should be sufficient, but of course ``./configure``
provides many more options, which you'll find described in the help.

Apart from passing options to configure, you can also specify a number of environment variables. Some of the more
important ones are documented at the end of the configure help output (``./configure --help | tail -25``).

For example you can use ``CC`` to use a different compiler and ``CFLAGS`` to change the used compilation flags::

    ~/php-src> ./configure --disable-all CC=clang CFLAGS="-O3 -march=native"

In this configuration the build will make use of clang (instead of gcc) and use a very high optimization level
(``-O3 -march=native``).

An option that is particularly useful for development is ``-fsanitize``, which allows you to detect memory corruption
and undefined behavior at runtime::

    CFLAGS="-fsanitize=address -fsanitize=undefined"

These options only work reliably since PHP 7.4 and will significantly slow down the generated PHP binary.

``make`` and ``make install``
-----------------------------

After everything is configured, you can use ``make`` to perform the actual compilation::

    ~/php-src> make -jN    # where N is the number of cores

The main result of this operation will be PHP binaries for the enabled SAPIs (by default ``sapi/cli/php`` and
``sapi/cgi/php-cgi``), as well as shared extensions in the ``modules/`` directory.

Now you can run ``make install`` to install PHP into ``/usr/local`` (default) or whatever directory you specified using
the ``--prefix`` configure switch.

``make install`` will do little more than copy a number of files to the new location. If you specified ``--with-pear``
during configuration, it will also download and install PEAR. Here is the resulting tree of a default PHP build:

.. code-block:: none

    > tree -L 3 -F ~/myphp

    /home/myuser/myphp
    |-- bin
    |   |-- pear*
    |   |-- peardev*
    |   |-- pecl*
    |   |-- phar -> /home/myuser/myphp/bin/phar.phar*
    |   |-- phar.phar*
    |   |-- php*
    |   |-- php-cgi*
    |   |-- php-config*
    |   `-- phpize*
    |-- etc
    |   `-- pear.conf
    |-- include
    |   `-- php
    |       |-- ext/
    |       |-- include/
    |       |-- main/
    |       |-- sapi/
    |       |-- TSRM/
    |       `-- Zend/
    |-- lib
    |   `-- php
    |       |-- Archive/
    |       |-- build/
    |       |-- Console/
    |       |-- data/
    |       |-- doc/
    |       |-- OS/
    |       |-- PEAR/
    |       |-- PEAR5.php
    |       |-- pearcmd.php
    |       |-- PEAR.php
    |       |-- peclcmd.php
    |       |-- Structures/
    |       |-- System.php
    |       |-- test/
    |       `-- XML/
    `-- php
        `-- man
            `-- man1/

A short overview of the directory structure:

* *bin/* contains the SAPI binaries (``php`` and ``php-cgi``), as well as the ``phpize`` and ``php-config`` scripts.
  It is also home to the various PEAR/PECL scripts.
* *etc/* contains configuration. Note that the default *php.ini* directory is **not** here.
* *include/php* contains header files, which are needed to build additional extensions or embed PHP in custom software.
* *lib/php* contains PEAR files. The *lib/php/build* directory includes files necessary for building extensions, e.g.
  the ``php.m4`` file containing PHP's M4 macros. If we had compiled any shared extensions those files would live
  in a subdirectory of *lib/php/extensions*.
* *php/man* obviously contains man pages for the ``php`` command.

As already mentioned, the default *php.ini* location is not *etc/*. You can display the location using the ``--ini``
option of the PHP binary:

.. code-block:: none

    ~/myphp/bin> ./php --ini
    Configuration File (php.ini) Path: /home/myuser/myphp/lib
    Loaded Configuration File:         (none)
    Scan for additional .ini files in: (none)
    Additional .ini files parsed:      (none)

As you can see the default *php.ini* directory is ``$PREFIX/lib`` (libdir) rather than ``$PREFIX/etc`` (sysconfdir). You
can adjust the default *php.ini* location using the ``--with-config-file-path=PATH`` configure option.

Also note that ``make install`` will not create an ini file. If you want to make use of a *php.ini* file it is your
responsibility to create one. For example you could copy the default development configuration:

.. code-block:: none

    ~/myphp/bin> cp ~/php-src/php.ini-development ~/myphp/lib/php.ini
    ~/myphp/bin> ./php --ini
    Configuration File (php.ini) Path: /home/myuser/myphp/lib
    Loaded Configuration File:         /home/myuser/myphp/lib/php.ini
    Scan for additional .ini files in: (none)
    Additional .ini files parsed:      (none)

Apart from the PHP binaries the *bin/* directory also contains two important scripts: ``phpize`` and ``php-config``.

``phpize`` is the equivalent of ``./buildconf`` for extensions. It will copy various files from *lib/php/build* and
invoke autoconf/autoheader. You will learn more about this tool in the next section.

``php-config`` provides information about the configuration of the PHP build. Try it out:

.. code-block:: none

    ~/myphp/bin> ./php-config
    Usage: ./php-config [OPTION]
    Options:
      --prefix            [/home/myuser/myphp]
      --includes          [-I/home/myuser/myphp/include/php -I/home/myuser/myphp/include/php/main -I/home/myuser/myphp/include/php/TSRM -I/home/myuser/myphp/include/php/Zend -I/home/myuser/myphp/include/php/ext -I/home/myuser/myphp/include/php/ext/date/lib]
      --ldflags           [ -L/usr/lib/i386-linux-gnu]
      --libs              [-lcrypt   -lresolv -lcrypt -lrt -lrt -lm -ldl -lnsl  -lxml2 -lxml2 -lxml2 -lcrypt -lxml2 -lxml2 -lxml2 -lcrypt ]
      --extension-dir     [/home/myuser/myphp/lib/php/extensions/debug-zts-20100525]
      --include-dir       [/home/myuser/myphp/include/php]
      --man-dir           [/home/myuser/myphp/php/man]
      --php-binary        [/home/myuser/myphp/bin/php]
      --php-sapis         [ cli cgi]
      --configure-options [--prefix=/home/myuser/myphp --enable-debug --enable-maintainer-zts]
      --version           [5.4.16-dev]
      --vernum            [50416]

The script is similar to the ``pkg-config`` script used by linux distributions. It is invoked during the extension
build process to obtain information about compiler options and paths. You can also use it to quickly get information
about your build, e.g. your configure options or the default extension directory. This information is also provided by
``./php -i`` (phpinfo), but ``php-config`` provides it in a simpler form (which can be easily used by automated tools).

Running the test suite
----------------------

If the ``make`` command finishes successfully, it will print a message encouraging you to run ``make test``:

.. code-block:: none

    Build complete.
    Don't forget to run 'make test'

``make test`` will run the PHP CLI binary against our test suite, which is located in the different *tests/* directories
of the PHP source tree. As a default build is run against more than 10000 (less for a minimal build, more if
you enable additional extensions) this can take several minutes.

The ``make test`` command internally invokes the ``run-tests.php`` file using your CLI binary. For more control, it is
recommended to invoke ``run-tests.php`` directly. For example, this will allow you to enable the parallel test runner::

    ~/php-src> sapi/cli/php run-tests.php -jN

Test parallelism is only available as of PHP 7.4. On earlier PHP versions parallelism is not available, and it is
necessary to additionally pass the ``-P`` option::

    ~/php-src> sapi/cli/php run-tests.php -P

Instead of running the whole test suite, you can also limit it to certain directories by passing them as arguments to
``run-tests.php``. E.g. to test only the Zend engine, the reflection extension and the array functions::

    ~/php-src> sapi/cli/php run-tests.php -jN Zend/ ext/reflection/ ext/standard/tests/array/

This is very useful, because it allows you to quickly run only the parts of the test suite that are relevant to your
changes. E.g. if you are doing language modifications you likely don't care about the extension tests and only want to
verify that the Zend engine is still working correctly.

You can run ``sapi/cli/php run-tests.php --help`` to display a full list of options the test runner accepts. Some
particularly useful options are:

  * ``-c php.ini`` can be used to specify a php.ini file to use.
  * ``-d foo=bar`` can be used to set ini options.
  * ``-m`` runs tests under valgrind to detect memory errors. Note that this is extremely slow.
  * ``--asan`` should be set when compiling PHP with ``-fsanitize=address``. Together these are approximately
    equivalent to running under valgrind, but with much better performance.

You don't need to explicitly use ``run-tests.php`` to pass options or limit directories. Instead you can use the
``TESTS`` variable to pass additional arguments via ``make test``. E.g. the equivalent of the previous command would
be::

    ~/php-src> make test TESTS="-jN Zend/ ext/reflection/ ext/standard/tests/array/"

We will take a more detailed look at the ``run-tests.php`` system later, in particular also talk about how to write your
own tests and how to debug test failures. :doc:`See the dedicated tests chapter <../../tests/introduction>`.

Fixing compilation problems and ``make clean``
----------------------------------------------

As you may know ``make`` performs an incremental build, i.e. it will not recompile all files, but only those ``.c``
files that changed since the last invocation. This is a great way to shorten build times, but it doesn't always work
well: For example, if you modify a structure in a header file, ``make`` will not automatically recompile all ``.c``
files making use of that header, thus leading to a broken build.

If you get odd errors while running ``make`` or the resulting binary is broken (e.g. if ``make test`` crashes it before
it gets to run the first test), you should try to run ``make clean``. This will delete all compiled objects, thus
forcing the next ``make`` call to perform a full build. (You can use ``ccache`` to reduce the cost of rebuilds.)

Sometimes you also need to run ``make clean`` after changing ``./configure`` options. If you only enable additional
extensions an incremental build should be safe, but changing other options may require a full rebuild.

Another source of compilation issues is the modification of ``config.m4`` files or other files that are part of the PHP
build system. If such a file is changed, it is necessary to rerun the ``./buildconf`` and ``./configure`` scripts. If
you do the modification yourself, you will likely remember to run the command, but if it happens as part of a
``git pull`` (or some other updating command) the issue might not be so obvious.

If you encounter any odd compilation problems that are not resolved by ``make clean``, chances are that running
``./buildconf`` will fix the issue. To avoid typing out the previous ``./configure`` options afterwards, you can make
use of the ``./config.nice`` script (which contains your last ``./configure`` call)::

    ~/php-src> make clean
    ~/php-src> ./buildconf --force
    ~/php-src> ./config.nice
    ~/php-src> make -jN

One last cleaning script that PHP provides is ``./vcsclean``. This will only work if you checked out the source code
from git. It effectively boils down to a call to ``git clean -X -f -d``, which will remove all untracked files and
directories that are ignored by git. You should use this with care.
