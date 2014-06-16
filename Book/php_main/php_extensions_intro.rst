The PHP extensions system
=========================

This chapter will try to give you a full view of how PHP extensions work, how they register against the engine
(there exist several hooks), how you can manage dependencies between extensions and finally what you can and can't do
with an extension. We will also give you details about the two different kinds of extensions PHP supports : PHP
extensions and Zend extensions.

.. note::

    If you are interested in concepts such as compiling an extension (statically or dynamically), playing with the PECL
    tool or managing extensions versions, then you should go to :doc:`../build_system/building_extensions`.

There exists two kinds of extensions to be loaded into PHP. Known as *PHP extensions* and *Zend extensions*, they are
not exactly the same thing, even though they share lots of concepts.
Basically, Zend extensions can hook at Zend Engine levels whereas PHP extensions cannot.
What this means is that if you want to play with very low-level concepts into the engine, you'll have to go for a
Zend extension. For every other purpose, a PHP extension will be enough.
Zend extensions are somehow tricky, and generally need the author to have deeper knowledge about PHP internals.
We will mainly talk about PHP extensions here, because you will notice that you can do so many things with "just" PHP
extensions, than studying Zend extensions will just be an easy game once you'll master PHP extensions.
Among others, Zend extensions are mainly needed if you want to change the behavior of the Zend Execution Engine, or if
you have to put your fingers into the Zend Memory Manager.

Goals and capabilities of PHP extensions
----------------------------------------

Let's first have a detailed look at the PHP extension C structure: ``zend_module_entry``::

    typedef struct _zend_module_entry zend_module_entry;
    typedef struct _zend_module_dep zend_module_dep;

    struct _zend_module_entry {
	    unsigned short size;                               /* Usually sizeof(zend_module_entry) */
	    unsigned int zend_api;                             /* Zend API number used */
	    unsigned char zend_debug;                          /* Zend debug flag */
	    unsigned char zts;                                 /* Zend Thread Safe flag */
	    const struct _zend_ini_entry *ini_entry;           /* INI entries vector */
	    const struct _zend_module_dep *deps;               /* Extension dependencies */
	    const char *name;                                  /* Extension name */
	    const struct _zend_function_entry *functions;      /* Function entries vector */
	    int (*module_startup_func)(INIT_FUNC_ARGS);        /* MINIT hook */
	    int (*module_shutdown_func)(SHUTDOWN_FUNC_ARGS);   /* MSHUTDOWN hook */
	    int (*request_startup_func)(INIT_FUNC_ARGS);       /* RINIT hook */
	    int (*request_shutdown_func)(SHUTDOWN_FUNC_ARGS);  /* RSHUTDOWN hook */
	    void (*info_func)(ZEND_MODULE_INFO_FUNC_ARGS);     /* INFO hook, for phpinfo */
	    const char *version;                               /* Version number, as chars */
	    size_t globals_size;                               /* Globals vector size */
    #ifdef ZTS
	    ts_rsrc_id* globals_id_ptr;                        /* Globals vector when ZTS */
    #else
	    void* globals_ptr;                                 /* Globals vector when non ZTS */
    #endif
	    void (*globals_ctor)(void *global TSRMLS_DC);      /* Globals constructor hook */
	    void (*globals_dtor)(void *global TSRMLS_DC);      /* Globals destructor hook */
	    int (*post_deactivate_func)(void);                 /* */
	    int module_started;                                /* Extension started switch 0/1 */
	    unsigned char type;                                /* Extension type, PERSISTENT or TEMPORARY */
	    void *handle;                                      /* Extension's handle (dlopen() handle ) */
	    int module_number;                                 /* Extension's internal number */
	    const char *build_id;                              /* buildid : merge of other settings */
    };

    struct _zend_module_dep {
	    const char *name;       /* module name */
	    const char *rel;        /* version relationship: NULL (exists), lt|le|eq|ge|gt (to given version) */
	    const char *version;    /* version */
	    unsigned char type;     /* dependency type */
    };

By analyzing the structure, among some details, we can tell that a PHP extension:
    * May add some INI entries to PHP configuration, ``const struct _zend_ini_entry *ini_entry;`` is used
    * Is managed by some dependency system, ``const struct _zend_module_dep *deps;`` is used
    * May add some functions to PHP, ``const struct _zend_function_entry *functions`` is used in that goal
    * May add some informations to "phpinfo" though the help of ``void (*info_func)(ZEND_MODULE_INFO_FUNC_ARGS)``
    * May run any code at 5 triggered hooks
    * May add at startup and destroy at shutdown global C variables, using ``void (*globals_ctor)(void *global TSRMLS_DC)``
      and its sister ``dtor``

All those parts are going to be covered now.

Extensions loading mechanism
----------------------------

Here we are going to detail how PHP extensions get registered into PHP. The process can be divided into two main parts:
    * Loading extension
    * Activating extension

When we talk about extensions, the first thing the engine does is load them. It will first load statically compiled
extensions, then it will finish with dynamically loaded ones. This may feel somehow logical, but that is important to
remember, mainly when it comes to talk about extensions dependencies.
The engine loads statically compiled extensions, then it parses the different configuration files (INI files), looking
for the special token *"extension="* and then builds an extension list and load them in the exact same order they've been
declared in the INI files. If the engine parses several INI files, usually this is done in alphabetical order.

.. important::

    It is important to understand that extensions will be loaded in the order they appear in the different configuration
    files.

Here are the tasks performed by the the engine when it loads an extension:

    * Checks for extension dependencies, but only against conflicts, so it does not load any other extension than the
      one it's been called with
    * Checks if the extension has already been registered, if it is the case, emits a warning
    * Registers the PHP extension functions into the global function table, calling
      ``zend_register_functions(module->functions)``

The code that loads extensions looks like this::

    ZEND_API zend_module_entry* zend_register_module_ex(zend_module_entry *module TSRMLS_DC)
    {
        int name_len;
        char *lcname;
        zend_module_entry *module_ptr;
        if (!module) {
            return NULL;
        }
        /* Check module dependencies */
        if (module->deps) {
            const zend_module_dep *dep = module->deps;

            while (dep->name) {
                if (dep->type == MODULE_DEP_CONFLICTS) {
                    name_len = strlen(dep->name);
                    lcname = zend_str_tolower_dup(dep->name, name_len);

                    if (zend_hash_exists(&module_registry, lcname, name_len+1)) {
                        efree(lcname);
                        /* TODO: Check version relationship */
                        zend_error(E_CORE_WARNING, "Cannot load module '%s' because conflicting module '%s' is already
                                                   loaded", module->name, dep->name);
                        return NULL;
                    }
                    efree(lcname);
                }
                ++dep;
            }
        }

        name_len = strlen(module->name);
        lcname = zend_str_tolower_dup(module->name, name_len);

        if (zend_hash_add(&module_registry, lcname, name_len+1, (void *)module, sizeof(zend_module_entry),
                          (void**)&module_ptr)==FAILURE) {
            zend_error(E_CORE_WARNING, "Module '%s' already loaded", module->name);
            efree(lcname);
            return NULL;
        }
        efree(lcname);
        module = module_ptr;
        EG(current_module) = module;

        if (module->functions && zend_register_functions(NULL, module->functions, NULL, module->type TSRMLS_CC)==FAILURE) {
            EG(current_module) = NULL;
            zend_error(E_CORE_WARNING,"%s: Unable to register functions, unable to load", module->name);
            return NULL;
        }

        EG(current_module) = NULL;
        return module;
    }

.. note::

    In the source, you will find that a *"module"* is a PHP extension, and an *"extension"* is a Zend extension.
    Get used to that somehow confusing vocabulary now.

Each extension has two interesting members here: ``int module_started`` and ``int module_number``. The first one is
easy : 0 when the extension has not been *activated* yet, 1 otherwise.
``module_number`` is an integer which is incremented by one by the engine each time it has to deal with extension
registration, so you dont have to fill it. It will later be used to recognize each extension's settings when they will
all be merged into global tables. For example, when an extension registers INI settings, those settings are added to a
big global table and the extension ``module_number`` is used at this time so that you can later tell which setting belong
to which extension.

The second part of extension management is activation. Once loaded, extensions get activated, the engine calls several
hooks against them, and some code will be run.
Here is the step where the engine will effectively sort the PHP extensions in an order that make the dependencies be
activated in a specific order.

``zend_startup_modules()`` does the job of activating PHP extensions. It starts by sorting them in the
``module_registry`` Hashtable calling a sorting callback. This sort process will check for dependencies requirement,
and sort the registry in a way that dependency requirements are activated first. Then comes the "real" activation:
``zend_startup_module_ex()`` is called on the freshly sorted extensions registry. It checks the extension field
``module_started`` to be sure not to activate an extension more that once, then checks dependencies against requirements.
If an extension requires another to be registered before itself and it's not the case, then an error will show up.

Understanding extensions' dependencies
--------------------------------------

As any extension may virtually do anything it wants within PHP, some extensions could conflict with each other, and thus
have to be declared incompatible and should never be loaded at the same time in the same PHP instance.
In parallel, a very big task could be split into several extensions, which then would require each other's presence.
The Zend extension dependency system may respond those cases, however it is not perfect, and it got tricks you should
be aware of if you want to save some future OOPS times.

For dynamically loaded extensions, the structure ``zend_module_dep`` may be used. Each extension can attach
``zend_module_dep`` structures to its main ``zend_module_entry`` structure, and fill each of them with extensions dependencies
informations. Each information must have a unique type: conflict, required or optional::

    #define MODULE_DEP_REQUIRED		1
    #define MODULE_DEP_CONFLICTS	2
    #define MODULE_DEP_OPTIONAL		3

    #define ZEND_MOD_REQUIRED_EX(name, rel, ver)	{ name, rel, ver, MODULE_DEP_REQUIRED  },
    #define ZEND_MOD_CONFLICTS_EX(name, rel, ver)	{ name, rel, ver, MODULE_DEP_CONFLICTS },
    #define ZEND_MOD_OPTIONAL_EX(name, rel, ver)	{ name, rel, ver, MODULE_DEP_OPTIONAL  },

    #define ZEND_MOD_REQUIRED(name)	    ZEND_MOD_REQUIRED_EX(name, NULL, NULL)
    #define ZEND_MOD_CONFLICTS(name)	ZEND_MOD_CONFLICTS_EX(name, NULL, NULL)
    #define ZEND_MOD_OPTIONAL(name)	    ZEND_MOD_OPTIONAL_EX(name, NULL, NULL)

    #define ZEND_MOD_END { NULL, NULL, NULL, 0 }

    struct _zend_module_dep {
	    const char *name;		/* module name */
	    const char *rel;		/* version relationship: NULL (exists), lt|le|eq|ge|gt (to given version) */
	    const char *version;	/* version */
	    unsigned char type;		/* dependency type */
    };

Conflicts are checked when the extension is registered, and as they are registered in a specific order, here is a first
gotcha you may remember.

.. warning::

    If you declare an extension "Foo" as beeing in conflict with an extension "Bar", then for the conflict to be
    detected and checked against, "Bar" must be registered before "Foo" in the engine, so that when "Foo" is registered,
    "Bar" is already present into the module registry. It is then recommanded to name
    the "Bar" file "00_bar.so", and the Foo file "01_foo.so", because alphabetical order is used to load PHP
    extensions from configuration files.

Here is an example showing how to declare conflicts between two extensions. In this example, the "Foo" extension is
in conflict with the "Bar" extension, but not the opposite (Usually, a conflict is two-way, but the extensions can be
developped by different people not knowing each other, thus ending in one-way declared conflicts)

.. code-block:: c

    /* Foo extension declarations */

    static const zend_module_dep foo_deps[] = { /* {{{ */
	    ZEND_MOD_CONFLICTS("Bar") /* Foo conflicts with Bar */
	    ZEND_MOD_END
    };

    zend_module_entry exta_module_entry = {
	    STANDARD_MODULE_HEADER_EX,
	    NULL,
	    foo_deps, /* dependencies vector */
	    "Foo",
	    Foo_functions,
	    PHP_MINIT(Foo),
	    PHP_MSHUTDOWN(Foo),
	    PHP_RINIT(Foo),
	    PHP_RSHUTDOWN(Foo),
	    PHP_MINFO(Foo),
	    "0.1",
	    STANDARD_MODULE_PROPERTIES
    };

Now, if you first load "Bar", then "Foo", you'll end with a message like this:

.. code-block:: none

    PHP Warning:  Cannot load module 'Foo' because conflicting module 'Bar' is already loaded in Unknown on line 0

If you first load "Foo", thus not having "Bar" loaded yet, it is not possible for the mechanism to detect the conflict, and
you'll end with both extension beeing loaded, expect some mess...

.. note::

    Extension names are lowercased when registered and compared, thus the system is case insensitive.

Now that we know how to declare conflicts, and that we remember conflicts are checked at extension registration and
may depend on registration order (default alphabetical), let's see together how to manage extensions requirement
dependencies, which happen to be resolved at extension activation time.

This time, "Foo" still conflicts with "Bar", but it also requires the mandatory presence of "Baz" extension, as it will,
for our use-case, use some services provided by "Baz".
Here is a declaration::

    /* Foo extension declarations */

    static const zend_module_dep foo_deps[] = { /* {{{ */
	    ZEND_MOD_CONFLICTS("Bar") /* Foo conflicts with Bar */
	    ZEND_MOD_REQUIRED("Baz")  /* Foo absolutly needs Baz to work */
	    ZEND_MOD_END
    };

    /* ... */

What is cool with dependency requirements, is that whatever the order the extensions got registered, they will be
activated in an order such that dependency requirements are loaded first. So for our above example, "Foo" declares
needing "Baz" to be both registered (sure) and activated before comes its own activation turn.
The engine will then activate "Baz" before activating "Foo".

.. warning::

    Do not declare recursive dependencies. PHP will hang.

You may have noticed two more concepts when dealing with extension dependencies: optionnal dependencies and dependencies
against specific versions.
Too bad, those two concepts are actually useless.
Extension dependencies against specific versions (the ``char *rel`` field) has never been implemented, but it is
planned for a next PHP version.
About optional dependency type (``ZEND_MOD_OPTIONAL``), it actually does the same as the "required" type. The only
difference is when you use the Reflection API, it shows "optional", so actually, this is just a hint for persons.

Extensions' lifetime into PHP
-----------------------------

Now you know about PHP extensions main structures, dependency management, compiling and loading, let's have a glance at
extensions' lifetime, which is tied to PHP's own lifetime.

PHP has been designed so that one instance should be able to treat several requests, forgetting everything between them.
If you carefully read its source code, you will clearly notice that.
PHP starts up, then it enters into a loop which will be triggered by each request. Depending on the SAPI and some
configuration, one PHP image may be able to treat exactly one request (the CLI SAPI usually does that) to virtually
an infinite number.
Extensions following PHP's lifetime, they will be triggered at different moments, and they should perform some
specific actions.
You should as well remember that usually PHP units are processes though they can be threads. For example, under Windows
platforms, PHP units of work are threads whereas usually under Unix systems they would be pieces of processes.
Usual precautions should be taken when talking about threads, especially regarding global variables for which PHP
supplies special hooks and macros.

Extensions' hooks
#################
