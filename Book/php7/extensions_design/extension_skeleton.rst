A look into a PHP extension and extension skeleton
==================================================

Here we detail what a PHP extension look like, and how to generate a skeleton using some tools. That will allow us to
use a skeleton code and hack into it, instead of creating every needed piece by hand from scratch.

We'll also detail how you could/should organize your extension files, how the engine loads them, and basically
everything you need to know about a PHP extension.

How the engine loads extensions
*******************************

You remember :doc:`the chapter about building PHP extensions <../build_system/building_extensions>`, so you know how
to compile/build it and install it.

You may build **statically compiled** extensions, those are extensions that are part of PHP's heart and melt into it.
They are not represented as *.so* files, but as *.o* objects that are linked into the final PHP executable (ELF). Thus,
such extensions cannot be disabled, they are part of the PHP executable body code : they are here, in, whatever you say
and do. Some extensions are required to be statically built, f.e *ext/core*, *ext/standard*, *ext/spl* and
*ext/mysqlnd* (non-exhaustive list).

You can find the list of statically compiled extensions by looking at the ``main/internal_functions.c`` that is
generated while you compile PHP. This step is detailed in
:doc:`the chapter about building PHP <../build_system/building_php>`.

Then, you may also build **dynamically loaded** extensions. Those are the famous *extension.so* files that are born at
the end of the individual compilation process. Dynamically loaded extensions offer the advantage to be pluggable and
unpluggable at runtime, and don't require a recompilation of all PHP to be enabled or disabled. The drawback is that
the PHP process startup time is longer when it must load .so files. But that's a matter of milliseconds and you don't
really suffer from that.

Another drawback of dynamically loaded extensions is the extension loading order. Some extensions may require other
ones to be loaded before them. Although this is not a good practice, we'll see that PHP extension system allows you to
declare dependencies to master such an order, but dependencies are usually a bad idea and should be avoided.

Last thing : PHP statically compiled extensions start before dynamically compiled ones. That means that their
``MINIT()`` is called before extensions.so files' ``MINIT()``.

When PHP starts, it quickly goes to parse its different INI files. If present, those later may declare extensions to
load using the *"extension=some_ext.so"* line reference.
PHP then collects every extension parsed from INI configuration, and will try to load them in the same order they've
been added to the INI file, until some extensions declared some dependencies (which will then be loaded before).

.. note:: If you use an operating system package manager, you may have noticed that packagers usually name their
          extension file with heading numbers, aka *00_ext.ini*, *01_ext.ini* etc... This is to master the order
          extensions will be loaded. Some uncommon extensions require a specific order to be run. We'd like to remind
          you that depending on other extensions to be loaded before yours is a bad idea.

To load extensions, `libdl <https://en.wikipedia.org/wiki/Dynamic_loading>`_ and its
`dlopen()/dlsym() <http://www.unix.com/man-page/All/3lib/libdl/>`_ functions are used.

The symbol that is looked for is the ``get_module()`` symbol, that means that you extension must export it to be loaded.
This is usually the case, as if you used the skeleton script (we'll foresee it in a minute), then that later generated
code using the ``ZEND_GET_MODULE(your_ext)`` macro, which looks like::

    #define ZEND_GET_MODULE(name) \
        BEGIN_EXTERN_C()\
        ZEND_DLEXPORT zend_module_entry *get_module(void) { return &name##_module_entry; }\
        END_EXTERN_C()

Like you can see, that macro when used declares a global symbol : the get_module() function that will get called by the
engine once wanting to load your extension.

.. note:: The source code PHP uses to load extensions is located in `zend_load_extension <https://github.com/php/
          php-src/blob/debd38f8511bcd4f72873f024221af17fca2bf1b/Zend/zend_extensions.c#L28>`_

What is a PHP extension ?
*************************

A PHP extension, not to be confused with a :doc:`Zend extension <zend_extensions>`, is set up by the usage of a
``zend_module_entry`` structure::

    struct _zend_module_entry {
        unsigned short size;                                /*
        unsigned int zend_api;                               * STANDARD_MODULE_HEADER
        unsigned char zend_debug;                            *
        unsigned char zts;                                   */

        const struct _zend_ini_entry *ini_entry;            /* Unused */
        const struct _zend_module_dep *deps;                /* Module dependencies */
        const char *name;                                   /* Module name */
        const struct _zend_function_entry *functions;       /* Module published functions */

        int (*module_startup_func)(INIT_FUNC_ARGS);         /*
        int (*module_shutdown_func)(SHUTDOWN_FUNC_ARGS);     *
        int (*request_startup_func)(INIT_FUNC_ARGS);         * Lifetime functions (hooks)
        int (*request_shutdown_func)(SHUTDOWN_FUNC_ARGS);    *
        void (*info_func)(ZEND_MODULE_INFO_FUNC_ARGS);       */

        const char *version;                                /* Module version */

        size_t globals_size;                                /*
    #ifdef ZTS                                               *
        ts_rsrc_id* globals_id_ptr;                          *
    #else                                                    * Globals management
        void* globals_ptr;                                   *
    #endif                                                   *
        void (*globals_ctor)(void *global);                  *
        void (*globals_dtor)(void *global);                  */

        int (*post_deactivate_func)(void);                   /* Rarely used lifetime hook */
        int module_started;                                  /* Has module been started (internal usage) */
        unsigned char type;                                  /* Module type (internal usage) */
        void *handle;                                        /* dlopen() returned handle */
        int module_number;                                   /* module number among others */
        const char *build_id;                                /* build id, part of STANDARD_MODULE_PROPERTIES_EX */
    };

The four first parameters have already been explained in
:doc:`the building extensions chapter <../build_system/building_extensions>`. They are usually filled-in using the
``STANDARD_MODULE_HEADER`` macro.

The ``ini_entry`` vector is actually unused. You :doc:`register INI entries <ini_settings>` using special macros.

Then you may declare dependencies, that means that your extension could need another extension to be loaded before it,
or could declare a conflict with another extensions. This is done using the ``deps`` field. In reality, this is very
uncommonly used, and more generally it is a bad practice to create dependencies across PHP extensions.

After that you declare a ``name``. Nothing to say, this name is the name of your extension (which can be different from
the name of its own *.so* file). Take care the name is case sensitive in most operations, we suggest you use something
short, lower case, with no spaces (to make things a bit easier).

Then come the ``functions`` field. It is a pointer to some PHP functions that extension wants to register into
the engine. We talked about that :doc:`in a dedicated chapter <php_functions>`.

Keeping-on come the 5 lifetime hooks. :doc:`See their dedicated chapter <php_lifecycle>`.

Your extension may publish a version number, as a ``char *``, using the ``version`` field. This field is only read as
part of your extension information, that is by phpinfo() or by the reflection API as
``ReflectionExtension::getVersion()``.

We next see a lot of fields about globals. Globals management :doc:`has a dedicated chapter <globals_management>`.

Finally the ending fields are usually part of the ``STANDARD_MODULE_PROPERTIES`` macro and you don't have to play with
them by hand. The engine will give you a ``module_number`` for its internal management, and the extension type will be
set to ``MODULE_PERSISTENT``. It could be ``MODULE_TEMPORARY`` as if you extension were loaded using PHP's userland
``dl()`` function, but that use-case is very uncommon, doesn't work with every SAPI and temporary extensions usually
lead to many problems into the engine.

Generating extension skeleton with scripts
******************************************

Now we'll see how to generate an extension skeleton so that you may start a new extension with some minimal content
and structure you won't be forced to create by hand from scratch.

the skeleton generator script is located into
`php-src/ext/ext_skel <https://github.com/php/php-src/blob/27d681435174433c3a9b0b8325361dfa383be0a6/ext/ext_skel>`_ and
the structure it uses as a template is stored into
`php-src/ext/skeleton <https://github.com/php/php-src/tree/27d681435174433c3a9b0b8325361dfa383be0a6/ext/skeleton>`_

.. note:: The script and the structure move a little bit as PHP versions move forward.

You can analyze those scripts to see how they work, but the basic usage is:

.. code-block:: shell

    > cd /tmp
    /tmp> /path/to/php/ext/ext_skel --skel=/path/to/php/ext/skeleton --extname=pib
    [ ... generating ... ]
    /tmp> tree pib/
    pib/
    ├── config.m4
    ├── config.w32
    ├── CREDITS
    ├── EXPERIMENTAL
    ├── php_pib.h
    ├── pib.c
    ├── pib.php
    └── tests
        └── 001.phpt
    /tmp>

You can see a very basic an minimal structure that got generated. You've learnt in the building extension chapter that
the to-be-compiled files of your extension must be declared into *config.m4*. The skeleton only generated
*<your-ext-name>.c* file. For the example, we called the extension *"pib"* so we got a *pib.c* file and we must
uncomment the *--enable-pib* line in *config.m4* for it to get compiled.

Every C file comes with a header file (usually). Here, the structure is *php_<your-ext-name>.h* , so *php_pib.h* for
us. Don't change that name, the building system expects such a naming convention for the header file.

You can see that a minimal test structure has been generated as well.

Let's open *pib.c*. In there, everything is commented out, so we won't have too many lines to write here.

Basically, we can see that the module symbol needed by the engine to load our extension is published here::

    #ifdef COMPILE_DL_PIB
    #ifdef ZTS
    ZEND_TSRMLS_CACHE_DEFINE()
    #endif
    ZEND_GET_MODULE(pib)
    #endif

The ``COMPILE_DL_<YOUR-EXT-NAME>`` macro is defined if you pass *--enable-<my-ext-name>* flag to configure script. We
also see that in case of ZTS mode, the TSRM local storage pointer is defined as part of ``ZEND_TSRMLS_CACHE_DEFINE()``
macro.

After that, there is nothing more to say as everything is commented out and should be clear to you.

New age of the extension skeleton generator
*******************************************

Since `this commit <https://github.com/php/php-src/commit/f35f45906eac34498c7720326fb9da9fde960871>`_ and the
extension skeleton generator had took a new style :


    It will now run on Windows without Cygwin and other nonsense.
    It no longer includes a way to generate XML documentation (the PHP documentation utilities already got tools for that
    in svn under phpdoc/doc-base) and it no longer support function stubs.

and here is the available options :

.. code-block:: shell

    php ext_skel.php --ext <name> [--experimental] [--author <name>]
                     [--dir <path>] [--std] [--onlyunix]
                     [--onlywindows] [--help]

      --ext <name>		The name of the extension defined as <name>
      --experimental	Passed if this extension is experimental, this creates
                            the EXPERIMENTAL file in the root of the extension
      --author <name>       Your name, this is used if --header is passed and
                            for the CREDITS file
      --dir <path>		Path to the directory for where extension should be
                            created. Defaults to the directory of where this script
     			lives
      --std			If passed, the standard header and vim rules footer used
     			in extensions that is included in the core, will be used
      --onlyunix		Only generate configure scripts for Unix
      --onlywindows		Only generate configure scripts for Windows
      --help                This help

The new extension skeleton generator will generate skeleton with three fixed functions,
you may define any others functions and change the concrete body as you want.

.. note:: Remember that the new ext_skel is no longer support proto files.

Publishing API
**************

If we open the header file, we can see those lines::

    #ifdef PHP_WIN32
    #	define PHP_PIB_API __declspec(dllexport)
    #elif defined(__GNUC__) && __GNUC__ >= 4
    #	define PHP_PIB_API __attribute__ ((visibility("default")))
    #else
    #	define PHP_PIB_API
    #endif

Those lines define a macro named ``PHP_<EXT-NAME>_API`` (for us ``PHP_PIB_API``) and it resolves to the
`GCC custom attribute <https://gcc.gnu.org/onlinedocs/gcc/Common-Function-Attributes.html#Common-Function-Attributes>`_
visibility("default").

In C, you can tell the linker to hide every symbol from the final object. This is what's done in PHP, for every
symbol, not only static ones (which are by definition not published).

.. warning:: The default PHP compilation line tells the compiler to hide every symbol and not export them.

You should then "unhide" the symbols you'd like your extension to publish for those to be used in other extensions or
other parts of the final ELF file.

.. note:: Remember that you can read published and hidden symbol of an ELF using ``nm`` under Unix.

We can't explain those concepts in deep here, perhaps such links could help you ?

* https://gcc.gnu.org/wiki/Visibility
* http://www.iecc.com/linker/linker10.html
* https://www.akkadia.org/drepper/dsohowto.pdf
* http://www.faqs.org/docs/Linux-HOWTO/Program-Library-HOWTO.html
* https://developer.apple.com/library/content/documentation/DeveloperTools/Conceptual/DynamicLibraries/000-Introduction/Introduction.html

So basically, if you want a C symbol of yours to be publicly available to other extensions, you should declare it
using the special ``PHP_PIB_API`` macro. The traditional use-case for that is to publish the classes symbols
(``zend_class_entry*`` type) so that other extensions can hook into your own published classes and replace some of their
handlers.

.. note:: Please, note that this only works with the traditional PHP. If you use
          :doc:`a PHP from a Linux distribution <../build_system/building_php>`, those are patched to resolve symbols
          at load time and not lazilly, thus this trick doesn't work.
