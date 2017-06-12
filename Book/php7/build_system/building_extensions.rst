.. highlight:: bash

Building PHP extensions
=======================

Now that you know how to compile PHP itself, we'll move on to compiling additional extensions. We'll discuss how the
build process works and what different options are available.

Loading shared extensions
-------------------------

As you already know from the previous section, PHP extensions can be either built statically into the PHP binary, or
compiled into a shared object (``.so``). Static linkage is the default for most of the bundled extensions, whereas
shared objects can be created by explicitly passing ``--enable-EXTNAME=shared`` or ``--with-EXTNAME=shared`` to
``./configure``.

While static extensions will always be available, shared extensions need to be loaded using the ``extension`` or
``zend_extension`` ini options [#]_. Both options take either an absolute path to the ``.so`` file or a path relative to
the ``extension_dir`` setting.

As an example, consider a PHP build compiled using this configure line::

    ~/php-src> ./configure --prefix=$HOME/myphp \
                           --enable-debug --enable-maintainer-zts \
                           --enable-opcache --with-gmp=shared

In this case both the opcache extension and GMP extension are compiled into shared objects located in the ``modules/``
directory. You can load both either by changing the ``extension_dir`` or by passing absolute paths::

    ~/php-src> sapi/cli/php -dzend_extension=`pwd`/modules/opcache.so \
                            -dextension=`pwd`/modules/gmp.so
    # or
    ~/php-src> sapi/cli/php -dextension_dir=`pwd`/modules \
                            -dzend_extension=opcache.so -dextension=gmp.so

During the ``make install`` step both ``.so`` files will be moved into the extension directory of your PHP installation,
which you may find using the ``php-config --extension-dir`` command. For the above build options it will be
``/home/myuser/myphp/lib/php/extensions/no-debug-non-zts-MODULE_API``. This value will also be the default of the
``extension_dir`` ini option, so you won't have to specify it explicitly and can load the extensions directly::

    ~/myphp> bin/php -dzend_extension=opcache.so -dextension=gmp.so

This leaves us with one question: Which mechanism should you use? Shared objects allow you to have a base PHP binary and
load additional extensions through the php.ini. Distributions make use of this by providing a bare PHP package and
distributing the extensions as separate packages. On the other hand, if you are compiling your own PHP binary, you
likely don't have need for this, because you already know which extensions you need.

As a rule of thumb, you'll use static linkage for the extensions bundled by PHP itself and use shared extensions for
everything else. The reason is simply that building external extensions as shared objects is easier (or at least less
intrusive), as you will see in a moment. Another benefit is that you can update the extension without rebuilding PHP.

.. [#] We'll explain the difference between a "normal" extension and a Zend extension later in the book. For now it
       suffices to know that Zend extensions are more "low level" (e.g. opcache or xdebug) and hook into the workings of
       the Zend Engine itself.

Installing extensions from PECL
-------------------------------

PECL_, the *PHP Extension Community Library*, offers a large number of extensions for PHP. When extensions are removed
from the main PHP distribution, they usually continue to exist in PECL. Similarly many extensions that are now bundled
with PHP were previously PECL extensions.

Unless you specified ``--without-pear`` during the configuration stage of your PHP build, ``make install`` will download
and install PECL as a part of PEAR. You will find the ``pecl`` script in the ``$PREFIX/bin`` directory. Installing
extensions is now as simple as running ``pecl install EXTNAME``, e.g.::

    ~/myphp> bin/pecl install apcu

This command will download, compile and install the APCu_ extension. The result will be a ``apcu.so`` file in your
extension directory, which can then be loaded by passing the ``extension=apcu.so`` ini option.

While ``pecl install`` is very handy for the end-user, it is of little interest to extension developers. In the
following, we'll describe two ways to manually build extensions: Either by importing it into the main PHP source tree
(this allows static linkage) or by doing an external build (only shared).

.. _PECL: http://pecl.php.net
.. _APCu: http://pecl.php.net/package/APCu

Adding extensions to the PHP source tree
----------------------------------------

There is no fundamental difference between a third-party extension and an extension bundled with PHP. As such you can
build an external extension simply by copying it into the PHP source tree and then using the usual build procedure.
We'll demonstrate this using APCu as an example.

First of all, you'll have to place the source code of the extension into the ``ext/EXTNAME`` directory of your PHP
source tree. If the extension is available via git, this is as simple as cloning the repository from within ``ext/``::

    ~/php-src/ext> git clone https://github.com/krakjoe/apcu.git

Alternatively you can also download a source tarball and extract it::

    /tmp> wget http://pecl.php.net/get/apcu-4.0.2.tgz
    /tmp> tar xzf apcu-4.0.2.tgz
    /tmp> mkdir ~/php-src/ext/apcu
    /tmp> cp -r apcu-4.0.2/. ~/php-src/ext/apcu

The extension will contain a ``config.m4`` file, which specifies extension-specific build instructions for use by
autoconf. To incorporate them into the ``./configure`` script, you'll have to run ``./buildconf`` again. To ensure that
the configure file is really regenerated, it is recommended to delete it beforehand::

    ~/php-src> rm configure && ./buildconf --force

You can now use the ``./config.nice`` script to add APCu to your existing configuration or start over with a completely
new configure line::

    ~/php-src> ./config.nice --enable-apcu
    # or
    ~/php-src> ./configure --enable-apcu # --other-options

Finally run ``make -jN`` to perform the actual build. As we didn't use ``--enable-apcu=shared`` the extension is
statically linked into the PHP binary, i.e. no additional actions are needed to make use of it. Obviously you can also
use ``make install`` to install the resulting binaries.

Building extensions using ``phpize``
------------------------------------

It is also possible to build extensions separately from PHP by making use of the ``phpize`` script that was already
mentioned in the :ref:`building_php` section.

``phpize`` plays a similar role as the ``./buildconf`` script used for PHP builds: First it will import the PHP build
system into your extension by copying files from ``$PREFIX/lib/php/build``. Among these files are ``acinclude.m4``
(PHP's M4 macros), ``phpize.m4`` (which will be renamed to ``configure.in`` in your extension and contains the main
build instructions) and ``run-tests.php``.

Then ``phpize`` will invoke autoconf to generate a ``./configure`` file, which can be used to customize the extension
build. Note that it is not necessary to pass ``--enable-apcu`` to it, as this is implicitly assumed. Instead you should
use ``--with-php-config`` to specify the path to your ``php-config`` script::

    /tmp/apcu-4.0.2> ~/myphp/bin/phpize
    Configuring for:
    PHP Api Version:         20121113
    Zend Module Api No:      20121113
    Zend Extension Api No:   220121113

    /tmp/apcu-4.0.2> ./configure --with-php-config=$HOME/myphp/bin/php-config
    /tmp/apcu-4.0.2> make -jN && make install

You should always specify the ``--with-php-config`` option when building extensions (unless you have only a single,
global installation of PHP), otherwise ``./configure`` will not be able to correctly determine what PHP version and
flags to build against. Specifying the ``php-config`` script also ensures that ``make install`` will move the generated
``.so`` file (which can be found in the ``modules/`` directory) to the right extension directory.

As the ``run-tests.php`` file was also copied during the ``phpize`` stage, you can run the extension tests using
``make test`` (or an explicit call to run-tests).

The ``make clean`` target for removing compiled objects is also available and allows you to force a full rebuild of
the extension, should the incremental build fail after a change. Additionally phpize provides a cleaning option via
``phpize --clean``. This will remove all the files imported by ``phpize``, as well as the files generated by the
``/configure`` script.

Displaying information about extensions
---------------------------------------

The PHP CLI binary provides several options to display information about extensions. You already know ``-m``, which will
list all loaded extensions. You can use it to verify that an extension was loaded correctly::

    ~/myphp/bin> ./php -dextension=apcu.so -m | grep apcu
    apcu

There are several further switches beginning with ``--r`` that expose Reflection functionality. For example you can use
``--ri`` to display the configuration of an extension::

    ~/myphp/bin> ./php -dextension=apcu.so --ri apcu
    apcu

    APCu Support => disabled
    Version => 4.0.2
    APCu Debugging => Disabled
    MMAP Support => Enabled
    MMAP File Mask =>
    Serialization Support => broken
    Revision => $Revision: 328290 $
    Build Date => Jan  1 2014 16:40:00

    Directive => Local Value => Master Value
    apc.enabled => On => On
    apc.shm_segments => 1 => 1
    apc.shm_size => 32M => 32M
    apc.entries_hint => 4096 => 4096
    apc.gc_ttl => 3600 => 3600
    apc.ttl => 0 => 0
    # ...

The ``--re`` switch lists all ini settings, constants, functions and classes added by an extension:

.. code-block:: none

    ~/myphp/bin> ./php -dextension=apcu.so --re apcu
    Extension [ <persistent> extension #27 apcu version 4.0.2 ] {
      - INI {
        Entry [ apc.enabled <SYSTEM> ]
          Current = '1'
        }
        Entry [ apc.shm_segments <SYSTEM> ]
          Current = '1'
        }
        # ...
      }

      - Constants [1] {
        Constant [ boolean APCU_APC_FULL_BC ] { 1 }
      }

      - Functions {
        Function [ <internal:apcu> function apcu_cache_info ] {

          - Parameters [2] {
            Parameter #0 [ <optional> $type ]
            Parameter #1 [ <optional> $limited ]
          }
        }
        # ...
      }
    }

The ``--re`` switch only works for normal extensions, Zend extensions use ``--rz`` instead. You can try this on
opcache::

    ~/myphp/bin> ./php -dzend_extension=opcache.so --rz "Zend OPcache"
    Zend Extension [ Zend OPcache 7.0.3-dev Copyright (c) 1999-2013 by Zend Technologies <http://www.zend.com/> ]

As you can see, this doesn't display any useful information. The reason is that opcache registers both a normal
extension and a Zend extension, where the former contains all ini settings, constants and functions. So in this
particular case you still need to use ``--re``. Other Zend extensions make their information available via ``--rz``
though.

Extensions API compatibility
----------------------------

Extensions are very sensitive to 5 major factors. If they dont fit, the extension wont load into PHP and will be 
useless:

    * PHP Api Version
    * Zend Module Api No
    * Zend Extension Api No
    * Debug mode
    * Thread safety

The *phpize* tool recall you some of those informations.
So if you have built a PHP with debug mode, and try to make it load and use an extension which's been built without
debug mode, it simply wont work. Same for the other checks.

*PHP Api Version* is the number of the version of the internal API. *Zend Module Api No* and *Zend Extension Api No*
are respectively about PHP extensions and Zend extensions API.

Those numbers are later passed as C macros to the extension beeing built, so that it can itself check against those
parameters and take different code paths based on C preprocessor ``#ifdef``\s. As those numbers are passed to the
extension code as macros, they are written in the extension structure, so that anytime you try to load this extension in
a PHP binary, they will be checked against the PHP binary's own numbers.
If they mismatch, then the extension will not load, and an error message will be displayed.

If we look at the extension C structure, it looks like this::

    zend_module_entry foo_module_entry = {
        STANDARD_MODULE_HEADER,
        "foo",
        foo_functions,
        PHP_MINIT(foo),
        PHP_MSHUTDOWN(foo),
        NULL,
        NULL,
        PHP_MINFO(foo),
        PHP_FOO_VERSION,
        STANDARD_MODULE_PROPERTIES
    };

What is interesting for us so far, is the ``STANDARD_MODULE_HEADER`` macro. If we expand it, we can see::

    #define STANDARD_MODULE_HEADER_EX sizeof(zend_module_entry), ZEND_MODULE_API_NO, ZEND_DEBUG, USING_ZTS
    #define STANDARD_MODULE_HEADER STANDARD_MODULE_HEADER_EX, NULL, NULL

Notice how ``ZEND_MODULE_API_NO``, ``ZEND_DEBUG``, ``USING_ZTS`` are used.


If you look at the default directory for PHP extensions, it should look like ``no-debug-non-zts-20090626``. As you'd
have guessed, this directory is made of distinct parts joined together : debug mode, followed by thread safety
information, followed by the Zend Module Api No.
So by default, PHP tries to help you navigating with extensions.

.. note::

    Usually, when you become an internal developper or an extension developper, you will have to play with 
    the debug parameter, and if you have to deal with the Windows platform, threads will show up as well. You can 
    end with compiling the same extension several times against several cases of those parameters.

Remember that every new major/minor version of PHP change parameters such as the PHP Api Version, that's why you need 
to recompile extensions against a newer PHP version.

.. code-block:: none

    > /path/to/php70/bin/phpize -v
    Configuring for:
    PHP Api Version:         20151012
    Zend Module Api No:      20151012
    Zend Extension Api No:   320151012

    > /path/to/php71/bin/phpize -v
    Configuring for:
    PHP Api Version:         20160303
    Zend Module Api No:      20160303
    Zend Extension Api No:   320160303

    > /path/to/php56/bin/phpize -v
    Configuring for:
    PHP Api Version:         20131106
    Zend Module Api No:      20131226
    Zend Extension Api No:   220131226

.. note::

    *Zend Module Api No* is itself built with a date using the *year.month.day* format. This is the date of the day the 
    API changed and was tagged.
    *Zend Extension Api No* is the Zend version followed by *Zend Module Api No*.
    
.. note::
    
    Too many numbers? Yes. One API number, bound to one PHP version, would really be enough for anybody and would ease 
    the understanding of PHP versionning. Unfortunately, we got 3 different API numbers in addition to the PHP version 
    itself. Which one should you look for ? The answer is any : they all-three-of-them evolve when PHP version evolve.
    For historical reasons, we got 3 different numbers.
    
But, you are a C developper anren't you ? Why not build a "compatibility" header on your side, based on such number ?
We authors, use something like this in extensions of ours::

    #include "php.h"
    #include "Zend/zend_extensions.h"
    
    #define PHP_5_5_X_API_NO		220121212
    #define PHP_5_6_X_API_NO		220131226

    #define PHP_7_0_X_API_NO		320151012
    #define PHP_7_1_X_API_NO		320160303
    #define PHP_7_2_X_API_NO		320160731

    #define IS_PHP_72          ZEND_EXTENSION_API_NO == PHP_7_2_X_API_NO
    #define IS_AT_LEAST_PHP_72 ZEND_EXTENSION_API_NO >= PHP_7_2_X_API_NO

    #define IS_PHP_71          ZEND_EXTENSION_API_NO == PHP_7_1_X_API_NO
    #define IS_AT_LEAST_PHP_71 ZEND_EXTENSION_API_NO >= PHP_7_1_X_API_NO

    #define IS_PHP_70          ZEND_EXTENSION_API_NO == PHP_7_0_X_API_NO
    #define IS_AT_LEAST_PHP_70 ZEND_EXTENSION_API_NO >= PHP_7_0_X_API_NO

    #define IS_PHP_56          ZEND_EXTENSION_API_NO == PHP_5_6_X_API_NO
    #define IS_AT_LEAST_PHP_56 (ZEND_EXTENSION_API_NO >= PHP_5_6_X_API_NO && ZEND_EXTENSION_API_NO < PHP_7_0_X_API_NO)

    #define IS_PHP_55          ZEND_EXTENSION_API_NO == PHP_5_5_X_API_NO
    #define IS_AT_LEAST_PHP_55 (ZEND_EXTENSION_API_NO >= PHP_5_5_X_API_NO && ZEND_EXTENSION_API_NO < PHP_7_0_X_API_NO)

    #if ZEND_EXTENSION_API_NO >= PHP_7_0_X_API_NO
    #define IS_PHP_7 1
    #define IS_PHP_5 0
    #else
    #define IS_PHP_7 0
    #define IS_PHP_5 1
    #endif
    
See ?

Or, simpler (so better ?) is to use PHP_VERSION_ID which you are probably much more familiar about::
    
    #if PHP_VERSION_ID >= 50600
    
