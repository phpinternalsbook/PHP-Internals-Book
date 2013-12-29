.. code-block:: none

    ~/myphp/bin> ldd ./php
    linux-vdso.so.1 =>  (0x00007fff0adff000)
	libcrypt.so.1 => /lib/x86_64-linux-gnu/libcrypt.so.1 (0x00007f9689077000)
	libresolv.so.2 => /lib/x86_64-linux-gnu/libresolv.so.2 (0x00007f9688e61000)
	librt.so.1 => /lib/x86_64-linux-gnu/librt.so.1 (0x00007f9688c58000)
	libm.so.6 => /lib/x86_64-linux-gnu/libm.so.6 (0x00007f96889d6000)
	libdl.so.2 => /lib/x86_64-linux-gnu/libdl.so.2 (0x00007f96887d2000)
	libnsl.so.1 => /lib/x86_64-linux-gnu/libnsl.so.1 (0x00007f96885b9000)
	libxml2.so.2 => /usr/lib/x86_64-linux-gnu/libxml2.so.2 (0x00007f9688457000)
	libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x00007f96880cd000)
	libpthread.so.0 => /lib/x86_64-linux-gnu/libpthread.so.0 (0x00007f9687eb0000)
	/lib64/ld-linux-x86-64.so.2 (0x00007f96892d2000)
	libz.so.1 => /lib/x86_64-linux-gnu/libz.so.1 (0x00007f9687c99000)
	liblzma.so.5 => /lib/x86_64-linux-gnu/liblzma.so.5 (0x00007f9687a76000)

Here we checked the dependencies of this PHP build against the system libraries. By default, with a default ``./configure`` command, some extensions get compiled, and those, as well as PHP Core, need dynamic shared libraries to work.
If you dont know what shared libraries are and what they provide, please, check our chapter about {link}prerequisites{link}

---

Building PHP Extensions
=======================

In this chapter, we won't talk about how to write a PHP extension. For that, you should read the {link}dedicated chapter{link}.
Here, we'll talk about what the structure of an extension looks like, and how to build extensions, both statically and using shared objects.
After reading this chapter, you'll know everything needed about compiling, installing and testing extensions.

Extensions structure
--------------------

Each extension come with some minimal structure for it to be compiled and linked against php sources :
    * At least one C file, code to be compiled
    * At least one header C file (.h)
    * At least one m4 file, called ``config.m4``, to give the steps *configure* script should follow to make compilation possible.

In fact, extensions are a little bit more complex than that, but rarely crazy complex.

PHP extensions and PECL
-----------------------

If you look at the PHP source tree, you notice an *ext/* directory. This directory contains all the default extensions PHP's been packaged with. This does not mean those will be compiled, this depends on the *configure* script options you provide.
Running ``./configure --help`` shows your choices :

.. code-block:: none

    phpsrc/ > ./configure --help | less
    {truncated}
    --enable-ftp
    --with-gd=DIR
    --disable-hash
    --without-pdo-sqlite=DIR
    ...

Here is a global explaination :
    * ``--enable-foo`` means that the ``foo`` extension won't be compiled by default, you have to provide the switch so that it gets compiled when you run *make*
    * ``--disable-foo`` or ``--without-foo`` mean that the ``foo`` extension will be compiled by default, you have to provide the switch so that it will be excluded from compilation when you run *make*
    * ``--with-foo=DIR`` means that the ``foo`` extension won't be compiled by default, you have to provide the switch so that it gets compiled when you run *make*. Additionnaly, the foo extension depends on system libraries. Those will be looked for in the default tree, except if you provide a specialized directory to look for them using the *DIR* parameter.

Wheither the extension is enabled (so you see a *--disable* switch for it in *configure* help output) or disabled (so you see a *--enable* switch for it in *configure* help output) by default is a choice made by the PHP team when it releases a new version of PHP. Thus, from version to version, extensions may move from *--enable* to *--disable* switch by default.

More extensions with PECL
*************************

It can happen that an extension is not bundled in the PHP source tree by default. Chances are it still exists on the PECL website. http://pecl.php.net is a website storing tons of extensions about PHP. On this site, you can look for extensions, see their releases and their version types (betas, alphas or stables) and obviously you can download their sources. Take care to get enough informations about the extension you are willing to download, it may be not maintained any more.

.. note::

    If an extension were bundled with a PHP version *n*, and is not with the version *n+1* anymore, this means that the PHP contributors decided to "move it to PECL". The extension is then still downloadable from the PECL website.
    Remember that extensions located on the PECL website are **not supported** by the PHP team, they are by their respective authors. That's why sometimes extensions move from PECL to the distribution and vice-versa during PHP's life.

.. note::

    There exists other source hosts for PHP extensions. GitHub is another great one, for example.

Compiling an extension
----------------------

Directly together with PHP
**************************

This happens when you run the *configure* script into the PHP source tree. Simply activate the switch, and the extensions will be built :

.. code-block:: none

    phpsrc/ > ./configure --disable-pdo --enable-soap

In the above example, we indicate we'd like a PHP to be built with all the default extensions minus the PDO one, and with the addition of the SOAP one. By default, the added extensions will be statically built, this means their code will be merged into the code of the final PHP binary, thus, you won't be able to disable them anymore using a .so file. This is known as "static compilation" (thought the exact term for that is "static linkage").

If you want to use shared library, which will build a .so file for your extension, you have to indicate it to the configure script, like this:

.. code-block:: none

    phpsrc/ > ./configure --disable-pdo --enable-soap=shared

Providing the ``=shared`` to the ``--enable`` (or ``--with``) switch tells the build system to compile the extension as a separated .so file.

.. note::

    Compiling statically merges the extension code into the resulting binaries. This means that the startup phase of PHP will be faster, because the dynamic loader doesn't have to find, load and relocate all the .so. However, you won't be able to change the code of the extensions anymore, without recompiling the whole PHP binary (which with the help of *make* cache system may not take so many time). Also, as the extension code is merged into the binary, its memory footprint will be bigger, as it obviously embeds more code to run.
    It is usually better to build shared libraries as you can then choose weither or not you want to include them at runtime, and it eases the process of updating an extension code. However, if you are sure you'll use the extension, and won't change it in the future, then you should go for static linking.

.. note::

    Not all extensions can be buit statically or as shared objects. You usually can choose between two, but some extensions are protected and can only be built weither statically or as shared objects.

Adding PECL extension to the PHP tree
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Here we'll demonstrate how to download a PHP extension, from PECL website for example, merge it to our PHP source tree and compile it together with PHP itself. We'll take the APC extension as an example.
The steps are :

    * Download and extract the extension sources into a subdir of *phpsrc/ext*
    * Delete the PHP *configure* script
    * Rebuild the PHP *configure* script so that it notices the new extension you just added
    * Activate the extension using the new generated *configure* script
    * *make* and *make install*, you are done

This gives something like :

.. code-block:: none

    /tmp> wget http://pecl.php.net/get/APC-3.1.13.tgz
    /tmp> tar xzf APC-3.1.13.tgz
    /tmp> mkdir phpsrc/php-5.4.15/ext/apc && cp APC-3.1.13/* phpsrc/php-5.4.15/ext/apc
    /tmp> cd phpsrc/php-5.4.15
    /tmp/phpsrc/php-5.4.15> rm configure && ./buildconf --force
    Forcing buildconf
    Removing configure caches
    buildconf: checking installation...
    buildconf: autoconf version 2.69 (ok)
    rebuilding aclocal.m4
    rebuilding configure
    rebuilding main/php_config.h.in
    /tmp/phpsrc/php-5.4.15> ./configure --enable-apc && make && make install

.. note::

    Obviously, from the above example, we could have built the extension as shared, using ``./configure --enable-apc=shared``

Appart from PHP
***************

If you want to compile an extension after having compiled and installed PHP itself, this fortunately is also possible. Obviously you'll end up with a .so file, no static compilation here. The process can be splitted into 3 steps :
    * prepare the extension by importing the compilation environnement into it
    * configure the extension, basically launch the *configure* script
    * *make* and *make install* it

Recall the *phpize* tool we talked about in the :ref:`compiling_php` chapter ? The goal of this tool is to import the PHP compilation tools when it is run into an extension base directory. Basically : it checks your extension m4 file, and creates a configure script you'll use. Here is an example :

.. code-block:: none

    > wget http://pecl.php.net/get/APC-3.1.13.tgz
    > tar xzf APC-3.1.13.tgz && cd APC-3.1.13
    APC-3.1.13> /home/myuser/myphp/bin/phpize
    Configuring for:
    PHP Api Version:         20090626
    Zend Module Api No:      20090626
    Zend Extension Api No:   220090626
    APC-3.1.13>

Your extension is ready, you can now run the *configure* script into it. Don't forget to provide it with the *php-config* path :

.. code-block:: none

    APC-3.1.13> ./configure --with-php-config=/home/myuser/myphp/bin/php-config

.. note::

    Perhaps there exist other options ? Watch for the *configure --help* output, but in any way, **never forget** to provide the *php-config* script path, it is necessary for your extension to know about the PHP it's gonna be compiled for.

Zend Extensions against PHP extensions
--------------------------------------

As you may know, PHP actually supports two different kinds of extensions. They are internally called *"Zend Module"* and *"Zend Extension"*. This is a little bit confusing. We prefer talking about, respectively from the previous names, "PHP extensions" and "Zend extensions".
Beside the fact that Zend extensions can hook at different level into the engine than PHP extensions can, there also exists differences when it comes to recognize them and load them but the preparation/compilation steps are exactly the sames.

PHP extensions
**************

PHP extensions are loaded with the ``extension=`` hint from the configuration. What you indicate behind that is just the name of the .so file, like this :

.. code-block:: ini

    extension = memcached.so

From the above example, the loading system will then look for a file named *memcached.so* in the extension directory. This directory has a default place you can change using the ``extension_dir`` key into the configuration file.

.. code-block:: ini

    extension_dir = /tmp/mydir
    extension = memcached.so

.. note::

    The default extension directory can be obtained by running ``php-config --extension-dir`` command. This information **does not change** if you provide an ``extension_dir`` in the configuration. To get the actual location of extensions, you should start by greping the ``extension_dir`` configuration directive, from the *php.ini* parsed, and if not known, rely on the default directory.

Zend extensions
***************

Zend extensions loading differ from PHP extensions. First, they use a different configuration key : ``zend_extension=``.
Second thing : you have to provide the full path to the *.so* object. It then looks like this :

.. code-block:: ini

    zend_extension = /tmp/mydir/php/zendextensions/myextension.so

Zend extensions don't care about the ``extension_dir`` directive or any default directory. This has changed in PHP 5.5.
Starting from PHP 5.5, Zend extensions loading mechanism is the same as for PHP extensions : they are beeing looked for based on the ``extension_dir`` information from configuration.

There still exists differences : the ``php --re`` command is for PHP extensions. Use ``php --rz`` for the equivalent for Zend extensions.
Also, should you use the ``dl()`` function of PHP (which tends to disappear, and is only available if the configuration enables it, as well as only with some SAPIs), it can only load PHP extensions. It is not possible to load Zend extensions at runtime in a PHP script using PHP's ``dl()``

Extensions tips and tricks
--------------------------

Here we provide you with tips you should know about extensions

Checking and testing extensions
*******************************

Remember that the PHP CLI 's got switches about extensions. Say you just compiled the memcached extension as a shared object.
At first, what you can do is to check it is correctly loaded in PHP, like this :

.. code-block:: none

    > php -dextension=memcached.so -m | grep memcached
    memcached

Ok, it gets loaded with no problem, and PHP tells us it knows about the extension.
There exists several other interesting switches. For example, if you want to confirm about what configuration settings are provided by the memcached extension, you should run :

.. code-block:: none

    > php -dextension=memcached.so --ri memcached
    memcached

    memcached support => enabled
    Version => 2.1.0
    libmemcached version => 1.0.8
    SASL support => no
    Session support => yes
    igbinary support => no
    json support => no

    Directive => Local Value => Master Value
    memcached.sess_locking => 1 => 1
    memcached.sess_consistent_hash => 0 => 0
    ...

And finally, if you want to know what the memcached extension, when loaded, adds to PHP, you run :

.. code-block:: none

    > php -dextension=memcached.so --re memcached
    Extension [ <persistent> extension #29 memcached version 2.1.0 ] {

      - Dependencies {
        Dependency [ session (Required) ]
        Dependency [ spl (Required) ]
      }

      - INI {
        Entry [ memcached.sess_locking <ALL> ]
          Current = '1'
        }
        ...
        Entry [ memcached.compression_type <ALL> ]
          Current = 'fastlz'
        }

      - Classes [2] {
        Class [ <internal:memcached> class Memcached ] {

          - Constants [87] {
            Constant [ integer OPT_COMPRESSION ] { -1001 }
            Constant [ integer OPT_COMPRESSION_TYPE ] { -1004 }
    ...

.. note::

    The ``--re`` and ``--ri`` switches invoke Reflection without the need for you to write code. They respectively stand for *"Reflection Informations"* and *"Reflection Extension"*. Remember to use ``--rz`` switch for Zend extensions.

Furthermore, you can run the extension's test suite. It is as easy as invoking ``make test`` in the extension directory, after having compiled it.

Extensions API compatibility
****************************

Extensions are very sensitive to 5 major factors. If they dont fit, the extension wont load into PHP and will be useless :

    * PHP Api Version
    * Zend Module Api No
    * Zend Extension Api No
    * Debug mode
    * Thread safety

The *phpize* tool recall you some of those informations.
So if you have built a PHP with debug mode, and try to make it load and use an extension which's been built without debug mode, it simply wont work. Same for the other checks.

*PHP Api Version* is the number of the version of the internal API. *Zend Module Api No* and *Zend Extension Api No* are respectively about PHP extensions and Zend extensions API.

Those numbers are later passed as C macros to the extension beeing built, so that it can itself checks against those parameters and take different code paths based on C preprocessor ``#ifdef``\s
As those numbers are passed to the extension code as macros, they are written in the extension structure, so that anytime you try to load this extension in a PHP binary, they will be checked against the PHP binary's own numbers.
If they mismatch, then the extension will not load, and an error message will be displayed.

If we look at the extension C structure, it looks like this::

    zend_module_entry foo_module_entry = {
    #if ZEND_MODULE_API_NO >= 20010901
	    STANDARD_MODULE_HEADER,
    #endif
	    "foo",
	    foo_functions,
	    PHP_MINIT(foo),
	    PHP_MSHUTDOWN(foo),
	    NULL,
	    NULL,
	    PHP_MINFO(foo),
    #if ZEND_MODULE_API_NO >= 20010901
	    PHP_FOO_VERSION,
    #endif
	    STANDARD_MODULE_PROPERTIES
    };

What is interesting for us so far, is the ``STANDARD_MODULE_HEADER`` macro. If we expand it, we can see::

    #define STANDARD_MODULE_HEADER_EX sizeof(zend_module_entry), ZEND_MODULE_API_NO, ZEND_DEBUG, USING_ZTS
    #define STANDARD_MODULE_HEADER STANDARD_MODULE_HEADER_EX, NULL, NULL

Notice how ``ZEND_MODULE_API_NO``, ``ZEND_DEBUG``, ``USING_ZTS`` are used.

And now, let's foresee the C code part into PHP which actually loads extensions (truncated)::

    PHPAPI int php_load_extension(char *filename, int type, int start_now TSRMLS_DC) /* {{{ */
    {
	    void *handle;
	    char *libpath;
	    zend_module_entry *module_entry;
	    zend_module_entry *(*get_module)(void);
	    int error_type;
	    char *extension_dir;

        (...)

	    /* load dynamic symbol */
	    handle = DL_LOAD(libpath);
	    if (!handle) {
    #if PHP_WIN32
		    char *err = GET_DL_ERROR();
		    if (err && (*err != "")) {
			    php_error_docref(NULL TSRMLS_CC, error_type, "Unable to load dynamic library '%s' - %s", libpath, err);
			    LocalFree(err);
		    } else {
			    php_error_docref(NULL TSRMLS_CC, error_type, "Unable to load dynamic library '%s' - %s", libpath, "Unknown reason");
		    }
    #else
		    php_error_docref(NULL TSRMLS_CC, error_type, "Unable to load dynamic library '%s' - %s", libpath, GET_DL_ERROR());
		    GET_DL_ERROR(); /* free the buffer storing the error */
    #endif
		    efree(libpath);
		    return FAILURE;
	    }
	    efree(libpath);

	    get_module = (zend_module_entry *(*)(void)) DL_FETCH_SYMBOL(handle, "get_module");

        (...)

	    if (!get_module) {
		    DL_UNLOAD(handle);
		    php_error_docref(NULL TSRMLS_CC, error_type, "Invalid library (maybe not a PHP library) '%s'", filename);
		    return FAILURE;
	    }
	    module_entry = get_module();
	    if (module_entry->zend_api != ZEND_MODULE_API_NO) {
		    (...)
		    name		= module_entry->name;
		    zend_api	= module_entry->zend_api;

		    php_error_docref(NULL TSRMLS_CC, error_type,
				    "%s: Unable to initialize module\n"
				    "Module compiled with module API=%d\n"
				    "PHP    compiled with module API=%d\n"
				    "These options need to match\n",
				    name, zend_api, ZEND_MODULE_API_NO);
		    DL_UNLOAD(handle);
		    return FAILURE;
	    }
	    if(strcmp(module_entry->build_id, ZEND_MODULE_BUILD_ID)) {
		    php_error_docref(NULL TSRMLS_CC, error_type,
				    "%s: Unable to initialize module\n"
				    "Module compiled with build ID=%s\n"
				    "PHP    compiled with build ID=%s\n"
				    "These options need to match\n",
				    module_entry->name, module_entry->build_id, ZEND_MODULE_BUILD_ID);
		    DL_UNLOAD(handle);
		    return FAILURE;
        (...)

If you look at the default directory for PHP extensions, it should look like ``no-debug-non-zts-20090626``. As you'd have guessed, this directory is made of distinct parts joined together : debug mode, followed by thread safety information, followed by the Zend Module Api No.
So by default, PHP tries to help you navigating with extensions.

.. note::

    Usually, when you become an internal developper or an extension developper, you will usually have to play with the debug parameter, and if you have to deal with the Windows platform, threads will show up as well. You can end with compiling the same extension several times against several cases of those parameters.

Remember that every new major/minor version of PHP change parameters such as the PHP Api Version, that's why you need to recompile extensions against a newer PHP version.

.. code-block:: none

    > /path/to/php54/bin/phpize -v
    Configuring for:
    PHP Api Version:         20100412
    Zend Module Api No:      20100525
    Zend Extension Api No:   220100525

    > /path/to/php55/bin/phpize -v
    Configuring for:
    PHP Api Version:         20121113
    Zend Module Api No:      20121212
    Zend Extension Api No:   220121212

    > /path/to/php53/bin/phpize -v
    Configuring for:
    PHP Api Version:         20090626
    Zend Module Api No:      20090626
    Zend Extension Api No:   220090626

.. note::

    *Zend Module Api No* is itself built with a date using the *year.month.day* format. This is the date of the day the API changed and was tagged.
    *Zend Extension Api No* is the Zend version followed by *Zend Module Api No*.
